/// Textures of every shape WebGL2 has, and writes into any level and layer
/// of them — `GraphicsDevice.createTexture` and
/// `GraphicsDevice.writeTexture`.
///
/// **Rows are counted the way the rest of this backend counts them.** A
/// texture a pass draws into keeps its picture's top at the *last* texel row
/// here, because GL's framebuffer origin is the bottom left; one filled from
/// bytes keeps the first row it was given at row zero. `WebGlTexture.rendered`
/// carries which kind a texture is, `readPixels` flips the first kind and not
/// the second, and the writes in this file follow the same rule
/// `overwriteTexture` does: a region is stated from the top of the picture,
/// and its rows go in reversed into a texture made to be drawn into, so a
/// region written and read back comes back the way up it went in.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

import 'webgl_formats.dart';
import 'webgl_resources.dart';
import 'webgl_types.dart';

/// The size of level [mipLevel] of [texture]: width, height, and the layers
/// (or 3D slices, which halve with the level; or six cube faces) it holds.
({int width, int height, int layers}) webglLevelExtent(
  TextureHandle texture,
  int mipLevel,
) {
  int at(int base) {
    final size = base >> mipLevel;
    return size < 1 ? 1 : size;
  }

  return (
    width: at(texture.width),
    height: at(texture.height),
    layers: switch (texture.dimension) {
      TextureDimension.d3 => at(texture.depthOrArrayLayers),
      TextureDimension.cube => 6,
      _ => texture.depthOrArrayLayers,
    },
  );
}

/// The GL target a texture of [dimension] is bound as, or null for the two
/// shapes WebGL2 does not have.
int? webglTargetOf(TextureDimension dimension) => switch (dimension) {
  TextureDimension.d2 => web.WebGLRenderingContext.TEXTURE_2D,
  TextureDimension.d2Array => web.WebGL2RenderingContext.TEXTURE_2D_ARRAY,
  TextureDimension.d3 => web.WebGL2RenderingContext.TEXTURE_3D,
  TextureDimension.cube => web.WebGLRenderingContext.TEXTURE_CUBE_MAP,
  // No 1D texture in GL ES at all, and no cube array before ES 3.2.
  TextureDimension.d1 || TextureDimension.cubeArray => null,
};

