/// Creating and releasing the WebGPU objects that outlive a draw, and the
/// arena the ones that do not are cut from.
///
/// **This file is where the fourth backend's buffer lifetimes are decided, and
/// the decision is not the one WebGL2 made.** That backend creates a
/// `WebGLBuffer` for every `bindVertexData` and `bindIndexData` and deletes it
/// when the pass ends — the handoff measured 1552 buffers in one frame. It gets
/// away with it because a GL driver owns the fencing: `bufferData` on a buffer
/// the GPU is still reading orphans the old allocation and the driver keeps it
/// alive until the command that reads it retires, and the whole cost is
/// allocator traffic.
///
/// WebGPU has no such fencing to lean on. A `GPUBuffer` is a real allocation
/// with an explicit `destroy`, and destroying one a submitted pass has not
/// finished with is a validation error rather than a slow path — so the WebGL
/// shape here is a frame that either leaks a thousand buffers or races the
/// queue.
///
/// ## What this does instead: one arena per kind, reset per frame
///
/// [WebGpuFrameArena] holds a single `GPUBuffer` and a cursor. Every transient
/// upload — a uniform block, a batch of particle vertices, an index run built
/// this frame — is a bump allocation in it, written with
/// `GPUQueue.writeBuffer`, and the cursor goes back to zero at
/// `GraphicsDevice.beginFrame`. A frame allocates nothing at all once the arena
/// has reached its high-water mark.
///
/// **Why resetting the cursor under a frame the GPU may still be reading is
/// safe, which is the part that looks wrong.** `writeBuffer` is not a host
/// write into memory the GPU can see: the bytes are copied into the queue's own
/// staging at the moment of the call, and the copy into the buffer is scheduled
/// *on the queue*, in the order it was asked for. So frame N's write, frame N's
/// pass, frame N+1's write over the same bytes and frame N+1's pass execute in
/// that order however far behind the GPU is, and the pass of frame N reads what
/// frame N wrote. This is the one property that makes an arena of this shape
/// correct without a ring of buffers, a fence or a frames-in-flight count —
/// and it is a property of `writeBuffer` specifically. An arena filled through
/// `mapAsync` and a mapped range would need every one of those.
///
/// **Growth retires rather than destroys**, for the reason above turned around.
/// A bind group made earlier in this frame names the buffer it was made
/// against, and a draw later in the same frame will bind it; a pass already
/// submitted is reading it. So an arena that overflows allocates a larger
/// buffer, keeps the old one in a list, and destroys nothing until the device
/// is disposed. Doubling makes that list a handful of entries whose total is
/// bounded by the final size, and it stops growing after the first few frames —
/// against the alternative, which is knowing when the GPU is done, which is
/// exactly the question this design exists to avoid asking once a draw.
///
/// Everything else here is the persistent half: a texture or a mesh buffer has
/// no such moment, so the lists these functions are handed are what `dispose`
/// walks. [WebGpuDevice] owns them and is the only caller.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_bundle_section.dart';
import 'webgpu_formats.dart';
import 'webgpu_interop.dart';
import 'webgpu_types.dart';

/// Where an arena put some bytes: the buffer they landed in, and how far into
/// it.
///
/// The buffer travels with the offset because an arena that has grown is
/// several buffers, and a binding made against the wrong one reads somebody
/// else's frame.
typedef WebGpuSlice = ({GPUBuffer buffer, int offset, int length});

/// A bump allocator over one `GPUBuffer`, reset every frame. See the library
/// comment, which is where the argument for this shape is.
final class WebGpuFrameArena {
  WebGpuFrameArena(
    this._gpu, {
    required this.usage,
    required this.alignment,
    required this.label,
    int initialBytes = 1 << 16,
  }) : _capacity = initialBytes {
    _buffer = _make(_capacity);
  }

  final GPUDevice _gpu;

  /// What the buffer may be bound as — uniform, vertex or index — beside
  /// `COPY_DST`, which every arena needs and this adds.
  ///
  /// One arena per usage rather than one buffer with all three flags: a WebGPU
  /// buffer may carry several, but `UNIFORM` and `VERTEX` on one allocation is
  /// a hint to the implementation that it can do neither well, and the three
  /// have different alignments anyway.
  final int usage;

