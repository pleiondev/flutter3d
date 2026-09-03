/// The flutter_gpu side of [GraphicsDevice] and [CommandEncoder].
///
/// Everything that used to reach `gpu.gpuContext` from the renderer, its nodes
/// and its contributors is here, behind an object that arrives as an argument.
/// This is the file a second backend is written *beside*, not inside.
///
/// Split across a few files by cohesive concern, all re-exported from here:
/// [GpuShaderLibrary] is `gpu_shader_library.dart`; [GpuCommandEncoder] — one
/// command buffer with one open pass — is `gpu_command_encoder.dart`;
/// [GpuFrame], which tracks when a frame's submitted work is actually done, is
/// `gpu_frame.dart`.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'gpu_command_encoder.dart';
import 'gpu_formats.dart';
import 'gpu_frame.dart';
import 'gpu_frame_image.dart';
import 'gpu_loaded_shaders.dart';
import 'gpu_readback.dart';
import 'gpu_shader_library.dart';
import 'gpu_texture.dart';
import 'host_buffer_grid.dart';

export 'gpu_command_encoder.dart';
export 'gpu_frame.dart';
export 'gpu_loaded_shaders.dart';
export 'gpu_shader_library.dart';

/// flutter_gpu as a [GraphicsDevice].
///
/// Construct one and hand it to `Renderer.create`. Nothing else in the engine
/// names flutter_gpu, which is what makes the import graph a property somebody
/// can check: `tool/structure.dart`'s "the hardware layer names no graphics
/// API" rule scans for it.
final class GpuRenderBackend implements GraphicsDevice {
  GpuRenderBackend._(this._library, this._transients, this._granule);

  /// Loads [bundleAsset] and builds a backend around the running context.
  ///
  /// Throws when the bundle is missing, which is the right moment to fail: a
  /// renderer without its shaders cannot draw anything, and the alternative is
  /// a black screen with a null somewhere.
  ///
  /// **A static method rather than a factory constructor**, because loading the
  /// bundle became asynchronous in flutter_gpu 3.47 and a factory constructor
  /// cannot be. The name is kept so every call site reads the same with an
  /// `await` in front of it.
  /// [extraBundles] are the application's own compiled bundles, searched before
  /// the engine's — see [GpuShaderLibrary]. Each is loaded the same way and
  /// each has to exist: a bundle named and not found is a stage that will come
  /// back null at the first draw, which on this backend is a pipeline built
  /// from nothing.
  static Future<GpuRenderBackend> create({
    String bundleAsset = defaultBundleAsset,
    List<String> extraBundles = const <String>[],
  }) async {
    final library = await gpu.ShaderLibrary.fromAsset(bundleAsset);
    if (library == null) {
      throw StateError('Failed to load the shader bundle: $bundleAsset');
    }
    final extra = <gpu.ShaderLibrary>[];
    for (final asset in extraBundles) {
      final loaded = await gpu.ShaderLibrary.fromAsset(asset);
      if (loaded == null) {
        // Thrown rather than skipped, and named. The failure this avoids is an
        // application whose effect silently falls back to the engine's stage of
        // the same name, or to nothing — both of which look like the effect
        // being wrong rather than the bundle being absent.
        throw StateError('Failed to load an extra shader bundle: $asset');
      }
      extra.add(loaded);
    }
    return GpuRenderBackend._(
      GpuShaderLibrary(library, extra),
      // Per-frame uniform allocators, rotated rather than reset in place.
      //
      // `CommandBuffer.submit` is asynchronous. Resetting a bump allocator
      // right after submit rewinds storage the GPU may still be reading, so the
      // next frame overwrites live uniforms. The symptom is flickering under
      // load, not a crash, which makes it hard to attribute.
      //
      // The block length is a whole number of granules, and every write is
      // rounded to one. `host_buffer_grid.dart` says why: without it
      // `HostBuffer.emplace` hands out ranges that run off the end of a block
      // and throws in the middle of a frame.
      List<gpu.HostBuffer>.generate(
        _kFramesInFlight,
        (_) => gpu.gpuContext.createHostBuffer(
          blockLengthInBytes: blockLengthFor(granule),
        ),
      ),
      granule,
    );
  }