/// A texture as [descriptor] says, allocated with `texStorage2D` or
/// `texStorage3D` and nothing in it. The caller has already refused the
/// shapes and usages this backend does not have; what is checked here is
/// what is wrong with the descriptor itself, as an [ArgumentError].
TextureHandle webglCreateTextureWithDescriptor(
  web.WebGL2RenderingContext gl,
  List<web.WebGLTexture> persistentTextures,
  List<web.WebGLRenderbuffer> persistentRenderbuffers,
  CompressedTextureSupport compressed,
  TextureDescriptor descriptor,
) {
  final format = descriptor.format;
  final dimension = descriptor.dimension;
  final internal = format.isCompressed
      ? compressedTextureFormatToGl(format, compressed)
      : textureFormatToGl(format);
  final target = webglTargetOf(dimension)!;
  final layers = descriptor.depthOrArrayLayers;
  if (dimension == TextureDimension.d2 && layers != 1) {
    throw ArgumentError.value(
      layers,
      'depthOrArrayLayers',
      'a 2D texture has one layer; ask for TextureDimension.d2Array',
    );
  }
  if (dimension == TextureDimension.cube &&
      (layers != 6 || descriptor.width != descriptor.height)) {
    throw ArgumentError(
      'a cube is six square faces: ${descriptor.width}x${descriptor.height}x'
      '$layers is not one',
    );
  }
  if (dimension == TextureDimension.d3 &&
      (format.isCompressed || format.isDepthOrStencil)) {
    // GL ES 3.0 allocates neither in a 3D texture: block-compressed formats
    // are 2D and 2D-array only, and depth is never volumetric.
    throw UnsupportedError(
      'WebGL2 makes no 3D texture in TextureFormat.${format.name}: '
      'compressed and depth formats are 2D, 2D-array and cube only there.',
    );
  }
  final deepest = <int>[
    descriptor.width,
    descriptor.height,
    if (dimension == TextureDimension.d3) layers,
  ].reduce((int a, int b) => a > b ? a : b);
  if (descriptor.mipLevelCount > deepest.bitLength) {
    throw ArgumentError.value(
      descriptor.mipLevelCount,
      'mipLevelCount',
      'is longer than the ${deepest.bitLength}-level chain of a texture '
          'this size',
    );
  }

  TextureHandle handleFor(WebGlTexture backend) => wrapTexture(
    backend: backend,
    width: descriptor.width,
    height: descriptor.height,
    format: format,
    sampleCount: descriptor.sampleCount,
    storageMode: descriptor.storageMode,
    type: dimension == TextureDimension.cube
        ? TextureType.textureCube
        : TextureType.texture2D,
    dimension: dimension,
    depthOrArrayLayers: layers,
    mipLevelCount: descriptor.mipLevelCount,
    usage: descriptor.usage,
  );

  if (descriptor.sampleCount > 1 ||
      descriptor.storageMode == StorageMode.deviceTransient) {
    // A renderbuffer, exactly as `createTexture` makes one: WebGL2 samples
    // no multisampled texture, and tile memory has no texture to be.
    if (dimension != TextureDimension.d2 || descriptor.mipLevelCount != 1) {
      throw ArgumentError(
        'a multisampled or deviceTransient texture is 2D with one level on '
        'WebGL2, where it is a renderbuffer',
      );
    }
    final made = webglCreateTexture(
      gl,
      persistentTextures,
      persistentRenderbuffers,
      RenderTargetDescriptor(
        width: descriptor.width,
        height: descriptor.height,
        format: format,
        sampleCount: descriptor.sampleCount,
        storageMode: descriptor.storageMode,
      ),
    );
    return handleFor(made.backend as WebGlTexture);
  }

  final texture = gl.createTexture();
  if (texture != null) persistentTextures.add(texture);
  webglBindForUpload(gl, target, texture);
  if (dimension == TextureDimension.d2Array ||
      dimension == TextureDimension.d3) {
    gl.texStorage3D(
      target,
      descriptor.mipLevelCount,
      internal,
      descriptor.width,
      descriptor.height,
      layers,
    );
  } else {
    gl.texStorage2D(
      target,
      descriptor.mipLevelCount,
      internal,
      descriptor.width,
      descriptor.height,
    );
  }
  return handleFor(
    WebGlTexture(
      texture: texture,
      target: target,
      // Drawn into when it may be: the same answer `createTexture` gives the
      // pool's targets. A compressed format is never an attachment.
      rendered:
          descriptor.usage.contains(TextureUsage.renderTarget) &&
          !format.isCompressed,
    ),
  );
}