  /// What every allocation's offset is rounded up to.
  ///
  /// 256 for uniforms, because that is `minUniformBufferOffsetAlignment` on
  /// every implementation so far and a dynamic offset that is not a multiple of
  /// it is refused. Four for vertices and indices, which is what `writeBuffer`
  /// itself demands.
  final int alignment;

  /// What the browser calls this buffer when it complains about it.
  final String label;

  int _capacity;
  int _cursor = 0;
  late GPUBuffer _buffer;

  /// Buffers this arena outgrew. Kept rather than destroyed — see the library
  /// comment — and released with the device.
  final List<GPUBuffer> _retired = <GPUBuffer>[];

  bool _disposed = false;

  /// How many `GPUBuffer`s this arena is holding, for
  /// `WebGpuDevice.debugTrackedResourceCount`. One, until a frame overflows it,
  /// and zero once [dispose] has destroyed them.
  int get bufferCount => _disposed ? 0 : 1 + _retired.length;

  /// The high-water mark since the arena was made, in bytes: what the largest
  /// frame so far asked of it. Diagnostic — read by `dispose_test.dart`, which
  /// asserts that a frame's second run allocates nothing new.
  int get peakBytes => _peak;
  int _peak = 0;

  GPUBuffer _make(int bytes) => _gpu.createBuffer(
    GPUBufferDescriptor(
      size: bytes,
      usage: usage | GpuBufferUsage.copyDst,
      label: label,
    ),
  );

  /// [bytes] written into the arena, and where they went.
  ///
  /// The length is rounded up to four before the cursor moves, because
  /// `writeBuffer` refuses a size that is not a multiple of four — see
  /// `gpuWritableBytes`, which does the same to the data. The padding is never
  /// read: a draw is bounded by its own count.
  WebGpuSlice write(ByteData bytes) {
    final length = bytes.lengthInBytes;
    final need = (length + 3) & ~3;
    var at = (_cursor + alignment - 1) & ~(alignment - 1);
    if (at + need > _capacity) {
      _retired.add(_buffer);
      var grown = _capacity * 2;
      while (grown < need) {
        grown *= 2;
      }
      _capacity = grown;
      _buffer = _make(_capacity);
      at = 0;
    }
    _gpu.queue.writeBuffer(_buffer, at, gpuWritableBytes(bytes).toJS);
    _cursor = at + need;
    if (_cursor > _peak) _peak = _cursor;
    return (buffer: _buffer, offset: at, length: length);
  }

  /// Back to the start, at the top of a frame. Safe under a frame the GPU has
  /// not finished — the library comment is the argument.
  void reset() => _cursor = 0;

  /// Destroys every buffer this arena holds. Called from `dispose`, once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final buffer in _retired) {
      buffer.destroy();
    }
    _retired.clear();
    _buffer.destroy();
  }
}

/// How many bytes one texel of [format] takes, for the uploads that state a row
/// stride.
///
/// Only the formats something in this engine actually uploads from the host
/// have an answer: eight-bit colour, the two float layouts the morph and
/// lightmap paths use, and the one- and two-channel maps. A format with no
/// answer is a texture this backend refuses to create from pixels rather than
/// one it fills with the wrong stride — which is a picture, and a plausible one.
int? webgpuTexelBytes(TextureFormat format) => switch (format) {
  TextureFormat.r8UNormInt => 1,
  TextureFormat.r8g8UNormInt => 2,
  TextureFormat.r8g8b8a8UNormInt ||
  TextureFormat.r8g8b8a8UNormIntSRGB ||
  TextureFormat.b8g8r8a8UNormInt ||
  TextureFormat.b8g8r8a8UNormIntSRGB ||
  TextureFormat.r32Float => 4,
  TextureFormat.r16g16b16a16Float => 8,
  TextureFormat.r32g32b32a32Float => 16,
  _ => null,
};