  /// The bundle this package ships, package-qualified.
  ///
  /// It lives here rather than on `Renderer` because it is `impellerc` output:
  /// an artefact only this backend can read, built by this package's
  /// `tool/build_shaders.sh` from this package's `shaders/`. The engine names
  /// the shaders it wants by entry point and does not know what compiled them.
  ///
  /// The `packages/<name>/` prefix is how Flutter addresses a dependency's
  /// assets, and it is the same string from inside this package as from an
  /// application that merely depends on it.
  static const String defaultBundleAsset =
      'packages/flutter3d_impeller/assets/shaders/flutter3d.shaderbundle';

  static const int _kFramesInFlight = 3;

  /// What every write into a transient buffer is rounded up to.
  ///
  /// Asked of the backend rather than assumed: the alignment is a property of
  /// the device, and a granule below it would let `emplace`'s own padding move
  /// the cursor off the grid this depends on.
  static int get granule =>
      granuleFor(gpu.gpuContext.minimumUniformByteAlignment);

  /// The granule these allocators were built on.
  final int _granule;

  /// Where each allocator's cursor is, mirrored so a write that would not fit
  /// in what is left of a block can be pushed onto the next one. See
  /// `host_buffer_grid.dart`.
  late final List<BlockCursor> _cursors = List<BlockCursor>.generate(
    _kFramesInFlight,
    (_) =>
        BlockCursor(blockLength: blockLengthFor(_granule), granule: _granule),
  );

  /// Writes [bytes] into this frame's allocator without letting it hand back a
  /// range that runs off the end of a block.
  gpu.BufferView emplace(ByteData bytes) {
    final host = _host;
    final cursor = _cursors[_frame < 0 ? 0 : _frame];
    final on = padded(bytes, _granule);
    final filler = cursor.fillerBefore(on.lengthInBytes);
    if (filler > 0) host.emplace(ByteData(filler));
    cursor.took(on.lengthInBytes);
    return host.emplace(on);
  }

  final GpuShaderLibrary _library;
  final List<gpu.HostBuffer> _transients;

  /// Which allocator this frame writes into. -1 until the first [beginFrame].
  int _frame = -1;

  gpu.HostBuffer get _host => _transients[_frame < 0 ? 0 : _frame];

  @override
  ShaderLibrary get shaders => _library;