/// [data] into [region] of level [mipLevel] of [target]. See
/// `GraphicsDevice.writeTexture` and the library note for which way up.
///
/// The bytes are repacked on the host into tight rows before they reach GL
/// — reversed for a drawn texture, and with [bytesPerRow]'s padding taken
/// out — so one `texSubImage*` call takes the whole region with an unpack
/// alignment of one, and nothing about the context's pixel-store state
/// outlives the call.
void webglWriteTexture(
  web.WebGL2RenderingContext gl,
  CompressedTextureSupport compressed,
  TextureHandle target,
  ByteData data, {
  TextureRegion? region,
  int mipLevel = 0,
  int? bytesPerRow,
}) {
  final backend = target.backend as WebGlTexture;
  final texture = backend.texture;
  if (texture == null) {
    throw ArgumentError.value(
      target,
      'target',
      'is attachment-only (multisampled or deviceTransient) and has no '
          'texels to write on WebGL2',
    );
  }
  // Against the chain a texture this size could have rather than
  // `mipLevelCount`: the creators that predate it leave it at one whatever
  // chain they allocated. GL refuses a level past the real one.
  final chain =
      (target.width > target.height ? target.width : target.height).bitLength;
  if (mipLevel < 0 || mipLevel >= chain) {
    throw ArgumentError.value(mipLevel, 'mipLevel', 'is not a level here');
  }
  final extent = webglLevelExtent(target, mipLevel);
  final box =
      region ??
      TextureRegion(
        width: extent.width,
        height: extent.height,
        depthOrArrayLayers: extent.layers,
      );
  if (box.x < 0 ||
      box.y < 0 ||
      box.z < 0 ||
      box.width < 1 ||
      box.height < 1 ||
      box.depthOrArrayLayers < 1 ||
      box.x + box.width > extent.width ||
      box.y + box.height > extent.height ||
      box.z + box.depthOrArrayLayers > extent.layers) {
    throw ArgumentError(
      'writeTexture: $box does not fit inside level $mipLevel, '
      '${extent.width}x${extent.height}x${extent.layers}',
    );
  }

  if (target.format.isCompressed) {
    _writeCompressed(
      gl,
      compressed,
      target,
      texture,
      data,
      box,
      mipLevel: mipLevel,
      extent: extent,
      bytesPerRow: bytesPerRow,
    );
    return;
  }

  final transfer = webglTransferOf(target.format);
  if (transfer == null) {
    throw UnsupportedError(
      'writeTexture: WebGL2 fills no texture in TextureFormat.'
      '${target.format.name} from bytes',
    );
  }
  final rowBytes = box.width * transfer.texelBytes;
  final tight = _repack(
    data,
    rowBytes: rowBytes,
    stride: bytesPerRow ?? rowBytes,
    rows: box.height,
    images: box.depthOrArrayLayers,
    flip: backend.rendered,
  );
  final y = backend.rendered ? extent.height - box.y - box.height : box.y;

  webglBindForUpload(gl, backend.target, texture);
  gl.pixelStorei(web.WebGLRenderingContext.UNPACK_ALIGNMENT, 1);
  switch (target.dimension) {
    case TextureDimension.cube:
      final face = rowBytes * box.height;
      for (var i = 0; i < box.depthOrArrayLayers; i++) {
        gl.texSubImage2D(
          web.WebGLRenderingContext.TEXTURE_CUBE_MAP_POSITIVE_X + box.z + i,
          mipLevel,
          box.x,
          y,
          box.width.toJS,
          box.height.toJS,
          transfer.format.toJS,
          transfer.type,
          webglTransferView(
            ByteData.sublistView(tight, i * face, (i + 1) * face),
            transfer.type,
          ),
        );
      }
    case TextureDimension.d2Array || TextureDimension.d3:
      gl.texSubImage3D(
        backend.target,
        mipLevel,
        box.x,
        y,
        box.z,
        box.width,
        box.height,
        box.depthOrArrayLayers,
        transfer.format,
        transfer.type,
        webglTransferView(ByteData.sublistView(tight), transfer.type),
      );
    case TextureDimension.d2 ||
        TextureDimension.d1 ||
        TextureDimension.cubeArray:
      gl.texSubImage2D(
        web.WebGLRenderingContext.TEXTURE_2D,
        mipLevel,
        box.x,
        y,
        box.width.toJS,
        box.height.toJS,
        transfer.format.toJS,
        transfer.type,
        webglTransferView(ByteData.sublistView(tight), transfer.type),
      );
  }
  gl.pixelStorei(web.WebGLRenderingContext.UNPACK_ALIGNMENT, 4);
}