/// Whether [format] is a depth or stencil layout, which decides what a texture
/// in it may be used for.
///
/// `COPY_SRC` is left off one: `depth24plus` has no defined byte layout at all,
/// so a copy out of it is refused by the specification rather than by a driver,
/// and asking for the usage is asking for a promise this API will not make.
bool webgpuIsDepthStencil(TextureFormat format) =>
    format == TextureFormat.s8UInt ||
    format == TextureFormat.d24UnormS8Uint ||
    format == TextureFormat.d32FloatS8UInt;

/// A texture matching [spec], with a chain [levels] deep. See
/// `GraphicsDevice.createTexture`.
///
/// `deviceTransient` is Impeller's tile memory, which WebGPU does not have. The
/// honest translation is an attachment allocated without `TEXTURE_BINDING`: not
/// sampleable, attachment only, which is exactly what the storage mode already
/// promises. Multisampled targets go the same way — this engine resolves them
/// rather than sampling them, and a texture that cannot be sampled is one fewer
/// usage flag for the implementation to plan around.
TextureHandle webgpuCreateTexture(
  GPUDevice gpu,
  List<WebGpuTexture> tracked,
  RenderTargetSpec spec, {
  int levels = 1,
}) {
  final format = gpuTextureFormat(spec.format);
  if (format == null) {
    throw ArgumentError.value(
      spec.format,
      'format',
      'has no WebGPU spelling; ask supportsTextureFormat first',
    );
  }
  // **A block-compressed target is refused here rather than by the browser.**
  // Every one of these has a spelling now that the compression features are
  // asked for, so a spelling is no longer the thing that stops one becoming a
  // render target — and `RENDER_ATTACHMENT` on a compressed format is a
  // validation error whose message names a usage flag rather than the call that
  // wanted it. The contract already says a compressed format is sample-only
  // everywhere (`TextureFormatCompression.isCompressed`), which is the same
  // refusal the WebGL2 backend gives by having no non-compressed table entry to
  // hand back.
  if (spec.format.isCompressed) {
    throw ArgumentError.value(
      spec.format,
      'format',
      'is block-compressed, and a compressed texture cannot be a render '
          'target on any backend. Upload one through createTextureFromPixels',
    );
  }
  final attachmentOnly =
      spec.sampleCount > 1 || spec.storageMode == StorageMode.deviceTransient;
  final texture = gpu.createTexture(
    GPUTextureDescriptor(
      size: GPUExtent3DDict(
        width: spec.width,
        height: spec.height,
        depthOrArrayLayers: 1,
      ),
      format: format,
      usage: attachmentOnly
          ? GpuTextureUsage.renderAttachment
          : GpuTextureUsage.renderAttachment |
                GpuTextureUsage.textureBinding |
                GpuTextureUsage.copyDst |
                (webgpuIsDepthStencil(spec.format)
                    ? 0
                    : GpuTextureUsage.copySrc),
      sampleCount: spec.sampleCount,
      mipLevelCount: levels,
      dimension: '2d',
      label: 'target ${spec.width}x${spec.height} $format',
    ),
  );
  final backend = WebGpuTexture(
    texture: texture,
    dimension: WebGpuTextureDimension.twoDimensional,
    sampleable: !attachmentOnly,
  );
  tracked.add(backend);
  return TextureHandle(
    backend: backend,
    width: spec.width,
    height: spec.height,
    format: spec.format,
    sampleCount: spec.sampleCount,
    storageMode: spec.storageMode,
  );
}

