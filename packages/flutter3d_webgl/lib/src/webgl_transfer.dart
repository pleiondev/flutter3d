/// Copies between buffers and textures — `GraphicsDevice.beginTransferPass`.
///
/// **Issued as they are recorded, like everything else on this backend.**
/// WebGL has no command buffer to defer into (see `webgl_encoder.dart`), so
/// a copy reaches the context when it is called and [WebGlTransferEncoder.submit]
/// only closes the pass. The order the contract promises — passes in the
/// order they were submitted — is the order the engine calls in, here as
/// for a render pass.
///
/// **Rows are the picture's, from the top**, as `webgl_textures.dart`
/// explains: a texture a pass draws into stores its top at the last row, so
/// a copy into or out of one turns the rows over — a row at a time, since GL
/// has no flipped copy — and a region read from one texture and copied into
/// another lands the same way up whichever kind each is.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

import 'webgl_buffers.dart';
import 'webgl_device.dart';
import 'webgl_formats.dart';
import 'webgl_framebuffer.dart';
import 'webgl_resources.dart';
import 'webgl_textures.dart';

/// One transfer pass. See the library note.
final class WebGlTransferEncoder extends TransferEncoder {
  WebGlTransferEncoder(this._device, this._gl);

  final WebGlDevice _device;
  final web.WebGL2RenderingContext _gl;
  bool _submitted = false;

  void _open(DeviceFeature feature, String reason) {
    if (_submitted) {
      throw StateError('this transfer pass was already submitted');
    }
    _device.features.require(
      feature,
      backend: webglBackendName,
      reason: reason,
    );
  }

  @override
  void copyBufferToBuffer(
    StorageBuffer source,
    int sourceOffset,
    StorageBuffer destination,
    int destinationOffset,
    int size,
  ) {
    _open(DeviceFeature.bufferCopy, 'copyBufferSubData is WebGL2 core');
    final from = webglBufferOf(source);
    final to = webglBufferOf(destination);
    webglRefuseMapped(from, 'copyBufferToBuffer');
    webglRefuseMapped(to, 'copyBufferToBuffer');
    if (sourceOffset % 4 != 0 || destinationOffset % 4 != 0 || size % 4 != 0) {
      throw ArgumentError(
        'copyBufferToBuffer: offsets and size are multiples of four',
      );
    }
    webglCheckRange(source, sourceOffset, size);
    webglCheckRange(destination, destinationOffset, size);
    if (identical(from, to) &&
        sourceOffset < destinationOffset + size &&
        destinationOffset < sourceOffset + size) {
      throw ArgumentError('copyBufferToBuffer: the two ranges overlap');
    }
    if (from.elementArray != to.elementArray) {
      // The type a first binding gave each (see `WebGlBuffer`) is for life,
      // and WebGL2 refuses a copy between an index buffer and any other.
      throw UnsupportedError(
        'WebGL2 copies no bytes between an index buffer and a buffer of '
        'other data. Copy between two of the same kind.',
      );
    }
    if (size == 0) return;
    _gl
      ..bindBuffer(web.WebGL2RenderingContext.COPY_READ_BUFFER, from.buffer)
      ..bindBuffer(web.WebGL2RenderingContext.COPY_WRITE_BUFFER, to.buffer)
      ..copyBufferSubData(
        web.WebGL2RenderingContext.COPY_READ_BUFFER,
        web.WebGL2RenderingContext.COPY_WRITE_BUFFER,
        sourceOffset,
        destinationOffset,
        size,
      )
      ..bindBuffer(web.WebGL2RenderingContext.COPY_READ_BUFFER, null)
      ..bindBuffer(web.WebGL2RenderingContext.COPY_WRITE_BUFFER, null);
  }