/// The compressed half of [webglWriteTexture]: whole blocks only, never
/// flipped — a block-compressed texture is never drawn into, so it is
/// always stored the way it was given.
void _writeCompressed(
  web.WebGL2RenderingContext gl,
  CompressedTextureSupport compressed,
  TextureHandle target,
  web.WebGLTexture texture,
  ByteData data,
  TextureRegion box, {
  required int mipLevel,
  required ({int width, int height, int layers}) extent,
  required int? bytesPerRow,
}) {
  final layout = target.format.blockLayout;
  bool blockAligned(int origin, int size, int block, int edge) =>
      origin % block == 0 && (size % block == 0 || origin + size == edge);
  if (!blockAligned(box.x, box.width, layout.blockWidth, extent.width) ||
      !blockAligned(box.y, box.height, layout.blockHeight, extent.height)) {
    throw ArgumentError(
      'writeTexture: $box does not cover whole '
      '${layout.blockWidth}x${layout.blockHeight} blocks of '
      'TextureFormat.${target.format.name}',
    );
  }
  final blocksWide = (box.width + layout.blockWidth - 1) ~/ layout.blockWidth;
  final blocksHigh =
      (box.height + layout.blockHeight - 1) ~/ layout.blockHeight;
  final rowBytes = blocksWide * layout.bytesPerBlock;
  final tight = _repack(
    data,
    rowBytes: rowBytes,
    stride: bytesPerRow ?? rowBytes,
    rows: blocksHigh,
    images: box.depthOrArrayLayers,
    flip: false,
  );
  final internal = compressedTextureFormatToGl(target.format, compressed);
  final backend = target.backend as WebGlTexture;
  webglBindForUpload(gl, backend.target, texture);
  switch (target.dimension) {
    case TextureDimension.cube:
      final face = rowBytes * blocksHigh;
      for (var i = 0; i < box.depthOrArrayLayers; i++) {
        gl.compressedTexSubImage2D(
          web.WebGLRenderingContext.TEXTURE_CUBE_MAP_POSITIVE_X + box.z + i,
          mipLevel,
          box.x,
          box.y,
          box.width,
          box.height,
          internal,
          Uint8List.sublistView(tight, i * face, (i + 1) * face).toJS,
        );
      }
    case TextureDimension.d2Array || TextureDimension.d3:
      gl.compressedTexSubImage3D(
        backend.target,
        mipLevel,
        box.x,
        box.y,
        box.z,
        box.width,
        box.height,
        box.depthOrArrayLayers,
        internal,
        tight.toJS,
      );
    case TextureDimension.d2 ||
        TextureDimension.d1 ||
        TextureDimension.cubeArray:
      gl.compressedTexSubImage2D(
        web.WebGLRenderingContext.TEXTURE_2D,
        mipLevel,
        box.x,
        box.y,
        box.width,
        box.height,
        internal,
        tight.toJS,
      );
  }
}

/// [images] images of [rows] rows, [stride] bytes apart in [data], as tight
/// rows of [rowBytes] — each image's rows reversed when [flip] is set.
/// Throws an [ArgumentError] when [data] is too short for the region.
Uint8List _repack(
  ByteData data, {
  required int rowBytes,
  required int stride,
  required int rows,
  required int images,
  required bool flip,
}) {
  if (stride < rowBytes) {
    throw ArgumentError.value(
      stride,
      'bytesPerRow',
      'is shorter than one row of the region ($rowBytes bytes)',
    );
  }
  final needed = stride * (rows * images - 1) + rowBytes;
  if (data.lengthInBytes < needed) {
    throw ArgumentError(
      'writeTexture: ${data.lengthInBytes} bytes is short of the $needed the '
      'region needs at $stride bytes a row',
    );
  }
  final source = Uint8List.sublistView(data);
  final out = Uint8List(rowBytes * rows * images);
  for (var image = 0; image < images; image++) {
    for (var row = 0; row < rows; row++) {
      final from = (image * rows + row) * stride;
      final to = (image * rows + (flip ? rows - 1 - row : row)) * rowBytes;
      out.setRange(to, to + rowBytes, source, from);
    }
  }
  return out;
}