/// A texture already holding [pixels], and [mipLevels] below it. See
/// `GraphicsDevice.createTextureFromPixels`.
///
/// Null where the bytes are not the size the description says, which is the
/// contract's answer for a decoder that disagreed about the dimensions.
///
/// A block-compressed format goes to [_webgpuCreateCompressedTextureFromPixels],
/// which measures in blocks rather than texels. It is still a null here for a
/// family the device was not granted, because [gpuTextureFormat] has a spelling
/// for all of them and only `supportsTextureFormat` knows which were asked for —
/// so the split is: a spelling that exists and a feature that was not granted is
/// a texture the browser would refuse, and the caller is meant to have asked
/// first.
TextureHandle? webgpuCreateTextureFromPixels(
  GPUDevice gpu,
  List<WebGpuTexture> tracked, {
  required int width,
  required int height,
  required TextureFormat format,
  required ByteData pixels,
  List<ByteData>? mipLevels,
}) {
  final spelling = gpuTextureFormat(format);
  if (spelling == null) return null;
  if (format.isCompressed) {
    return _webgpuCreateCompressedTextureFromPixels(
      gpu,
      tracked,
      spelling: spelling,
      width: width,
      height: height,
      format: format,
      pixels: pixels,
      mipLevels: mipLevels,
    );
  }
  final texelBytes = webgpuTexelBytes(format);
  if (texelBytes == null) return null;
  if (pixels.lengthInBytes != width * height * texelBytes) return null;

  // Every level measured before a single byte is uploaded, the way the WebGL2
  // backend measures its chain: `writeTexture` reads as many bytes as the
  // rectangle needs and ignores the rest, so a level built with the wrong
  // arithmetic is a plausible, wrong picture the moment anything minifies.
  final levels = mipLevels ?? const <ByteData>[];
  var w = width;
  var h = height;
  for (final level in levels) {
    w = w > 1 ? w >> 1 : 1;
    h = h > 1 ? h >> 1 : 1;
    if (level.lengthInBytes != w * h * texelBytes) return null;
  }

  final texture = gpu.createTexture(
    GPUTextureDescriptor(
      size: GPUExtent3DDict(
        width: width,
        height: height,
        depthOrArrayLayers: 1,
      ),
      format: spelling,
      usage:
          GpuTextureUsage.textureBinding |
          GpuTextureUsage.copyDst |
          GpuTextureUsage.copySrc,
      sampleCount: 1,
      mipLevelCount: 1 + levels.length,
      dimension: '2d',
      label: 'image ${width}x$height $spelling',
    ),
  );
  _writeLevel(gpu, texture, 0, 0, width, height, texelBytes, pixels);
  w = width;
  h = height;
  for (var i = 0; i < levels.length; i++) {
    w = w > 1 ? w >> 1 : 1;
    h = h > 1 ? h >> 1 : 1;
    _writeLevel(gpu, texture, i + 1, 0, w, h, texelBytes, levels[i]);
  }

  final backend = WebGpuTexture(
    texture: texture,
    dimension: WebGpuTextureDimension.twoDimensional,
    sampleable: true,
  );
  tracked.add(backend);
  return TextureHandle(
    backend: backend,
    width: width,
    height: height,
    format: format,
  );
}