  /// Zeros written from the host: WebGL2 has no clear for a buffer, and
  /// `bufferSubData` of a zeroed array is the whole of one.
  @override
  void clearBuffer(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    _open(DeviceFeature.bufferCopy, 'a clear is a write of zeros');
    final target = webglBufferOf(buffer);
    webglRefuseMapped(target, 'clearBuffer');
    final size = webglCheckRange(buffer, offsetInBytes, sizeInBytes);
    if (offsetInBytes % 4 != 0 || size % 4 != 0) {
      throw ArgumentError('clearBuffer: offset and size are multiples of four');
    }
    if (size == 0) return;
    _gl
      ..bindBuffer(web.WebGL2RenderingContext.COPY_WRITE_BUFFER, target.buffer)
      ..bufferSubData(
        web.WebGL2RenderingContext.COPY_WRITE_BUFFER,
        offsetInBytes,
        Uint8List(size).toJS,
      )
      ..bindBuffer(web.WebGL2RenderingContext.COPY_WRITE_BUFFER, null);
  }

  @override
  void copyTextureToTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    _open(
      DeviceFeature.textureCopy,
      'copyTexSubImage and blitFramebuffer are WebGL2 core',
    );
    final from = source.texture;
    final to = destination.texture;
    if (from.format != to.format) {
      // The contract allows an sRGB pair; GL ES does not copy between the
      // two encodings with `copyTexSubImage`, and a blit would convert the
      // bytes rather than copy them.
      throw UnsupportedError(
        'WebGL2 copies texels only between textures of one format; '
        '${from.format.name} and ${to.format.name} differ',
      );
    }
    if (from.sampleCount > 1 || to.sampleCount > 1) {
      throw UnsupportedError(
        'WebGL2 cannot copy a multisampled renderbuffer texel for texel; '
        'resolve it with resolveTexture',
      );
    }
    if (from.format.isCompressed) {
      throw UnsupportedError(
        'WebGL2 has no copy for a block-compressed texture: it can neither '
        'read one back nor attach one to read from',
      );
    }
    final depth = from.format.isDepthOrStencil;
    if (!depth && !_device.textureFormatSupport(from.format).renderable) {
      throw UnsupportedError(
        'WebGL2 copies from a texture by attaching it to read from, and '
        'TextureFormat.${from.format.name} is not colour-renderable here',
      );
    }
    final src = _region(source, width, height, depthOrArrayLayers);
    final dst = _region(destination, width, height, depthOrArrayLayers);
    final flip = src.rendered != dst.rendered;
    final dstBackend = to.backend as WebGlTexture;
    final readFb = _gl.createFramebuffer();
    final drawFb = depth ? _gl.createFramebuffer() : null;
    try {
      for (var i = 0; i < depthOrArrayLayers; i++) {
        _gl.bindFramebuffer(
          web.WebGL2RenderingContext.READ_FRAMEBUFFER,
          readFb,
        );
        _attach(
          web.WebGL2RenderingContext.READ_FRAMEBUFFER,
          source,
          source.z + i,
          depth: depth,
        );
        _requireComplete(web.WebGL2RenderingContext.READ_FRAMEBUFFER);
        if (depth) {
          _gl.bindFramebuffer(
            web.WebGL2RenderingContext.DRAW_FRAMEBUFFER,
            drawFb,
          );
          _attach(
            web.WebGL2RenderingContext.DRAW_FRAMEBUFFER,
            destination,
            destination.z + i,
            depth: true,
          );
          // `blitFramebuffer` is clipped by the scissor, which a pass leaves
          // enabled; widened for the reason `blitToCanvas` gives.
          _gl.scissor(0, 0, dst.levelWidth, dst.levelHeight);
          // GL mirrors a blit whose destination rectangle runs backwards,
          // which is the one way a depth copy can turn its rows over.
          _gl.blitFramebuffer(
            source.x,
            src.glY,
            source.x + width,
            src.glY + height,
            destination.x,
            flip ? dst.glY + height : dst.glY,
            destination.x + width,
            flip ? dst.glY : dst.glY + height,
            to.format.hasStencil
                ? web.WebGLRenderingContext.DEPTH_BUFFER_BIT |
                      web.WebGLRenderingContext.STENCIL_BUFFER_BIT
                : web.WebGLRenderingContext.DEPTH_BUFFER_BIT,
            web.WebGLRenderingContext.NEAREST,
          );
          continue;
        }
        webglBindForUpload(_gl, dstBackend.target, dstBackend.texture);
        final rows = flip ? height : 1;
        final rowHeight = flip ? 1 : height;
        for (var r = 0; r < rows; r++) {
          _copyRows(
            destination,
            destination.z + i,
            dstY: flip ? dst.glY + height - 1 - r : dst.glY,
            srcX: source.x,
            srcY: src.glY + r,
            width: width,
            height: rowHeight,
          );
        }
      }
    } finally {
      _gl
        ..bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, null)
        ..bindFramebuffer(web.WebGL2RenderingContext.DRAW_FRAMEBUFFER, null)
        ..deleteFramebuffer(readFb)
        ..deleteFramebuffer(drawFb);
    }
  }

  /// `copyTexSubImage*` from the bound read framebuffer into [to]'s level at
  /// layer or face [z].
  void _copyRows(
    TextureCopyLocation to,
    int z, {
    required int dstY,
    required int srcX,
    required int srcY,
    required int width,
    required int height,
  }) {
    final backend = to.texture.backend as WebGlTexture;
    switch (to.texture.dimension) {
      case TextureDimension.d2Array || TextureDimension.d3:
        _gl.copyTexSubImage3D(
          backend.target,
          to.mipLevel,
          to.x,
          dstY,
          z,
          srcX,
          srcY,
          width,
          height,
        );
      case TextureDimension.cube:
        _gl.copyTexSubImage2D(
          web.WebGLRenderingContext.TEXTURE_CUBE_MAP_POSITIVE_X + z,
          to.mipLevel,
          to.x,
          dstY,
          srcX,
          srcY,
          width,
          height,
        );
      case TextureDimension.d2 ||
          TextureDimension.d1 ||
          TextureDimension.cubeArray:
        _gl.copyTexSubImage2D(
          web.WebGLRenderingContext.TEXTURE_2D,
          to.mipLevel,
          to.x,
          dstY,
          srcX,
          srcY,
          width,
          height,
        );
    }
  }

  @override
  void copyBufferToTexture(
    StorageBuffer source,
    BufferTextureLayout layout,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    _open(
      DeviceFeature.bufferTextureCopy,
      'PIXEL_UNPACK_BUFFER is WebGL2 core',
    );
    final from = _unpackable(source, 'copyBufferToTexture');
    final texture = destination.texture;
    final backend = texture.backend as WebGlTexture;
    if (backend.texture == null) {
      throw ArgumentError.value(
        destination,
        'destination',
        'is attachment-only (multisampled or deviceTransient)',
      );
    }
    final dst = _region(destination, width, height, depthOrArrayLayers);
    final format = texture.format;
    final rowsPerImage = layout.rowsPerImage ?? height;

    _gl
      ..bindBuffer(web.WebGL2RenderingContext.PIXEL_UNPACK_BUFFER, from.buffer)
      ..pixelStorei(web.WebGLRenderingContext.UNPACK_ALIGNMENT, 1);
    webglBindForUpload(_gl, backend.target, backend.texture);
    try {
      if (format.isCompressed) {
        _unpackCompressed(
          source,
          layout,
          destination,
          width: width,
          height: height,
          layers: depthOrArrayLayers,
        );
        return;
      }
      final transfer = webglTransferOf(format);
      if (transfer == null) {
        throw UnsupportedError(
          'WebGL2 fills no texture in TextureFormat.${format.name} from a '
          'buffer',
        );
      }
      final imageStride = _checkLayout(
        source,
        layout,
        texelBytes: transfer.texelBytes,
        width: width,
        height: height,
        rowsPerImage: rowsPerImage,
        layers: depthOrArrayLayers,
      );
      final flip = dst.rendered;
      if (!flip) {
        _gl
          ..pixelStorei(
            web.WebGL2RenderingContext.UNPACK_ROW_LENGTH,
            layout.bytesPerRow ~/ transfer.texelBytes,
          )
          ..pixelStorei(
            web.WebGL2RenderingContext.UNPACK_IMAGE_HEIGHT,
            rowsPerImage,
          );
      }
      for (var i = 0; i < depthOrArrayLayers; i++) {
        final base = layout.offsetInBytes + i * imageStride;
        final rows = flip ? height : 1;
        for (var r = 0; r < rows; r++) {
          _unpack(
            destination,
            destination.z + i,
            y: flip ? dst.glY + height - 1 - r : dst.glY,
            width: width,
            height: flip ? 1 : height,
            format: transfer.format,
            type: transfer.type,
            offset: base + r * layout.bytesPerRow,
          );
        }
      }
    } finally {
      _gl
        ..pixelStorei(web.WebGL2RenderingContext.UNPACK_ROW_LENGTH, 0)
        ..pixelStorei(web.WebGL2RenderingContext.UNPACK_IMAGE_HEIGHT, 0)
        ..pixelStorei(web.WebGLRenderingContext.UNPACK_ALIGNMENT, 4)
        // Unbound without fail: with a buffer on PIXEL_UNPACK_BUFFER every
        // later upload from host memory is read as an offset into it.
        ..bindBuffer(web.WebGL2RenderingContext.PIXEL_UNPACK_BUFFER, null);
    }
  }

  void _unpack(
    TextureCopyLocation to,
    int z, {
    required int y,
    required int width,
    required int height,
    required int format,
    required int type,
    required int offset,
  }) {
    final backend = to.texture.backend as WebGlTexture;
    switch (to.texture.dimension) {
      case TextureDimension.d2Array || TextureDimension.d3:
        _gl.texSubImage3D(
          backend.target,
          to.mipLevel,
          to.x,
          y,
          z,
          width,
          height,
          1,
          format,
          type,
          offset.toJS,
        );
      case TextureDimension.cube:
        _gl.texSubImage2D(
          web.WebGLRenderingContext.TEXTURE_CUBE_MAP_POSITIVE_X + z,
          to.mipLevel,
          to.x,
          y,
          width.toJS,
          height.toJS,
          format.toJS,
          type,
          offset.toJS,
        );
      case TextureDimension.d2 ||
          TextureDimension.d1 ||
          TextureDimension.cubeArray:
        _gl.texSubImage2D(
          web.WebGLRenderingContext.TEXTURE_2D,
          to.mipLevel,
          to.x,
          y,
          width.toJS,
          height.toJS,
          format.toJS,
          type,
          offset.toJS,
        );
    }
  }

  /// A compressed region from a buffer: tightly packed block rows only,
  /// because WebGL2 exposes none of the pixel-store state that would let GL
  /// skip padding between rows of blocks.
  void _unpackCompressed(
    StorageBuffer source,
    BufferTextureLayout layout,
    TextureCopyLocation to, {
    required int width,
    required int height,
    required int layers,
  }) {
    final format = to.texture.format;
    final block = format.blockLayout;
    final blocksWide = (width + block.blockWidth - 1) ~/ block.blockWidth;
    final blocksHigh = (height + block.blockHeight - 1) ~/ block.blockHeight;
    final rowBytes = blocksWide * block.bytesPerBlock;
    if (layout.bytesPerRow != rowBytes ||
        (layout.rowsPerImage ?? blocksHigh) != blocksHigh) {
      throw UnsupportedError(
        'WebGL2 takes compressed blocks from a buffer tightly packed only: '
        '$rowBytes bytes a row of blocks and $blocksHigh rows an image',
      );
    }
    final image = rowBytes * blocksHigh;
    webglCheckRange(source, layout.offsetInBytes, image * layers);
    final internal = compressedTextureFormatToGl(
      format,
      _device.compressedTextureSupport,
    );
    final backend = to.texture.backend as WebGlTexture;
    switch (to.texture.dimension) {
      case TextureDimension.d2Array || TextureDimension.d3:
        _gl.compressedTexSubImage3D(
          backend.target,
          to.mipLevel,
          to.x,
          to.y,
          to.z,
          width,
          height,
          layers,
          internal,
          (image * layers).toJS,
          layout.offsetInBytes.toJS,
        );
      case TextureDimension.cube:
        for (var i = 0; i < layers; i++) {
          _gl.compressedTexSubImage2D(
            web.WebGLRenderingContext.TEXTURE_CUBE_MAP_POSITIVE_X + to.z + i,
            to.mipLevel,
            to.x,
            to.y,
            width,
            height,
            internal,
            image.toJS,
            (layout.offsetInBytes + i * image).toJS,
          );
        }
      case TextureDimension.d2 ||
          TextureDimension.d1 ||
          TextureDimension.cubeArray:
        _gl.compressedTexSubImage2D(
          web.WebGLRenderingContext.TEXTURE_2D,
          to.mipLevel,
          to.x,
          to.y,
          width,
          height,
          internal,
          image.toJS,
          layout.offsetInBytes.toJS,
        );
    }
  }

  @override
  void copyTextureToBuffer(
    TextureCopyLocation source,
    StorageBuffer destination,
    BufferTextureLayout layout, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    _open(DeviceFeature.bufferTextureCopy, 'PIXEL_PACK_BUFFER is WebGL2 core');
    final to = _unpackable(destination, 'copyTextureToBuffer');
    final texture = source.texture;
    final format = texture.format;
    if (texture.sampleCount > 1) {
      throw UnsupportedError(
        'WebGL2 reads no multisampled renderbuffer back; resolve it first',
      );
    }
    if (format.isCompressed || format.isDepthOrStencil) {
      throw UnsupportedError(
        'WebGL2 reads back neither block-compressed nor depth texels: '
        'TextureFormat.${format.name}',
      );
    }
    final transfer = webglTransferOf(format);
    if (transfer == null) {
      throw UnsupportedError(
        'WebGL2 has no host layout for TextureFormat.${format.name}',
      );
    }
    final src = _region(source, width, height, depthOrArrayLayers);
    final rowsPerImage = layout.rowsPerImage ?? height;
    final imageStride = _checkLayout(
      destination,
      layout,
      texelBytes: transfer.texelBytes,
      width: width,
      height: height,
      rowsPerImage: rowsPerImage,
      layers: depthOrArrayLayers,
    );
    final readFb = _gl.createFramebuffer();
    _gl
      ..bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, readFb)
      ..bindBuffer(web.WebGL2RenderingContext.PIXEL_PACK_BUFFER, to.buffer)
      ..pixelStorei(web.WebGLRenderingContext.PACK_ALIGNMENT, 1)
      ..pixelStorei(
        web.WebGL2RenderingContext.PACK_ROW_LENGTH,
        layout.bytesPerRow ~/ transfer.texelBytes,
      );
    try {
      for (var i = 0; i < depthOrArrayLayers; i++) {
        _attach(
          web.WebGL2RenderingContext.READ_FRAMEBUFFER,
          source,
          source.z + i,
          depth: false,
        );
        _requireComplete(web.WebGL2RenderingContext.READ_FRAMEBUFFER);
        if (i == 0) _requireReadablePair(format, transfer);
        final base = layout.offsetInBytes + i * imageStride;
        final rows = src.rendered ? height : 1;
        for (var r = 0; r < rows; r++) {
          _gl.readPixels(
            source.x,
            src.rendered ? src.glY + height - 1 - r : src.glY,
            width,
            src.rendered ? 1 : height,
            transfer.format,
            transfer.type,
            (base + r * layout.bytesPerRow).toJS,
          );
        }
      }
    } finally {
      _gl
        ..pixelStorei(web.WebGL2RenderingContext.PACK_ROW_LENGTH, 0)
        ..pixelStorei(web.WebGLRenderingContext.PACK_ALIGNMENT, 4)
        ..bindBuffer(web.WebGL2RenderingContext.PIXEL_PACK_BUFFER, null)
        ..bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, null)
        ..deleteFramebuffer(readFb);
    }
  }

  /// `readPixels` takes one format/type pair per kind of colour buffer —
  /// `RGBA`/`UNSIGNED_BYTE` for normalised, `RGBA_INTEGER`/`INT` or
  /// `UNSIGNED_INT` for integers, `RGBA`/`FLOAT` for floats — and one more
  /// the implementation names for the bound framebuffer. A format whose own
  /// layout is neither cannot be packed into a buffer as itself, and is
  /// refused by name rather than written in some other layout.
  void _requireReadablePair(
    TextureFormat format,
    ({int format, int type, int texelBytes}) transfer,
  ) {
    final canonical = switch (format.sampleKind) {
      TextureSampleKind.uint => (
        web.WebGL2RenderingContext.RGBA_INTEGER,
        web.WebGLRenderingContext.UNSIGNED_INT,
      ),
      TextureSampleKind.sint => (
        web.WebGL2RenderingContext.RGBA_INTEGER,
        web.WebGLRenderingContext.INT,
      ),
      _ =>
        transfer.type == web.WebGLRenderingContext.FLOAT
            ? (web.WebGLRenderingContext.RGBA, web.WebGLRenderingContext.FLOAT)
            : (
                web.WebGLRenderingContext.RGBA,
                web.WebGLRenderingContext.UNSIGNED_BYTE,
              ),
    };
    final implementation = (
      _int(
        _gl.getParameter(
          web.WebGLRenderingContext.IMPLEMENTATION_COLOR_READ_FORMAT,
        ),
      ),
      _int(
        _gl.getParameter(
          web.WebGLRenderingContext.IMPLEMENTATION_COLOR_READ_TYPE,
        ),
      ),
    );
    final wanted = (transfer.format, transfer.type);
    if (wanted == canonical || wanted == implementation) return;
    throw UnsupportedError(
      'WebGL2 cannot pack TextureFormat.${format.name} into a buffer as '
      'itself here: readPixels takes it only as another layout',
    );
  }

  @override
  void resolveTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination,
  ) {
    _open(
      DeviceFeature.offscreenMultisample,
      'this context multisamples nothing it can resolve',
    );
    final from = source.texture;
    final to = destination.texture;
    if (from.sampleCount < 2 || to.sampleCount != 1) {
      throw ArgumentError(
        'resolveTexture resolves a multisampled texture into a '
        'single-sampled one: x${from.sampleCount} into x${to.sampleCount}',
      );
    }
    if (from.format != to.format) {
      throw ArgumentError(
        'resolveTexture: ${from.format.name} and ${to.format.name} differ',
      );
    }
    final dst = webglLevelExtent(to, destination.mipLevel);
    if (dst.width != from.width || dst.height != from.height) {
      throw ArgumentError(
        'resolveTexture: a ${from.width}x${from.height} texture resolves into '
        'a level of the same size, not ${dst.width}x${dst.height}',
      );
    }
    final depth = from.format.isDepthOrStencil;
    final readFb = _gl.createFramebuffer();
    final drawFb = _gl.createFramebuffer();
    try {
      _gl.bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, readFb);
      _attach(
        web.WebGL2RenderingContext.READ_FRAMEBUFFER,
        source,
        0,
        depth: depth,
      );
      _gl.bindFramebuffer(web.WebGL2RenderingContext.DRAW_FRAMEBUFFER, drawFb);
      _attach(
        web.WebGL2RenderingContext.DRAW_FRAMEBUFFER,
        destination,
        destination.z,
        depth: depth,
      );
      _gl
        ..scissor(0, 0, dst.width, dst.height)
        ..blitFramebuffer(
          0,
          0,
          from.width,
          from.height,
          0,
          0,
          dst.width,
          dst.height,
          depth
              ? web.WebGLRenderingContext.DEPTH_BUFFER_BIT
              : web.WebGLRenderingContext.COLOR_BUFFER_BIT,
          web.WebGLRenderingContext.NEAREST,
        );
    } finally {
      _gl
        ..bindFramebuffer(web.WebGL2RenderingContext.READ_FRAMEBUFFER, null)
        ..bindFramebuffer(web.WebGL2RenderingContext.DRAW_FRAMEBUFFER, null)
        ..deleteFramebuffer(readFb)
        ..deleteFramebuffer(drawFb);
    }
  }

  @override
  void submit() {
    if (_submitted) {
      throw StateError('this transfer pass was already submitted');
    }
    _submitted = true;
  }

  // ---------------------------------------------------------------- helpers

  /// Where a box of [width] x [height] x [layers] at [at] sits in GL's rows,
  /// after checking it fits the level: `glY` is the bottom GL row of the box
  /// — the same row for an uploaded texture, the mirrored one for a texture
  /// a pass draws into.
  ({int glY, bool rendered, int levelWidth, int levelHeight}) _region(
    TextureCopyLocation at,
    int width,
    int height,
    int layers,
  ) {
    final texture = at.texture;
    if (at.mipLevel < 0 || at.mipLevel >= _chainOf(texture)) {
      throw ArgumentError.value(at.mipLevel, 'mipLevel', 'is not a level');
    }
    final extent = webglLevelExtent(texture, at.mipLevel);
    if (at.x < 0 ||
        at.y < 0 ||
        at.z < 0 ||
        width < 1 ||
        height < 1 ||
        layers < 1 ||
        at.x + width > extent.width ||
        at.y + height > extent.height ||
        at.z + layers > extent.layers) {
      throw ArgumentError(
        'a ${width}x${height}x$layers box at (${at.x}, ${at.y}, ${at.z}) does '
        'not fit level ${at.mipLevel}, '
        '${extent.width}x${extent.height}x${extent.layers}',
      );
    }
    final rendered = (texture.backend as WebGlTexture).rendered;
    return (
      glY: rendered ? extent.height - at.y - height : at.y,
      rendered: rendered,
      levelWidth: extent.width,
      levelHeight: extent.height,
    );
  }

  static int _chainOf(TextureHandle texture) =>
      (texture.width > texture.height ? texture.width : texture.height)
          .bitLength;

  /// Attaches layer or face [z] of [at]'s texture to [target].
  void _attach(
    int target,
    TextureCopyLocation at,
    int z, {
    required bool depth,
  }) {
    final texture = at.texture;
    final cube = texture.dimension == TextureDimension.cube;
    attachToFramebuffer(
      _gl,
      target,
      depth
          ? (texture.format.hasStencil
                ? web.WebGL2RenderingContext.DEPTH_STENCIL_ATTACHMENT
                : web.WebGLRenderingContext.DEPTH_ATTACHMENT)
          : web.WebGLRenderingContext.COLOR_ATTACHMENT0,
      texture,
      face: cube ? z : 0,
      mipLevel: at.mipLevel,
      layer: cube ? 0 : z,
    );
  }

  void _requireComplete(int target) {
    final status = _gl.checkFramebufferStatus(target);
    if (status == web.WebGLRenderingContext.FRAMEBUFFER_COMPLETE) return;
    throw StateError(
      'the copy cannot attach this texture to read from it (framebuffer '
      'status 0x${status.toRadixString(16)})',
    );
  }

  /// [buffer]'s backend, refused when it is an index buffer — WebGL2 binds
  /// one to no pixel-transfer target — or mapped.
  WebGlBuffer _unpackable(StorageBuffer buffer, String what) {
    final backend = webglBufferOf(buffer);
    webglRefuseMapped(backend, what);
    if (backend.elementArray) {
      throw UnsupportedError(
        'WebGL2 binds an index buffer to no pixel-transfer target, so $what '
        'cannot use one. Copy through a buffer made without '
        'BufferUsage.index.',
      );
    }
    return backend;
  }

  /// Checks [layout] against a box of texels in [buffer]: rows a whole
  /// number of texels apart and at least a row long, images at least the
  /// box's height apart, and the last texel inside the buffer. Answers the
  /// bytes from one image to the next.
  static int _checkLayout(
    StorageBuffer buffer,
    BufferTextureLayout layout, {
    required int texelBytes,
    required int width,
    required int height,
    required int rowsPerImage,
    required int layers,
  }) {
    final rowBytes = width * texelBytes;
    if (layout.bytesPerRow < rowBytes || layout.bytesPerRow % texelBytes != 0) {
      throw ArgumentError.value(
        layout.bytesPerRow,
        'bytesPerRow',
        'is not a whole number of texels at least $rowBytes bytes long',
      );
    }
    if (rowsPerImage < height) {
      throw ArgumentError.value(
        rowsPerImage,
        'rowsPerImage',
        'is fewer than the $height rows of the box',
      );
    }
    final imageStride = layout.bytesPerRow * rowsPerImage;
    webglCheckRange(
      buffer,
      layout.offsetInBytes,
      imageStride * (layers - 1) + layout.bytesPerRow * (height - 1) + rowBytes,
    );
    return imageStride;
  }

  static int _int(JSAny? value) => value != null && value.isA<JSNumber>()
      ? (value as JSNumber).toDartInt
      : -1;
}