  /// Through `ShaderLibrary.fromBytes`, once the header's SDK is this one's.
  /// See [GpuLoadedShaderLibrary] for what a reload does and cannot do here.
  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) =>
      GpuLoadedShaderLibrary.load(bytes, running: runningSdk);

  @override
  // Through `gpu_texture.dart`, which keeps the first answer — see the note
  // there about a context that stops reporting one.
  TextureFormat get defaultColorFormat => defaultColorFormatOfContext;

  @override
  TextureFormat get defaultDepthStencilFormat =>
      gpu.gpuContext.defaultDepthStencilFormat.toEngine();

  @override
  // Impeller runs on Metal and Vulkan conventions.
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  @override
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  // Renderable everywhere flutter_gpu runs, with nothing to enable.
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  @override
  // Four is what this engine's goldens were recorded with.
  int get preferredSampleCount => 4;

  @override
  bool get supportsOffscreenMsaa => gpu.gpuContext.doesSupportOffscreenMSAA;

  @override
  // Impeller exposes glPolygonMode's equivalent, so the request goes through.
  bool get supportsWireframe => true;

  @override
  // flutter_gpu's depth-stencil format is documented never to be depth-only,
  // so a device that names one has a stencil beside its depth; one that
  // answers `unknown` has neither, and the x-ray stage stays off.
  bool get supportsStencil =>
      gpu.gpuContext.defaultDepthStencilFormat != gpu.PixelFormat.unknown;

  @override
  bool get supportsMipmaps => gpu.gpuContext.doesSupportManuallyMippedTextures;

  /// flutter_gpu's own answer, which is per compression family underneath:
  /// BC on a desktop GPU, ETC2 and ASTC on a mobile one, all three on Apple
  /// silicon, and its `formats.dart` says to ask before allocating. An
  /// uncompressed format is a yes today because the capability surface does
  /// not vary by format there; that is flutter_gpu's statement, and this
  /// repeats it rather than restating it as a table of its own.
  @override
  bool supportsTextureFormat(TextureFormat format) =>
      gpu.gpuContext.supportsTextureFormat(format.toGpu());

  /// flutter_gpu's own answer: sixteen on every Metal and Vulkan device this
  /// has run on, and one where the driver has no anisotropic sampler. A
  /// sampler asking for more than this is clamped inside `bindTexture`, which
  /// is flutter_gpu's documented behaviour and not a courtesy of this layer.
  @override
  int get maxAnisotropy => gpu.gpuContext.maxSamplerAnisotropy;

  /// Probed once, because flutter_gpu reports no capability for it.
  ///
  /// Every other `supports` here answers from `gpuContext`; there is no
  /// `doesSupportCubeTextures`. Allocating a one-by-one cube is the cheapest
  /// question that gets a real answer from the driver, and the alternative —
  /// returning a constant true — is a claim about every device this ever runs
  /// on, made by someone who tested one.
  @override
  bool get supportsCubeTextures => _cubesWork ??= _probeCubes();

  bool? _cubesWork;

  /// **The texture it makes is dropped, and that is not a leak.** A reviewer
  /// asked; the answer is that `flutter_gpu`'s `Texture` is a native field
  /// wrapper with no `dispose` — there is no way to release one, and the object
  /// going out of scope is how every texture in this backend is freed. One
  /// pixel, once per process, is the price of the only question that gets a
  /// real answer from the driver.
  ///
  /// The `catch` cannot tell "this driver has no cube textures" from "something
  /// else went wrong", and deliberately does not try: both answers mean the
  /// same thing to a caller deciding whether to build a cube map.
  bool _probeCubes() {
    try {
      gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        1,
        1,
        textureType: gpu.TextureType.textureCube,
        enableRenderTargetUsage: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  TextureHandle? createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) {
    // Six, in the order the interface documents: +X, −X, +Y, −Y, +Z, −Z. A
    // shorter list is a caller bug rather than a device one, and refusing it
    // here is what stops five faces and one of whatever the allocation happened
    // to contain.
    if (faces.length != 6) return null;
    if (!supportsCubeTextures) return null;
    // **Sizes checked here rather than left to the upload**, and the
    // conformance suite is why: `overwrite` throws when a buffer is not exactly
    // its level's size, so a chain built with the wrong arithmetic took the
    // frame down where the other two backends returned null. Refusing early is
    // what the interface documents, and what the software and WebGL backends
    // already did.
    final levels = mipLevels ?? const <List<ByteData>>[];
    var side = size;
    for (final level in levels) {
      if (level.length != 6) return null;
      side = side > 1 ? side >> 1 : 1;
      for (final face in level) {
        if (face.lengthInBytes != side * side * 4) return null;
      }
    }
    // The base faces too, and before the allocation rather than after it, as
    // this used to be: a cube refused for its face size was a cube already
    // created, with nothing but the collector to take it back.
    final expected = _baseLevelLengthInBytes(size, size, format);
    for (final face in faces) {
      if (face.lengthInBytes != expected) return null;
    }

    final texture = createGpuTexture(
      StorageMode.hostVisible,
      size,
      size,
      format: format,
      type: TextureType.textureCube,
      // One more than the levels below it, the same arithmetic
      // `createTextureFromPixels` does.
      mipLevelCount: levels.isEmpty ? 1 : levels.length + 1,
      // Nothing renders into a face: `ColorTarget` carries no slice, so a cube
      // can only ever be filled from the host. Asking for render-target usage
      // would be asking for an allocation nothing can use.
      enableRenderTargetUsage: false,
    );

    for (var i = 0; i < 6; i++) {
      texture.gpuTexture.overwrite(faces[i], slice: i);
    }

    // Level by level and face by face, and only as far as the texture actually
    // goes: writing a level it does not have throws, and a chain longer than
    // the allocation is the ordinary case rather than a mistake.
    final allocated = texture.gpuTexture.mipLevelCount;
    for (
      var level = 0;
      level < levels.length && level + 1 < allocated;
      level++
    ) {
      for (var face = 0; face < 6; face++) {
        texture.gpuTexture.overwrite(
          levels[level][face],
          slice: face,
          mipLevel: level + 1,
        );
      }
    }
    return texture;
  }

  @override
  TextureHandle createTexture(RenderTargetSpec spec) => createGpuTexture(
    spec.storageMode,
    spec.width,
    spec.height,
    format: spec.format,
    sampleCount: spec.sampleCount,
    // Transient textures live in tile memory and cannot be sampled, so
    // asking for shader read on one is a contradiction the driver would
    // have to resolve for us.
    enableShaderReadUsage: spec.storageMode != StorageMode.deviceTransient,
  );

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutSpec? layout,
  }) => PipelineHandle(
    backend: gpu.gpuContext.createRenderPipeline(
      vertex.backend as gpu.Shader,
      fragment.backend as gpu.Shader,
      // Null is passed through rather than replaced with a layout derived
      // from the shader. flutter_gpu does that derivation itself, and doing
      // it here as well would be a second answer to the question the
      // reflection already answers.
      vertexLayout: layout?.toGpu(),
    ),
    name: '${vertex.name}+${fragment.name}',
  );

  /// [usage] is ignored here, and that is not laziness.
  ///
  /// A flutter_gpu `DeviceBuffer` is untyped: the same buffer can be bound as
  /// vertices in one draw and as indices in the next. The parameter exists
  /// because WebGL cannot do that — it binds a buffer to its target for life —
  /// and a contract that let one backend infer what the other must be told
  /// would be a contract only one backend could implement.
  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    final buffer = gpu.gpuContext.createDeviceBufferWithCopy(bytes);
    return GeometryBuffer(
      backend: buffer,
      offsetInBytes: 0,
      lengthInBytes: buffer.sizeInBytes,
    );
  }

  @override
  TextureHandle? createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    // `overwrite` demands exactly the base mip size and throws otherwise, so
    // asking first turns a mismatch into a null the caller can handle. Bytes
    // per texel is a backend question — padding and alignment are the device's
    // — which is precisely why this check cannot live above the seam. Asked
    // *before* the allocation rather than of the allocated texture, as it used
    // to be: a texture made only to be refused is a texture this backend has
    // no way to free except the collector.
    if (pixels.lengthInBytes !=
        _baseLevelLengthInBytes(width, height, format)) {
      return null;
    }

    final texture = createGpuTexture(
      // Host-visible, because these bytes come from the CPU. That is a
      // consequence of *how the texture is filled* rather than of what it is
      // for, which is why it is not a parameter above.
      //
      // This used to also ask for origin-at-the-bottom, via a
      // `TextureCoordinateSystem` flutter_gpu deleted in 3.47. It never had an
      // effect worth the line: the setting was read by the path that turns a
      // texture into a `ui.Image`, not by a shader sampling one, and the two
      // backends that have no such concept have always drawn these textures
      // the same way up — `normal-mapping`, a grid of tiles where a vertical
      // flip could not hide, sits at 1.1% between them.
      StorageMode.hostVisible,
      width,
      height,
      format: format,
      // One more than the levels below it. flutter_gpu clamps its own
      // allocation at `fullMipCount`, which stops one short of one-by-one, so a
      // longer chain than the device will hold is trimmed rather than refused —
      // and the trimming happens there, where the limit is known.
      mipLevelCount: mipLevels == null ? 1 : mipLevels.length + 1,
      // A block-compressed format is sample-only everywhere — see the note on
      // `TextureFormat`'s compressed values — and `gpuContext.createTexture`
      // enforces that itself: it throws for a compressed format asking for
      // render-target usage. This is the same refusal
      // `createCubeTextureFromPixels` already gives every face, for the same
      // reason: nothing here ever renders into an upload made from bytes.
      //
      // `format.isCompressed` (`flutter3d_hardware`) rather than
      // `format.toGpu().isCompressed` (flutter_gpu's own extension): the two
      // are checked against each other for every value in
      // `gpu_formats_test.dart`, and this line reads the one every other
      // backend can also read, so a WebGL2 or CPU call site never has to ask
      // flutter_gpu's opinion of a format to answer the same question.
      enableRenderTargetUsage: !format.isCompressed,
    );
    texture.gpuTexture.overwrite(pixels);
    if (mipLevels != null) {
      // Level by level, and only as far as the texture actually goes: asking
      // to write a level it does not have throws, and a chain longer than
      // `fullMipCount` is the ordinary case rather than a mistake.
      final levels = texture.gpuTexture.mipLevelCount;
      for (var i = 0; i < mipLevels.length && i + 1 < levels; i++) {
        texture.gpuTexture.overwrite(mipLevels[i], mipLevel: i + 1);
      }
    }
    return texture;
  }

  /// The byte length `overwrite` will demand for a [width] by [height] base
  /// level of [format].
  ///
  /// flutter_gpu's own arithmetic — `Texture.getMipLevelSizeInBytes`, whole
  /// blocks times bytes per block — reproduced so the question can be asked
  /// *before* a texture exists to ask it of. Both upload paths used to
  /// allocate first and read the answer off the texture, which meant a
  /// refused upload had already made an allocation nothing could free but the
  /// collector. Benign on this backend, but an ordering nothing should rest
  /// on. The extension getters this reads are flutter_gpu's, so a format it
  /// learns a new size for answers here too.
  static int _baseLevelLengthInBytes(
    int width,
    int height,
    TextureFormat format,
  ) {
    final gpuFormat = format.toGpu();
    final blocksWide =
        (width + gpuFormat.blockWidth - 1) ~/ gpuFormat.blockWidth;
    final blocksHigh =
        (height + gpuFormat.blockHeight - 1) ~/ gpuFormat.blockHeight;
    return blocksWide * blocksHigh * gpuFormat.bytesPerBlock;
  }

  @override
  void beginFrame() {
    // The frame that was being encoded is now complete as far as this side is
    // concerned: no more passes will be added to it, so if the GPU has already
    // finished every buffer it holds, its callbacks can run.
    _openFrame.encoded = true;
    // Anything still open was abandoned by a throw part way through encoding —
    // see `GpuFrame.abandonUnsubmitted`. Without this the frame waits for a
    // pass nobody will ever submit and its callbacks never run.
    _openFrame.abandonUnsubmitted();
    _openFrame.settleIfDone();
    _openFrame = GpuFrame();

    _frame = (_frame + 1) % _kFramesInFlight;
    // **This allocator leaks a block per boundary crossing, so past a budget
    // it is cheaper to throw it away than to keep it.** The bug is upstream:
    // `flutter_gpu/lib/src/buffer.dart`, `HostBuffer._allocateEmplacement` —
    // the block-overflow branch always allocates a fresh 1 MB `DeviceBuffer`
    // and appends it to the current internal frame's `_buffers` list, and
    // `reset()` only rewinds cursors and rotates the internal ring, never
    // trimming or reusing the tail. Every frame whose transient writes cross a
    // block boundary grows the list by a block, forever. The [BlockCursor]
    // mirrors the crossings exactly (see `host_buffer_grid.dart`), so once a
    // slot has accumulated [_kTransientBlockBudget] of them we recreate its
    // `HostBuffer` here, at the one point where doing so is safe — and the
    // safety argument is the same as the rewind's below: this slot was last
    // written a full ring of frames ago, so the GPU is done with it, and any
    // command buffer still in flight holds its own references to the old
    // `DeviceBuffer`s. Dropping ours frees nothing early; the wrappers go when
    // the collector gets to them, which is the only release flutter_gpu has.
    // A flutter_gpu that fixes the overflow branch makes this whole clause —
    // and `BlockCursor.crossed` — deletable.
    if (_cursors[_frame].crossed >= _kTransientBlockBudget) {
      _transients[_frame] = gpu.gpuContext.createHostBuffer(
        blockLengthInBytes: blockLengthFor(_granule),
      );
      _cursors[_frame] = BlockCursor(
        blockLength: blockLengthFor(_granule),
        granule: _granule,
      );
      _transientRecreations++;
    }
    // Safe to rewind: this allocator was last written a full ring of frames
    // ago, so the GPU is done with it.
    _transients[_frame].reset();
    _cursors[_frame].reset();
  }

  /// When a transient slot's leaked-block estimate is worth a fresh allocator.
  ///
  /// Thirty-two blocks is about 32 MB retained by one slot — three slots, so
  /// under 100 MB in the worst case before every slot has been recreated. Low
  /// enough that the leak stays invisible next to the render targets, high
  /// enough that a scene crossing a boundary or two per frame recreates a slot
  /// every few hundred frames rather than every few, and each recreation only
  /// costs the four fresh blocks `HostBuffer`'s constructor allocates.
  static const int _kTransientBlockBudget = 32;

  /// How many transient allocators have been thrown away over the leak above.
  ///
  /// Diagnostic, like [rejectedSubmissions]: a number climbing fast means the
  /// scene's per-frame transient writes dwarf the block budget, which is worth
  /// knowing about rather than merely surviving.
  int get debugTransientRecreations => _transientRecreations;
  int _transientRecreations = 0;

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    final buffer = gpu.gpuContext.createCommandBuffer();
    final pass = buffer.createRenderPass(_toRenderTarget(descriptor));
    final frame = _openFrame;
    frame.encoding++;
    return GpuCommandEncoder(buffer, pass, this, frame);
  }

  /// The frame being encoded, and the ones the GPU has not finished.
  ///
  /// **A frame is not over when `submit` returns.** flutter_gpu hands the work
  /// to the queue and comes straight back; what is on the screen is a texture
  /// this backend still owns, and drawing into it again before the compositor
  /// has read it is a picture made of two frames. Which is exactly what an
  /// editor holding a still camera showed, and what three, and eight, and
  /// sixteen buffers each made rarer without making impossible.
  GpuFrame _openFrame = GpuFrame();

  /// How many command buffers the driver has refused since this device opened.
  ///
  /// **The one signal flutter_gpu offers about a failed submission**, and it
  /// was being discarded: `submit`'s completion callback takes a `bool ok`
  /// which nothing read, so a rejected buffer produced the same counters and
  /// the same frame result as one that executed. Nothing above the driver
  /// reports this otherwise — the frame simply comes back missing whatever
  /// that pass drew.
  ///
  /// Zero on a healthy device, and anything else is worth investigating rather
  /// than tolerating.
  int get rejectedSubmissions => _rejectedSubmissions;
  int _rejectedSubmissions = 0;

  /// Called from the encoder's completion callback. Not private because the
  /// encoder is a separate class in a separate file, and the alternative is a
  /// setter that says less.
  void noteRejectedSubmission() => _rejectedSubmissions++;

  @override
  void onFrameComplete(void Function() whenDone) =>
      _openFrame.whenDone.add(whenDone);

  @override
  Widget present(
    TextureHandle frame, {
    BoxFit fit = BoxFit.fill,
    FilterQuality quality = FilterQuality.none,
  }) =>
      // A stateful widget rather than `asImage()` inline into a `RawImage`,
      // which is what this was: the inline image was never disposed, so every
      // frame left a `ui.Image` for the collector and pinned the frame texture
      // in the engine's image accounting past the frames-in-flight ring. The
      // widget owns the image and closes it — see `gpu_frame_image.dart`.
      GpuFrameImage(frame: frame, fit: fit, quality: quality);

  @override
  Future<ByteData?> readPixels(TextureHandle texture) {
    // Tile memory holds nothing once the pass has ended, and the backend's own
    // failure for this is unhelpful. Say it here, where the caller is in scope.
    if (texture.storageMode == StorageMode.deviceTransient) {
      return Future<ByteData?>.value();
    }
    // Premultiplied, which is what `rawRgba` means and what the reference PNGs
    // are decoded as. The two sides of a golden comparison must agree, and the
    // engine's own output is opaque, so this is the layout with no conversion
    // anywhere in the path.
    //
    // The image is closed once the bytes are out. It is only a handle — the
    // backend still owns the texture — but leaving it open made every readback
    // a `ui.Image` for the collector, and goldens read back a lot of them.
    final image = texture.gpuTexture.asImage();
    return image
        .toByteData(format: ui.ImageByteFormat.rawRgba)
        .whenComplete(image.dispose);
  }

  /// A copy queued in order and read off a staging texture when the queue
  /// says it ran — see `gpu_readback.dart` for why not `copyTextureToBuffer`.
  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) =>
      _readback.read(texture, region);

  late final GpuReadback _readback = GpuReadback(
    onRejectedSubmission: noteRejectedSubmission,
  );

  /// How many staging textures the readbacks have made so far. Diagnostic.
  int get debugReadbackStagingCount => _readback.debugStagingCount;

  /// A deliberate no-op. See the note at [supportsCubeTextures] on
  /// `_probeCubes`: flutter_gpu's `Texture` has no native dispose, so every
  /// texture and buffer this backend has handed out is already relying on
  /// nothing but going out of scope and the garbage collector — there is no
  /// call this method could make that would free anything sooner. Kept as a
  /// real method rather than left unimplemented so a caller that tears down
  /// every [GraphicsDevice] uniformly does not have to special-case this one.
  @override
  void dispose() {}

  /// A no-op, and the reason is flutter_gpu's rather than this backend's:
  /// `gpu.Texture` has no native dispose, so letting the last reference go is
  /// the only release path there is here. That makes this the right
  /// implementation and an unusual one — the engine still calls it, because on
  /// WebGL2 the same call is the difference between a resize costing nothing
  /// and a tab that grows until the context is lost.
  @override
  void releaseTexture(TextureHandle texture) {}

  @override
  void releaseGeometry(GeometryBuffer geometry) {}

  static gpu.RenderTarget _toRenderTarget(RenderPassDescriptor descriptor) =>
      gpu.RenderTarget(
        colorAttachments: <gpu.ColorAttachment>[
          for (final color in descriptor.colors)
            gpu.ColorAttachment(
              texture: color.texture.gpuTexture,
              resolveTexture: color.resolveTexture?.gpuTexture,
              loadAction: color.loadAction.toGpu(),
              storeAction: color.storeAction.toGpu(),
              clearValue: color.clearValue,
            ),
        ],
        depthStencilAttachment: switch (descriptor.depth) {
          null => null,
          // Depth cleared on entry and discarded on exit, because that is the
          // only thing any pass in this engine has ever wanted; the stencil
          // half is the descriptor's to say. See [DepthTarget].
          final DepthTarget depth => gpu.DepthStencilAttachment(
            texture: depth.texture.gpuTexture,
            depthClearValue: depth.clearValue,
            stencilLoadAction: depth.stencilLoadAction.toGpu(),
            stencilStoreAction: depth.stencilStoreAction.toGpu(),
            stencilClearValue: depth.stencilClearValue,
          ),
        },
      );
}