/// The block-compressed half of [webgpuCreateTextureFromPixels].
///
/// **Split out rather than threaded through the path above, for the reason the
/// WebGL2 backend split its own: the two disagree about arithmetic, not about a
/// constant.** There a level is `width * height * texelBytes` bytes and here it
/// is whole blocks rounded up; there `writeTexture`'s `bytesPerRow` is a row of
/// texels and here it is a row of blocks, with `rowsPerImage` counting block
/// rows to match. Handed the texel numbers, the browser reads several times the
/// bytes that exist and refuses the write — which is the good outcome. The bad
/// one is a chain whose lower levels were measured with the wrong rounding: the
/// base draws, and the picture only goes wrong once something minifies.
/// [gpuBlockLayoutOf] is that arithmetic, in one place, so the size check and
/// the upload cannot disagree.
///
/// Every level is measured before a single byte is uploaded, exactly as the
/// uncompressed path measures its chain: `mipLevelCount` is fixed when the
/// texture is made, so a chain that turns out malformed halfway through leaves
/// an allocation nothing can correct.
///
/// **No `RENDER_ATTACHMENT` and no `COPY_SRC`.** A compressed texture cannot be
/// drawn into on any backend, and `readPixels` refuses it too — the contract
/// hands back eight-bit RGBA and a compressed texture has no such bytes to give.
/// Two usages it does not need are two the implementation need not plan around.
TextureHandle? _webgpuCreateCompressedTextureFromPixels(
  GPUDevice gpu,
  List<WebGpuTexture> tracked, {
  required String spelling,
  required int width,
  required int height,
  required TextureFormat format,
  required ByteData pixels,
  List<ByteData>? mipLevels,
}) {
  if (pixels.lengthInBytes !=
      gpuBlockLayoutOf(format, width, height).byteLength) {
    return null;
  }
  final levels = mipLevels ?? const <ByteData>[];
  var w = width;
  var h = height;
  for (final level in levels) {
    w = w > 1 ? w >> 1 : 1;
    h = h > 1 ? h >> 1 : 1;
    if (level.lengthInBytes != gpuBlockLayoutOf(format, w, h).byteLength) {
      return null;
    }
  }

  final texture = gpu.createTexture(
    GPUTextureDescriptor(
      size: GPUExtent3DDict(
        width: width,
        height: height,
        depthOrArrayLayers: 1,
      ),
      format: spelling,
      usage: GpuTextureUsage.textureBinding | GpuTextureUsage.copyDst,
      sampleCount: 1,
      mipLevelCount: 1 + levels.length,
      dimension: '2d',
      label: 'image ${width}x$height $spelling',
    ),
  );

  void upload(int level, int w, int h, ByteData bytes) {
    final layout = gpuBlockLayoutOf(format, w, h);
    gpu.queue.writeTexture(
      GPUTexelCopyTextureInfo(
        texture: texture,
        mipLevel: level,
        origin: GPUOrigin3DDict(x: 0, y: 0, z: 0),
        aspect: 'all',
      ),
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes).toJS,
      GPUTexelCopyBufferLayout(
        offset: 0,
        bytesPerRow: layout.bytesPerRow,
        rowsPerImage: layout.rowsPerImage,
      ),
      // The extent stays in *texels* while the layout above is in blocks, which
      // is the one place the two units meet. A level narrower than a block — the
      // 2x2 tail of a 4x4 BC1 chain — is legal exactly because it is the whole
      // of its level, and the block it is stored in covers the rest.
      GPUExtent3DDict(width: w, height: h, depthOrArrayLayers: 1),
    );
  }

  upload(0, width, height, pixels);
  w = width;
  h = height;
  for (var i = 0; i < levels.length; i++) {
    w = w > 1 ? w >> 1 : 1;
    h = h > 1 ? h >> 1 : 1;
    upload(i + 1, w, h, levels[i]);
  }

  final backend = WebGpuTexture(
    texture: texture,
    dimension: WebGpuTextureDimension.twoDimensional,
    sampleable: true,
  );
  tracked.add(backend);
  return TextureHandle(
    backend: backend,
    width: width,
    height: height,
    format: format,
  );
}

/// [faces] in `+X, −X, +Y, −Y, +Z, −Z` order as one cube texture. See
/// `GraphicsDevice.createCubeTextureFromPixels`.
///
/// **A cube is a six-layer 2D texture here**, and a face is the `z` of an
/// origin rather than a target constant of its own. There is no six-argument
/// upload call and no face enumeration in this API, so the order the contract
/// documents is honoured by the loop's own index and by nothing else — which is
/// why the conformance check that draws six known directions against six known
/// colours is the thing that holds it.
///
/// **A block-compressed cube is a null, and that is a scope line rather than a
/// limit of the API.** WebGPU would take one — six layers of block rows is the
/// same `writeTexture` the 2D path makes — but nothing in this repository
/// uploads a compressed cube: the KTX2 loader hands over one 2D image and the
/// engine's own cubes are rendered rather than decoded. A path with no caller is
/// a path with no test, and the null is what [webgpuTexelBytes] already answers
/// for a format it has no texel size for.
TextureHandle? webgpuCreateCubeTextureFromPixels(
  GPUDevice gpu,
  List<WebGpuTexture> tracked, {
  required int size,
  required TextureFormat format,
  required List<ByteData> faces,
  List<List<ByteData>>? mipLevels,
}) {
  final spelling = gpuTextureFormat(format);
  final texelBytes = webgpuTexelBytes(format);
  if (spelling == null || texelBytes == null) return null;
  if (faces.length != 6) return null;
  for (final face in faces) {
    if (face.lengthInBytes != size * size * texelBytes) return null;
  }
  final levels = mipLevels ?? const <List<ByteData>>[];
  var side = size;
  for (final level in levels) {
    if (level.length != 6) return null;
    side = side > 1 ? side >> 1 : 1;
    for (final face in level) {
      if (face.lengthInBytes != side * side * texelBytes) return null;
    }
  }

  final texture = gpu.createTexture(
    GPUTextureDescriptor(
      size: GPUExtent3DDict(width: size, height: size, depthOrArrayLayers: 6),
      format: spelling,
      usage:
          GpuTextureUsage.textureBinding |
          GpuTextureUsage.copyDst |
          GpuTextureUsage.copySrc,
      sampleCount: 1,
      mipLevelCount: 1 + levels.length,
      dimension: '2d',
      label: 'cube ${size}x$size $spelling',
    ),
  );
  for (var face = 0; face < 6; face++) {
    _writeLevel(gpu, texture, 0, face, size, size, texelBytes, faces[face]);
  }
  side = size;
  for (var level = 0; level < levels.length; level++) {
    side = side > 1 ? side >> 1 : 1;
    for (var face = 0; face < 6; face++) {
      _writeLevel(
        gpu,
        texture,
        level + 1,
        face,
        side,
        side,
        texelBytes,
        levels[level][face],
      );
    }
  }

  final backend = WebGpuTexture(
    texture: texture,
    dimension: WebGpuTextureDimension.cube,
    sampleable: true,
  );
  tracked.add(backend);
  return TextureHandle(
    backend: backend,
    width: size,
    height: size,
    format: format,
    type: TextureType.textureCube,
  );
}

