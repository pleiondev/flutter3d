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

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_bundle_section.dart';
import 'webgpu_compute.dart' show WebGpuStorage;
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
///
/// **Where the browser has `TRANSIENT_ATTACHMENT` ([transientAttachments]), a
/// single-level `deviceTransient` target is allocated with it** — `H7`: the
/// tile memory the storage mode names, which on a tiler is a depth or MSAA
/// buffer that never reaches memory at all. The encoder then clears and
/// discards it, the only operations WebGPU allows on one.
TextureHandle webgpuCreateTexture(
  GPUDevice gpu,
  List<WebGpuTexture> tracked,
  RenderTargetDescriptor spec, {
  int levels = 1,
  bool transientAttachments = false,
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
  final transient =
      levels == 1 &&
      webgpuIsTransientAttachment(spec, supported: transientAttachments);
  final texture = gpu.createTexture(
    GPUTextureDescriptor(
      size: GPUExtent3DDict(
        width: spec.width,
        height: spec.height,
        depthOrArrayLayers: 1,
      ),
      format: format,
      usage: transient
          ? GpuTextureUsage.renderAttachment |
                GpuTextureUsage.transientAttachment
          : attachmentOnly
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
    transient: transient,
  );
  tracked.add(backend);
  return wrapTexture(
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
  return wrapTexture(
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
  return wrapTexture(
    backend: backend,
    width: width,
    height: height,
    format: format,
  );
}

/// Writes [rgba] into [rect] of [target]'s base level. See
/// `GraphicsDevice.overwriteTexture` — the caller already refused a
/// compressed format and a non-zero mip level, so this is always a plain
/// RGBA8 region.
void webgpuOverwriteTexture(
  GPUDevice gpu,
  TextureHandle target,
  ByteData rgba,
  ScreenRect rect,
) {
  final texture = (target.backend as WebGpuTexture).texture;
  final bytes = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
  // `writeTexture` stores the bytes as the texture lays them out, and the
  // contract hands over RGBA whatever the target is. A `bgra8unorm` target —
  // one of the two formats the caller already let through — takes them with
  // red and blue exchanged, on a copy, so the caller's buffer is left alone.
  final stored = target.format == TextureFormat.b8g8r8a8UNormInt
      ? _swappedCopy(bytes)
      : bytes;
  // Not `gpuBlockLayoutOf`: that reads `TextureFormat.blockLayout`, which
  // only a compressed format carries — `r8g8b8a8UNormInt` is what this
  // function's own doc comment says it always is, four bytes a pixel with
  // no block to round up to.
  gpu.queue.writeTexture(
    GPUTexelCopyTextureInfo(
      texture: texture,
      mipLevel: 0,
      origin: GPUOrigin3DDict(x: rect.x, y: rect.y, z: 0),
      aspect: 'all',
    ),
    stored.toJS,
    GPUTexelCopyBufferLayout(
      offset: 0,
      bytesPerRow: rect.width * 4,
      rowsPerImage: rect.height,
    ),
    GPUExtent3DDict(
      width: rect.width,
      height: rect.height,
      depthOrArrayLayers: 1,
    ),
  );
}

/// A copy of [bytes] with red and blue exchanged in every texel.
Uint8List _swappedCopy(Uint8List bytes) {
  final copy = Uint8List.fromList(bytes);
  swapRedAndBlue(copy);
  return copy;
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
  return wrapTexture(
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
  // Trimmed to a chain that reaches one by one and no further, as the contract
  // says a chain longer than the device will allocate is — and as the WebGL2
  // backend trims it. WebGPU refuses a `mipLevelCount` past the full chain,
  // and refuses it asynchronously: the handle comes back over an invalid
  // texture and every pass that names a face of it draws nothing.
  final fullChain = size <= 1 ? 1 : size.bitLength;
  final levels = mipLevels < 1
      ? 1
      : (mipLevels > fullChain ? fullChain : mipLevels);
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
      mipLevelCount: levels,
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
  return wrapTexture(
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
  GeometryUsage usage, {
  void Function(GeometryBuffer)? release,
}) {
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
  return wrapGeometry(
    backend: WebGpuGeometry(buffer),
    offsetInBytes: 0,
    lengthInBytes: bytes.lengthInBytes,
    release: release,
  );
}

/// Writes into an existing buffer through the same queue [webgpuUploadGeometry]
/// uploads with. See `GraphicsDevice.overwriteGeometry`.
///
/// **`writeBuffer` demands a four-byte-aligned offset as well as a
/// four-byte-aligned length**, and only the length is padded for by
/// [gpuWritableBytes] — an unaligned offset is refused outright rather than
/// silently rounded, because rounding it would write over bytes the caller
/// never named.
void webgpuOverwriteGeometry(
  GPUDevice gpu,
  GeometryBuffer target,
  int offsetInBytes,
  ByteData bytes,
) {
  if (offsetInBytes < 0 ||
      offsetInBytes + bytes.lengthInBytes > target.lengthInBytes) {
    throw ArgumentError(
      'overwriteGeometry: $offsetInBytes + ${bytes.lengthInBytes} does not '
      'fit inside a ${target.lengthInBytes}-byte buffer',
    );
  }
  final at = target.offsetInBytes + offsetInBytes;
  if (at % 4 != 0) {
    throw ArgumentError(
      'overwriteGeometry: offset $at is not four-byte aligned',
    );
  }
  final buffer = (target.backend as WebGpuGeometry).buffer;
  gpu.queue.writeBuffer(buffer, at, gpuWritableBytes(bytes).toJS);
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

/// The view shape a texture of [dimension] is sampled as.
WebGpuTextureDimension webgpuViewDimension(TextureDimension dimension) =>
    switch (dimension) {
      TextureDimension.d1 => WebGpuTextureDimension.oneDimensional,
      TextureDimension.d2 => WebGpuTextureDimension.twoDimensional,
      TextureDimension.d2Array => WebGpuTextureDimension.twoDimensionalArray,
      TextureDimension.d3 => WebGpuTextureDimension.threeDimensional,
      TextureDimension.cube => WebGpuTextureDimension.cube,
      TextureDimension.cubeArray => WebGpuTextureDimension.cubeArray,
    };

/// [usage] as `GPUTextureUsage` bits.
int gpuTextureUsageOf(TextureUsage usage) =>
    (usage.contains(TextureUsage.sampled)
        ? GpuTextureUsage.textureBinding
        : 0) |
    (usage.contains(TextureUsage.renderTarget)
        ? GpuTextureUsage.renderAttachment
        : 0) |
    (usage.contains(TextureUsage.storage)
        ? GpuTextureUsage.storageBinding
        : 0) |
    (usage.contains(TextureUsage.copySource) ? GpuTextureUsage.copySrc : 0) |
    (usage.contains(TextureUsage.copyDestination)
        ? GpuTextureUsage.copyDst
        : 0);

/// A texture of any shape — `GraphicsDevice.createTexture`.
///
/// The device has already checked the features the shape needs; what is
/// checked here is everything the browser would otherwise refuse
/// asynchronously, as a texture handed back over an invalid allocation:
/// a size past [limits], a layer count the shape cannot have, a chain longer
/// than the texture, a sample count WebGPU does not offer, and a usage the
/// format cannot take. Each is an [ArgumentError] naming the field.
TextureHandle webgpuCreateTextureWithDescriptor(
  GPUDevice gpu,
  List<WebGpuTexture> tracked,
  TextureDescriptor descriptor, {
  required DeviceLimits limits,
  required TextureFormatSupport support,
}) {
  final d = descriptor;
  final spelling = gpuTextureFormat(d.format);
  if (spelling == null || support == TextureFormatSupport.none) {
    throw ArgumentError.value(
      d.format,
      'format',
      'is not one this WebGPU device can allocate; ask textureFormatSupport',
    );
  }
  Never refuse(String field, Object value, String why) =>
      throw ArgumentError.value(value, field, why);

  final layers = d.depthOrArrayLayers;
  switch (d.dimension) {
    case TextureDimension.d1:
      if (d.height != 1 || layers != 1) {
        refuse('height', d.height, 'a 1D texture is one texel high, one layer');
      }
      if (d.width > limits.maxTextureDimension1D) {
        refuse('width', d.width, 'is past maxTextureDimension1D');
      }
    case TextureDimension.d3:
      if (d.width > limits.maxTextureDimension3D ||
          d.height > limits.maxTextureDimension3D ||
          layers > limits.maxTextureDimension3D) {
        refuse('size', d, 'is past maxTextureDimension3D');
      }
    case TextureDimension.d2:
    case TextureDimension.d2Array:
    case TextureDimension.cube:
    case TextureDimension.cubeArray:
      if (d.width > limits.maxTextureDimension2D ||
          d.height > limits.maxTextureDimension2D) {
        refuse('size', d, 'is past maxTextureDimension2D');
      }
      if (layers > limits.maxTextureArrayLayers) {
        refuse('depthOrArrayLayers', layers, 'is past maxTextureArrayLayers');
      }
  }
  switch (d.dimension) {
    case TextureDimension.d2 when layers != 1:
      refuse('depthOrArrayLayers', layers, 'a 2D texture has one layer');
    case TextureDimension.cube when layers != 6 || d.width != d.height:
      refuse('depthOrArrayLayers', layers, 'a cube is six square layers');
    case TextureDimension.cubeArray when layers % 6 != 0 || d.width != d.height:
      refuse('depthOrArrayLayers', layers, 'a cube array is six per cube');
    default:
  }
  final largest = <int>[
    d.width,
    d.height,
    if (d.dimension == TextureDimension.d3) layers,
  ].reduce((int a, int b) => a > b ? a : b);
  if (d.mipLevelCount > largest.bitLength ||
      (d.dimension == TextureDimension.d1 && d.mipLevelCount != 1)) {
    refuse('mipLevelCount', d.mipLevelCount, 'is longer than the full chain');
  }
  if (d.sampleCount != 1) {
    if (d.sampleCount != 4) {
      refuse('sampleCount', d.sampleCount, 'WebGPU offers one or four');
    }
    if (d.dimension != TextureDimension.d2 ||
        d.mipLevelCount != 1 ||
        !support.multisample ||
        d.usage.contains(TextureUsage.storage)) {
      refuse(
        'sampleCount',
        d.sampleCount,
        'a multisampled texture is 2D, one level, not storage, in a format '
            'whose support says multisample',
      );
    }
  }
  if (d.usage.contains(TextureUsage.renderTarget) &&
      (d.dimension == TextureDimension.d1 ||
          !(support.renderable || support.depthStencil))) {
    refuse(
      'usage',
      d.usage,
      '${d.format.name} cannot be an attachment here; leave renderTarget out '
          '(TextureUsage.sampled | TextureUsage.copyDestination for an upload)',
    );
  }
  if (d.usage.contains(TextureUsage.storage) && !support.storage) {
    refuse('usage', d.usage, '${d.format.name} cannot be a storage texture');
  }

  // `depth24plus` has no byte layout to copy out, so the usage is left off
  // as `webgpuCreateTexture` leaves it — asking for it asks for a promise
  // the specification does not make.
  final usage =
      gpuTextureUsageOf(d.usage) &
      (d.format == TextureFormat.d24UnormS8Uint
          ? ~GpuTextureUsage.copySrc
          : ~0);
  final texture = gpu.createTexture(
    GPUTextureDescriptor(
      size: GPUExtent3DDict(
        width: d.width,
        height: d.height,
        depthOrArrayLayers: layers,
      ),
      format: spelling,
      usage: usage,
      sampleCount: d.sampleCount,
      mipLevelCount: d.mipLevelCount,
      dimension: gpuTextureDimension(d.dimension),
      label: d.label ?? 'texture $d',
    ),
  );
  final backend = WebGpuTexture(
    texture: texture,
    dimension: webgpuViewDimension(d.dimension),
    sampleable: d.usage.contains(TextureUsage.sampled) && d.sampleCount == 1,
  );
  tracked.add(backend);
  return wrapTexture(
    backend: backend,
    width: d.width,
    height: d.height,
    format: d.format,
    sampleCount: d.sampleCount,
    storageMode: d.storageMode,
    // A multisampled texture is `texture2D` with a sample count, as every
    // target `createTexture` makes is.
    type: d.dimension == TextureDimension.cube
        ? TextureType.textureCube
        : TextureType.texture2D,
    dimension: d.dimension,
    // Counted as the descriptor counts them: six for a cube.
    depthOrArrayLayers: layers,
    mipLevelCount: d.mipLevelCount,
    usage: d.usage,
  );
}

/// The extent of level [level] of [texture]: width, height and layers (or
/// depth, for a volume, which halves with the level as the others do).
({int width, int height, int layers}) webgpuLevelExtent(
  GPUTexture texture,
  int level,
) {
  int halve(int n) => (n >> level) < 1 ? 1 : n >> level;
  return (
    width: halve(texture.width),
    height: halve(texture.height),
    layers: texture.dimension == '3d'
        ? halve(texture.depthOrArrayLayers)
        : texture.depthOrArrayLayers,
  );
}

/// [region] checked against level [level] of [texture], and against the
/// block footprint of [format], or an [ArgumentError] naming what does not
/// fit. A compressed region starts on a block and covers whole blocks, unless
/// it runs to the edge of the level, where the last block is partial.
void webgpuCheckRegion(
  GPUTexture texture,
  TextureFormat format,
  int level,
  TextureRegion region, {
  required ({int blockWidth, int blockHeight, int bytesPerBlock}) block,
}) {
  if (level < 0 || level >= texture.mipLevelCount) {
    throw ArgumentError.value(
      level,
      'mipLevel',
      'the texture has ${texture.mipLevelCount} level(s)',
    );
  }
  final extent = webgpuLevelExtent(texture, level);
  final r = region;
  if (r.x < 0 ||
      r.y < 0 ||
      r.z < 0 ||
      r.width < 1 ||
      r.height < 1 ||
      r.depthOrArrayLayers < 1 ||
      r.x + r.width > extent.width ||
      r.y + r.height > extent.height ||
      r.z + r.depthOrArrayLayers > extent.layers) {
    throw ArgumentError.value(
      region,
      'region',
      'does not fit level $level, which is '
          '${extent.width}x${extent.height}x${extent.layers}',
    );
  }
  bool aligned(int at, int size, int step, int edge) =>
      at % step == 0 && (size % step == 0 || at + size == edge);
  if (!aligned(r.x, r.width, block.blockWidth, extent.width) ||
      !aligned(r.y, r.height, block.blockHeight, extent.height)) {
    throw ArgumentError.value(
      region,
      'region',
      '${format.name} is stored in ${block.blockWidth}x${block.blockHeight} '
          'blocks, and a region covers whole ones',
    );
  }
}

/// Writes [data] into [region] of level [level] of [target] —
/// `GraphicsDevice.writeTexture`.
///
/// `queue.writeTexture` takes any row stride, unlike an encoded copy, so
/// [bytesPerRow] defaults to the tight one and is honoured as given.
void webgpuWriteTexture(
  GPUDevice gpu,
  TextureHandle target,
  ByteData data, {
  TextureRegion? region,
  int level = 0,
  int? bytesPerRow,
}) {
  final texture = (target.backend as WebGpuTexture).texture;
  if (texture.usage & GpuTextureUsage.copyDst == 0) {
    throw ArgumentError.value(
      target,
      'target',
      'was not made with TextureUsage.copyDestination',
    );
  }
  final block = gpuCopyBlock(target.format, intoTexture: true);
  if (block == null) {
    throw ArgumentError.value(
      target.format,
      'format',
      'has no byte layout WebGPU will write into',
    );
  }
  final extent = webgpuLevelExtent(texture, level.clamp(0, 31));
  final r =
      region ??
      TextureRegion(
        width: extent.width,
        height: extent.height,
        depthOrArrayLayers: extent.layers,
      );
  webgpuCheckRegion(texture, target.format, level, r, block: block);
  final across = (r.width + block.blockWidth - 1) ~/ block.blockWidth;
  final rows = (r.height + block.blockHeight - 1) ~/ block.blockHeight;
  final tight = across * block.bytesPerBlock;
  final stride = bytesPerRow ?? tight;
  if (stride < tight) {
    throw ArgumentError.value(
      stride,
      'bytesPerRow',
      'is shorter than one row of the region ($tight bytes)',
    );
  }
  final needed =
      stride * rows * (r.depthOrArrayLayers - 1) + stride * (rows - 1) + tight;
  if (data.lengthInBytes < needed) {
    throw ArgumentError.value(
      data.lengthInBytes,
      'data',
      'holds fewer bytes than the region needs ($needed)',
    );
  }
  gpu.queue.writeTexture(
    GPUTexelCopyTextureInfo(
      texture: texture,
      mipLevel: level,
      origin: GPUOrigin3DDict(x: r.x, y: r.y, z: r.z),
      aspect: 'all',
    ),
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes).toJS,
    GPUTexelCopyBufferLayout(
      offset: 0,
      bytesPerRow: stride,
      rowsPerImage: rows,
    ),
    GPUExtent3DDict(
      width: r.width,
      height: r.height,
      depthOrArrayLayers: r.depthOrArrayLayers,
    ),
  );
}

/// [usage] as `GPUBufferUsage` bits.
///
/// **The two host usages are where the APIs meet awkwardly.** WebGPU lets
/// `MAP_READ` sit only beside `COPY_DST`, and `MAP_WRITE` only beside
/// `COPY_SRC`. So a buffer asked to be [BufferUsage.hostReadable] and nothing
/// but a copy destination is a real mappable buffer, and one that is also
/// storage (what `createStorageBuffer(hostReadable: true)` always made) is a
/// storage buffer with `COPY_SRC`, read back through a staging copy — the
/// contract's `MappedBuffer` allows "a copy where it cannot". The same for
/// writing, through `COPY_DST` and `queue.writeBuffer`.
int gpuBufferUsageOf(BufferUsage usage) {
  final readOnlyMap =
      usage.contains(BufferUsage.hostReadable) &&
      (usage.bits &
              ~(BufferUsage.hostReadable.bits |
                  BufferUsage.copyDestination.bits)) ==
          0;
  final writeOnlyMap =
      usage.contains(BufferUsage.hostWritable) &&
      (usage.bits &
              ~(BufferUsage.hostWritable.bits | BufferUsage.copySource.bits)) ==
          0;
  return (usage.contains(BufferUsage.vertex) ? GpuBufferUsage.vertex : 0) |
      (usage.contains(BufferUsage.index) ? GpuBufferUsage.index : 0) |
      (usage.contains(BufferUsage.uniform) ? GpuBufferUsage.uniform : 0) |
      (usage.contains(BufferUsage.storage) ? GpuBufferUsage.storage : 0) |
      (usage.contains(BufferUsage.indirect) ? GpuBufferUsage.indirect : 0) |
      (usage.contains(BufferUsage.copySource) ? GpuBufferUsage.copySrc : 0) |
      (usage.contains(BufferUsage.copyDestination)
          ? GpuBufferUsage.copyDst
          : 0) |
      (readOnlyMap ? GpuBufferUsage.mapRead | GpuBufferUsage.copyDst : 0) |
      (writeOnlyMap ? GpuBufferUsage.mapWrite | GpuBufferUsage.copySrc : 0) |
      // Read back through a staging copy, or written through the queue.
      (usage.contains(BufferUsage.hostReadable) && !readOnlyMap
          ? GpuBufferUsage.copySrc
          : 0) |
      (usage.contains(BufferUsage.hostWritable) && !writeOnlyMap
          ? GpuBufferUsage.copyDst
          : 0);
}

/// A general buffer — `GraphicsDevice.createBuffer`, its gates already
/// passed. [contents] are written through a mapping at creation, which needs
/// no usage the caller did not ask for.
StorageBuffer webgpuCreateBuffer(
  GPUDevice gpu,
  BufferDescriptor descriptor, {
  ByteData? contents,
}) {
  final length = descriptor.lengthInBytes;
  if (contents != null && contents.lengthInBytes > length) {
    throw ArgumentError.value(
      contents.lengthInBytes,
      'contents',
      'is longer than the $length-byte buffer',
    );
  }
  final size = ((length < 4 ? 4 : length) + 3) & ~3;
  final buffer = gpu.createBuffer(
    GPUBufferDescriptor(
      size: size,
      usage: gpuBufferUsageOf(descriptor.usage),
      mappedAtCreation: contents != null,
      label: descriptor.label ?? 'buffer $length',
    ),
  );
  if (contents != null) {
    buffer.getMappedRange().toDart.asUint8List().setRange(
      0,
      contents.lengthInBytes,
      contents.buffer.asUint8List(
        contents.offsetInBytes,
        contents.lengthInBytes,
      ),
    );
    buffer.unmap();
  }
  GeometryBuffer? view(BufferUsage as) => descriptor.usage.contains(as)
      ? wrapGeometry(
          backend: WebGpuGeometry(buffer),
          offsetInBytes: 0,
          lengthInBytes: length,
        )
      : null;
  return wrapStorageBuffer(
    backend: WebGpuStorage(buffer, length),
    lengthInBytes: length,
    hostReadable: descriptor.usage.contains(BufferUsage.hostReadable),
    asIndices: view(BufferUsage.index),
    asVertices: view(BufferUsage.vertex),
    usage: descriptor.usage,
  );
}

/// One texel — white, or zero depth — in the shape a slot with nothing bound
/// wants. See `WebGpuDevice.bindGroupFor`.
WebGpuTexture webgpuCreateBlank(
  GPUDevice gpu,
  List<WebGpuTexture> tracked,
  WebGpuTextureDimension dimension, {
  required bool depth,
}) {
  final layers = switch (dimension) {
    WebGpuTextureDimension.cube || WebGpuTextureDimension.cubeArray => 6,
    _ => 1,
  };
  final texture = gpu.createTexture(
    GPUTextureDescriptor(
      size: GPUExtent3DDict(width: 1, height: 1, depthOrArrayLayers: layers),
      // A WebGPU texture starts zeroed, which is the depth an unbound
      // comparison slot reads.
      format: depth ? 'depth16unorm' : 'rgba8unorm',
      usage: GpuTextureUsage.textureBinding | GpuTextureUsage.copyDst,
      sampleCount: 1,
      mipLevelCount: 1,
      dimension: switch (dimension) {
        WebGpuTextureDimension.oneDimensional => '1d',
        WebGpuTextureDimension.threeDimensional => '3d',
        _ => '2d',
      },
      label: 'blank ${dimension.gpuName}${depth ? ' depth' : ''}',
    ),
  );
  if (!depth) {
    for (var layer = 0; layer < layers; layer++) {
      gpu.queue.writeTexture(
        GPUTexelCopyTextureInfo(
          texture: texture,
          mipLevel: 0,
          origin: GPUOrigin3DDict(x: 0, y: 0, z: layer),
          aspect: 'all',
        ),
        Uint8List.fromList(const <int>[255, 255, 255, 255]).toJS,
        GPUTexelCopyBufferLayout(offset: 0, bytesPerRow: 4, rowsPerImage: 1),
        GPUExtent3DDict(width: 1, height: 1, depthOrArrayLayers: 1),
      );
    }
  }
  final backend = WebGpuTexture(
    texture: texture,
    dimension: dimension,
    sampleable: true,
  );
  tracked.add(backend);
  return backend;
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