/// An empty cube a pass may draw into, one face and one level at a time. See
/// `GraphicsDevice.createCubeRenderTarget`.
///
/// **Six array layers and `RENDER_ATTACHMENT`, and that is the whole of it.**
/// Where WebGL2 needs a face target constant in `framebufferTexture2D` and
/// Impeller needs a slice on the attachment, here a face is `baseArrayLayer`
/// and a level is `baseMipLevel` on an ordinary 2D view —
/// `WebGpuTexture.attachmentView` already makes exactly that pair, because a
/// cube face and a mip level are the same mechanism in this API.
///
/// **[mipLevels] is a chain a pass may draw into, not one it may only upload
/// to**, and for a while this said the opposite. The levels were allocated from
/// the day the cube was and `supportsRenderToMip` went on answering false beside
/// them, so a caller reading the capability was told the chain was out of reach
/// while the allocation quietly held it. Nothing had to be built to lift that:
/// the level is `baseMipLevel` on the attachment view, and a reflection probe
/// fills the chain with its own passes rather than asking this API for a
/// `generateMipmap` it does not have.
///
/// Null for a format this device has no spelling for, and for a block-compressed
/// one: those have spellings now that the compression features are asked for,
/// and a compressed render target is a validation error rather than a slow path.
TextureHandle? webgpuCreateCubeRenderTarget(
  GPUDevice gpu,
  List<WebGpuTexture> tracked, {
  required int size,
  required TextureFormat format,
  int mipLevels = 1,
}) {
  final spelling = gpuTextureFormat(format);
  if (spelling == null || format.isCompressed) return null;
  final texture = gpu.createTexture(
    GPUTextureDescriptor(
      size: GPUExtent3DDict(width: size, height: size, depthOrArrayLayers: 6),
      format: spelling,
      usage:
          GpuTextureUsage.renderAttachment |
          GpuTextureUsage.textureBinding |
          GpuTextureUsage.copyDst |
          GpuTextureUsage.copySrc,
      sampleCount: 1,
      mipLevelCount: mipLevels,
      dimension: '2d',
      label: 'cube target ${size}x$size $spelling',
    ),
  );
  final backend = WebGpuTexture(
    texture: texture,
    dimension: WebGpuTextureDimension.cube,
    sampleable: true,
  );
  tracked.add(backend);
  return TextureHandle(
    backend: backend,
    width: size,
    height: size,
    format: format,
    type: TextureType.textureCube,
  );
}

void _writeLevel(
  GPUDevice gpu,
  GPUTexture texture,
  int level,
  int layer,
  int width,
  int height,
  int texelBytes,
  ByteData bytes,
) => gpu.queue.writeTexture(
  GPUTexelCopyTextureInfo(
    texture: texture,
    mipLevel: level,
    origin: GPUOrigin3DDict(x: 0, y: 0, z: layer),
    aspect: 'all',
  ),
  bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes).toJS,
  // **No 256-byte rounding here**, and that asymmetry is worth stating once: a
  // `writeTexture` row may be any multiple of the texel size, while the
  // `copyTextureToBuffer` a readback makes may not. The two look like the same
  // operation from Dart and are not.
  GPUTexelCopyBufferLayout(
    offset: 0,
    bytesPerRow: width * texelBytes,
    rowsPerImage: height,
  ),
  GPUExtent3DDict(width: width, height: height, depthOrArrayLayers: 1),
);

/// Geometry uploaded once and bound many times, until the device that made it
/// is disposed. See `GraphicsDevice.uploadGeometry`.
///
/// [usage] is not a hint here any more than it is on WebGL2: a WebGPU buffer
/// declares `VERTEX` or `INDEX` when it is made and cannot be bound as the
/// other afterwards. That the contract already carries the word is one of the
/// places it turned out not to be describing a single API.
GeometryBuffer webgpuUploadGeometry(
  GPUDevice gpu,
  List<GPUBuffer> tracked,
  ByteData bytes,
  GeometryUsage usage,
) {
  final buffer = gpu.createBuffer(
    GPUBufferDescriptor(
      // Rounded up to four, which `writeBuffer` demands of every size it is
      // given — see `gpuWritableBytes` for the bytes' half of the same rule.
      size: (bytes.lengthInBytes + 3) & ~3,
      usage:
          (usage == GeometryUsage.vertices
              ? GpuBufferUsage.vertex
              : GpuBufferUsage.index) |
          GpuBufferUsage.copyDst,
      label: 'geometry ${bytes.lengthInBytes}B ${usage.name}',
    ),
  );
  gpu.queue.writeBuffer(buffer, 0, gpuWritableBytes(bytes).toJS);
  tracked.add(buffer);
  return GeometryBuffer(
    backend: WebGpuGeometry(buffer),
    offsetInBytes: 0,
    lengthInBytes: bytes.lengthInBytes,
  );
}

/// Destroys one texture and stops tracking it, or answers false for a handle
/// this device does not hold — a double release, or one from another device.
///
/// A `GPUTexture` is a real allocation with an explicit `destroy`, exactly as a
/// `WebGLTexture` is and unlike flutter_gpu's `Texture`, so this is the only
/// thing that frees one before the whole device goes. A resize remakes six or
/// seven full-screen targets; without this they stay until the tab does.
bool webgpuReleaseTexture(WebGpuTexture backend, List<WebGpuTexture> tracked) {
  final at = tracked.indexWhere((WebGpuTexture it) => identical(it, backend));
  if (at < 0) return false;
  tracked.removeAt(at).texture.destroy();
  return true;
}

/// Destroys one geometry buffer and stops tracking it. See
/// [webgpuReleaseTexture].
///
/// Takes [buffer] as an `Object` and finds it by identity, deliberately: an
/// `is` test against an interop type asks a question about JavaScript rather
/// than about a Dart class, and membership in the list this device fills is the
/// better question anyway — it also rejects a buffer from another device.
bool webgpuReleaseGeometry(Object buffer, List<GPUBuffer> tracked) {
  if (buffer is! WebGpuGeometry) return false;
  final at = tracked.indexWhere((GPUBuffer it) => identical(it, buffer.buffer));
  if (at < 0) return false;
  tracked.removeAt(at).destroy();
  return true;
}

/// Destroys every tracked texture and buffer and empties both lists. See
/// `GraphicsDevice.dispose`.
void webgpuDisposePersistentResources(
  List<WebGpuTexture> textures,
  List<GPUBuffer> buffers,
) {
  for (final texture in textures) {
    texture.texture.destroy();
  }
  textures.clear();
  for (final buffer in buffers) {
    buffer.destroy();
  }
  buffers.clear();
}
