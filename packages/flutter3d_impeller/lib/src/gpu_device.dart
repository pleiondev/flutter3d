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

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'gpu_buffer.dart';
import 'gpu_capabilities.dart';
import 'gpu_command_encoder.dart';
import 'gpu_formats.dart';
import 'gpu_frame.dart';
import 'gpu_loaded_shaders.dart';
import 'gpu_readback.dart';
import 'gpu_shader_library.dart';
import 'gpu_texture.dart';
import 'gpu_transfer_encoder.dart';
import 'host_buffer_grid.dart';

export 'gpu_capabilities.dart' show impellerBackendName;
export 'gpu_frame_image.dart';

/// flutter_gpu as a [GraphicsDevice].
///
/// Construct one and hand it to `Renderer.create`. Nothing else in the engine
/// names flutter_gpu, which is what makes the import graph a property somebody
/// can check: `tool/structure.dart`'s "the hardware layer names no graphics
/// API" rule scans for it.
final class GpuRenderBackend extends GraphicsDevice {
  @override
  String get backendName => 'Impeller';

  /// [frame] — a texture this device made, such as `FrameResult.frame` — as
  /// a `dart:ui` image over the same allocation, without a copy. What a
  /// widget that composites the engine's frame itself paints.
  ui.Image frameImage(TextureHandle frame) => frame.gpuTexture.asImage();

  // TODO(impeller): debug groups, resource labels, device loss and
  // asynchronous pipelines. flutter_gpu exposes no debug labels, no loss
  // signal and no asynchronous pipeline creation, so the inherited defaults
  // stand: groups and markers do nothing, labels are kept for `labelOf`
  // only, `lost` never fires, and `createPipelineAsync` links in the calling
  // turn.

  // ------------------------------------------------------- capabilities

  /// What flutter_gpu exposes here — see `gpu_capabilities.dart`, where each
  /// feature is decided and each absent one names what flutter_gpu lacks.
  /// Asked once: every input is a property of the context.
  @override
  late final DeviceFeatures features = impellerFeatures(
    cubesWork: _probeCubes(),
  );

  @override
  late final DeviceLimits limits = impellerLimits(
    renderToMip: features.has(DeviceFeature.renderToMipLevel),
    msaa: features.has(DeviceFeature.offscreenMultisample),
  );

  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) =>
      impellerFormatSupport(format, features);

  /// Never called: [features] has no `gpuTimestamps`.
  @override
  void onGpuTimings(void Function(GpuFrameTimings timings)? listener) {}

  /// Refuses every compute member below with the same words.
  // TODO(impeller): flutter_gpu has no compute pipeline, compute pass or
  // storage binding — unblocked by flutter/flutter#188480, whose proposal
  // (#188474) the contract's compute shape already follows.
  Never _noCompute() => throw UnsupportedCapability(
    DeviceFeature.compute,
    backend: impellerBackendName,
    reason:
        'flutter_gpu has no compute pipeline yet (flutter/flutter#188480); '
        'splats sort on the CPU here',
  );

  @override
  StorageBuffer createStorageBuffer(
    ByteData bytes, {
    bool hostReadable = false,
    bool bindableAsIndices = false,
  }) => _noCompute();

  @override
  ComputePipelineHandle createComputePipeline(ShaderHandle shader) =>
      _noCompute();

  @override
  ComputeEncoder beginComputePass({
    String? label,
    PassTimestampWrites? timestampWrites,
  }) => _noCompute();

  /// The contents of a [BufferUsage.hostReadable] buffer [createBuffer] made,
  /// from the host's copy of it — see `gpu_buffer.dart` for why that copy is
  /// exactly what the buffer holds on this backend. Any other buffer is a
  /// compute buffer, and refused as one.
  @override
  Future<ByteData> readBuffer(StorageBuffer buffer) {
    final backend = buffer.backend;
    if (backend is! GpuBuffer) _noCompute();
    if (!buffer.usage.contains(BufferUsage.hostReadable)) {
      throw ArgumentError(
        'readBuffer: this buffer was made without BufferUsage.hostReadable',
      );
    }
    return Future<ByteData>.value(backend.read(0, buffer.lengthInBytes));
  }

  /// A no-op, for [releaseTexture]'s reason: a `DeviceBuffer` has no native
  /// release either. Only [createBuffer] makes one here.
  @override
  void releaseStorageBuffer(StorageBuffer buffer) {}

  @override
  List<TextureFormat> get hdrOutputFormats => const <TextureFormat>[];

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
  static Future<GpuRenderBackend> open({
    String bundleAsset = defaultBundleAsset,
    List<String> extraBundles = const <String>[],
  }) async {
    final library = await gpu.ShaderLibrary.fromAsset(bundleAsset);
    if (library == null) {
      throw DeviceUnavailableException(
        'Failed to load the shader bundle: $bundleAsset',
        backend: impellerBackendName,
      );
    }
    final extra = <gpu.ShaderLibrary>[];
    for (final asset in extraBundles) {
      final loaded = await gpu.ShaderLibrary.fromAsset(asset);
      if (loaded == null) {
        // Thrown rather than skipped, and named. The failure this avoids is an
        // application whose effect silently falls back to the engine's stage of
        // the same name, or to nothing — both of which look like the effect
        // being wrong rather than the bundle being absent.
        throw DeviceUnavailableException(
          'Failed to load an extra shader bundle: $asset',
          backend: impellerBackendName,
        );
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
          blockLengthInBytes: blockLengthFor(_deviceGranule),
        ),
      ),
      _deviceGranule,
    );
  }

  /// The bundle this package ships, package-qualified.
  ///
  /// It lives here rather than on `Renderer` because it is `impellerc` output:
  /// an artefact only this backend can read, built by this package's
  /// `tool/build_shaders.sh` from the GLSL in `flutter3d_shaders`, which every
  /// backend compiles its own way. The engine names the shaders it wants by
  /// entry point and does not know what compiled them.
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
  static int get _deviceGranule =>
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
  /// range that runs off the end of a block. The encoder reaches it through
  /// [GpuRenderBackendInternals.emplace].
  gpu.BufferView _emplace(ByteData bytes) {
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

  /// Whether cube textures work, probed once — `DeviceFeature.cubeTextures`.
  ///
  /// Every other feature here answers from `gpuContext`; there is no
  /// `doesSupportCubeTextures`. Allocating a one-by-one cube is the cheapest
  /// question that gets a real answer from the driver, and the alternative —
  /// returning a constant true — is a claim about every device this ever runs
  /// on, made by someone who tested one.
  ///
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
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) {
    features.require(DeviceFeature.cubeTextures, backend: impellerBackendName);
    return createGpuTexture(
      // Device-private: nothing on the host ever writes a face, and the two
      // things that read one — the prefilter and the lit shaders — are passes.
      StorageMode.devicePrivate,
      size,
      size,
      format: format,
      type: TextureType.textureCube,
      // Trimmed to what the device will allocate inside `createGpuTexture`,
      // as every chain here is.
      mipLevelCount: mipLevels,
      enableRenderTargetUsage: true,
    );
  }

  @override
  TextureHandle createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) {
    // Six, in the order the interface documents: +X, −X, +Y, −Y, +Z, −Z. A
    // shorter list is a caller bug rather than a device one, and refusing it
    // here is what stops five faces and one of whatever the allocation happened
    // to contain.
    if (faces.length != 6) {
      throw refuseResource(
        'createCubeTextureFromPixels',
        'a cube has six faces and ${faces.length} were given',
      );
    }
    features.require(DeviceFeature.cubeTextures, backend: impellerBackendName);
    // **Sizes checked here rather than left to the upload**, and the
    // conformance suite is why: `overwrite` throws when a buffer is not exactly
    // its level's size, so a chain built with the wrong arithmetic took the
    // frame down where the other two backends refused. Refusing early is
    // what the interface documents, and what the software and WebGL backends
    // already did.
    final levels = mipLevels ?? const <List<ByteData>>[];
    var side = size;
    for (final level in levels) {
      if (level.length != 6) {
        throw refuseResource(
          'createCubeTextureFromPixels',
          'a mip level of a cube has six faces and ${level.length} were given',
        );
      }
      side = side > 1 ? side >> 1 : 1;
      // Through the same arithmetic as the base below. Four bytes a texel was
      // right for RGBA8 alone: a half-float radiance cube's chain — eight
      // bytes a texel, the one use this parameter names — was refused level
      // by level while its base passed.
      final expected = _baseLevelLengthInBytes(side, side, format);
      for (final face in level) {
        if (face.lengthInBytes != expected) {
          throw refuseResource(
            'createCubeTextureFromPixels',
            'a ${side}x$side face of a mip level is $expected bytes and '
                '${face.lengthInBytes} were given',
          );
        }
      }
    }
    // The base faces too, and before the allocation rather than after it, as
    // this used to be: a cube refused for its face size was a cube already
    // created, with nothing but the collector to take it back.
    final expected = _baseLevelLengthInBytes(size, size, format);
    for (final face in faces) {
      if (face.lengthInBytes != expected) {
        throw refuseResource(
          'createCubeTextureFromPixels',
          'a ${size}x$size face is $expected bytes and ${face.lengthInBytes} '
              'were given',
        );
      }
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
      // Filled from the host and never drawn into: a cube a pass renders into
      // is `createCubeRenderTarget`'s, and asking for render-target usage on
      // an upload would be asking for an allocation nothing uses that way.
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

  TextureHandle _createTarget(RenderTargetDescriptor spec) => createGpuTexture(
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
    VertexLayoutDescriptor? layout,
  }) => wrapPipeline(
    owner: this,
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
    return wrapGeometry(
      backend: buffer,
      offsetInBytes: 0,
      lengthInBytes: buffer.sizeInBytes,
      release: releaseGeometry,
    );
  }

  /// `createDeviceBufferWithCopy` always makes a [gpu.StorageMode.hostVisible]
  /// buffer — see its own implementation — which is the one storage mode
  /// [gpu.DeviceBuffer.overwrite] accepts; every buffer [uploadGeometry] hands
  /// out here can therefore always be overwritten.
  ///
  /// [gpu.DeviceBuffer.flush] follows the write. On unified memory it is a
  /// no-op; on a discrete GPU without coherent host memory it is what actually
  /// moves the new bytes across, and skipping it there would leave the write
  /// visible to nothing until some unrelated flush happened to cover the same
  /// range.
  @override
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  ) {
    final buffer = target.backend as gpu.DeviceBuffer;
    if (offsetInBytes < 0 ||
        offsetInBytes + bytes.lengthInBytes > target.lengthInBytes) {
      throw ArgumentError(
        'overwriteGeometry: $offsetInBytes + ${bytes.lengthInBytes} does not '
        'fit inside a ${target.lengthInBytes}-byte buffer',
      );
    }
    final at = target.offsetInBytes + offsetInBytes;
    final ok = buffer.overwrite(bytes, destinationOffsetInBytes: at);
    if (!ok) {
      throw StateError(
        'DeviceBuffer.overwrite refused ${bytes.lengthInBytes} bytes at $at',
      );
    }
    buffer.flush(offsetInBytes: at, lengthInBytes: bytes.lengthInBytes);
  }

  /// `gpu.Texture.overwrite` replaces a whole mip level at once — there is
  /// no partial-region write on this backend — so a region write here means
  /// [readback]ing the level first, patching it in memory, and writing the
  /// whole level back through `overwrite`. The one call on this backend
  /// that is genuinely asynchronous for its own reason, not [loadShaders]'s.
  @override
  Future<void> overwriteTexture(
    TextureHandle target,
    ByteData rgba, {
    ScreenRect? region,
    int mipLevel = 0,
  }) async {
    if (!readbackFormats.contains(target.format)) {
      throw UnsupportedError(
        'overwriteTexture: TextureFormat.${target.format.name} is not one '
        'of readbackFormats — the two this call, like readback, insists on.',
      );
    }
    if (mipLevel != 0) {
      throw UnsupportedError(
        'overwriteTexture: mip level $mipLevel is refused; only the base '
        'level (0) may be overwritten.',
      );
    }
    final rect =
        region ?? ScreenRect(width: target.width, height: target.height);
    if (rect.x < 0 ||
        rect.y < 0 ||
        rect.x + rect.width > target.width ||
        rect.y + rect.height > target.height) {
      throw ArgumentError(
        'overwriteTexture: $rect does not fit inside a '
        '${target.width}x${target.height} texture',
      );
    }
    if (rgba.lengthInBytes != rect.width * rect.height * 4) {
      throw ArgumentError(
        'overwriteTexture: ${rgba.lengthInBytes} bytes does not match '
        '${rect.width}x${rect.height} RGBA8',
      );
    }

    final whole = await readback(target);
    final patched = Uint8List.fromList(
      whole.buffer.asUint8List(whole.offsetInBytes, whole.lengthInBytes),
    );
    final rowBytes = target.width * 4;
    for (var y = 0; y < rect.height; y++) {
      final srcRowStart = y * rect.width * 4;
      final dstRowStart = (rect.y + y) * rowBytes + rect.x * 4;
      patched.setRange(
        dstRowStart,
        dstRowStart + rect.width * 4,
        rgba.buffer.asUint8List(
          rgba.offsetInBytes + srcRowStart,
          rect.width * 4,
        ),
      );
    }
    // **Written back in the texture's own byte order.** The level came back
    // through `toByteData(rawRgba)`, which converts to RGBA whatever the
    // texture stores, and the caller's region is RGBA by contract — but
    // `overwrite` copies bytes as the texture lays them out. A
    // `b8g8r8a8UNormInt` target, which is this backend's default colour
    // format on Metal, would otherwise come back with red and blue exchanged
    // across the whole level, not only inside the region.
    if (target.format == TextureFormat.b8g8r8a8UNormInt) {
      for (var i = 0; i < patched.length; i += 4) {
        final red = patched[i];
        patched[i] = patched[i + 2];
        patched[i + 2] = red;
      }
    }
    target.gpuTexture.overwrite(ByteData.sublistView(patched), mipLevel: 0);
  }

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    // `overwrite` demands exactly the base mip size and throws otherwise, so
    // asking first turns a mismatch into a refusal the caller can handle. Bytes
    // per texel is a backend question — padding and alignment are the device's
    // — which is precisely why this check cannot live above the seam. Asked
    // *before* the allocation rather than of the allocated texture, as it used
    // to be: a texture made only to be refused is a texture this backend has
    // no way to free except the collector.
    final expected = _baseLevelLengthInBytes(width, height, format);
    if (pixels.lengthInBytes != expected) {
      throw refuseResource(
        'createTextureFromPixels',
        'a ${width}x$height ${format.name} texture is $expected bytes and '
            '${pixels.lengthInBytes} were given',
      );
    }
    // The levels too, for the reason `createCubeTextureFromPixels` above states
    // and this one had not caught up with: `overwrite` throws when a buffer is
    // not exactly its level's size, so a chain built with the wrong arithmetic
    // took the frame down here where the other two backends refused.
    // Through the same arithmetic as the base, so a block-compressed chain is
    // measured in whole blocks rather than in texels.
    if (mipLevels != null) {
      var w = width;
      var h = height;
      for (final level in mipLevels) {
        w = w > 1 ? w >> 1 : 1;
        h = h > 1 ? h >> 1 : 1;
        final need = _baseLevelLengthInBytes(w, h, format);
        if (level.lengthInBytes != need) {
          throw refuseResource(
            'createTextureFromPixels',
            'a ${w}x$h mip level is $need bytes and ${level.lengthInBytes} '
                'were given',
          );
        }
      }
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
  ///
  /// Nothing here reads it — the engine survives either way, which is the point.
  /// It is for whoever is looking at a frame time that grew: this and
  /// [GpuRenderBackendInternals.debugReadbackStagingCount] are the two numbers that say the cost is
  /// allocation rather than drawing.
  int get _debugTransientRecreations => _transientRecreations;
  int _transientRecreations = 0;

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    // `gfx-50n`. Before anything reaches flutter_gpu, because past this line
    // there is no Dart left to throw from: a second attachment on the GLES
    // path walks into an `FML_CHECK` and the process stops.
    descriptor
      ..checkAttachmentLimit(
        limits.maxColorAttachments,
        backend: 'the Impeller backend on this device',
      )
      // A layer above zero (no array textures here), a mip level above the
      // base where flutter_gpu cannot attach one, and the two query kinds
      // flutter_gpu does not have — each refused by the feature it needs.
      ..checkFeatures(features, backend: impellerBackendName);
    final buffer = gpu.gpuContext.createCommandBuffer();
    final pass = buffer.createRenderPass(_toRenderTarget(descriptor));
    final frame = _openFrame;
    frame.encoding++;
    return GpuCommandEncoder(
      buffer,
      pass,
      this,
      frame,
      depthReadOnly: descriptor.depth?.depthReadOnly ?? false,
      stencilReadOnly: descriptor.depth?.stencilReadOnly ?? false,
    );
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

  /// Called from the encoder's completion callback, through
  /// [GpuRenderBackendInternals.noteRejectedSubmission].
  void _noteRejectedSubmission() => _rejectedSubmissions++;

  @override
  void onFrameComplete(void Function() whenDone) =>
      _openFrame.whenDone.add(whenDone);

  /// The whole of a texture outside `readbackFormats`, converted — what
  /// [readback] answers when `readbackConverts` says so.
  Future<ByteData> _readConverted(TextureHandle texture) {
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
        .whenComplete(image.dispose)
        .then(
          (ByteData? bytes) =>
              bytes ??
              (throw refuseResource(
                'readback',
                'flutter_gpu could not convert a ${texture.format.name} '
                    'texture to RGBA8',
              )),
        );
  }

  /// A copy queued in order and read off a staging texture when the queue
  /// says it ran — see `gpu_readback.dart` for why not `copyTextureToBuffer`.
  /// The whole of a float target is converted through `asImage` instead.
  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) =>
      readbackConverts(texture, region: region)
      ? _readConverted(texture)
      : _readback.read(texture, region);

  late final GpuReadback _readback = GpuReadback(
    onRejectedSubmission: noteRejectedSubmission,
  );

  /// How many staging textures the readbacks have made so far. Diagnostic.
  ///
  /// For the same caller as [GpuRenderBackendInternals.debugTransientRecreations], reading the other half
  /// of the same question: a golden run makes one of these per picture, and a
  /// frame that is not being read back should make none at all.
  int get _debugReadbackStagingCount => _readback.debugStagingCount;

  /// A deliberate no-op. See the note at `supportsCubeTextures` on
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

  /// Drops the `gpu.SamplerOptions` built for [sampler]. The cache is the
  /// backend's, shared by every device in the isolate, so another device's
  /// next bind of the same description builds it again too.
  @override
  void releaseSampler(SamplerDescriptor sampler) => forgetGpuSampler(sampler);

  // ------------------------------------------------- the 1.0 surface

  /// A 2D texture (a 1D one is a row of them, which is all a GLSL ES stage
  /// can sample anyway) or a cube, multisampled or with a chain, in any
  /// format flutter_gpu has. Every other shape is refused by the feature it
  /// needs, before anything is allocated.
  ///
  /// A [RenderTargetDescriptor] is the pool's 2D target, made as it always
  /// was; any other descriptor is the general form, `textureWrites`.
  @override
  TextureHandle createTexture(TextureDescriptor descriptor) {
    if (descriptor is RenderTargetDescriptor) return _createTarget(descriptor);
    features.require(DeviceFeature.textureWrites, backend: impellerBackendName);
    final shape = switch (descriptor.dimension) {
      TextureDimension.d1 || TextureDimension.d2 => null,
      TextureDimension.cube => DeviceFeature.cubeTextures,
      TextureDimension.d2Array => DeviceFeature.textureArrays,
      TextureDimension.d3 => DeviceFeature.texture3D,
      TextureDimension.cubeArray => DeviceFeature.cubeArrayTextures,
    };
    if (shape != null) {
      // TODO(impeller): flutter_gpu's TextureType is texture2D,
      // texture2DMultisample, textureCube and textureExternalOES — array, 3D
      // and cube-array textures are unblocked by upstream TextureType values
      // for them (and a slice count that follows).
      features.require(
        shape,
        backend: impellerBackendName,
        reason: 'flutter_gpu has no ${descriptor.dimension.name} texture type',
      );
    }
    if (descriptor.usage.contains(TextureUsage.storage)) {
      // TODO(impeller): flutter_gpu has `enableShaderWriteUsage` on a texture
      // and no way to bind one as storage — unblocked by a storage-texture
      // binding in its RenderPass (and the compute pass of #188480).
      features.require(
        DeviceFeature.storageTextures,
        backend: impellerBackendName,
        reason: 'flutter_gpu cannot bind a texture as storage',
      );
    }
    final format = descriptor.format;
    if (!format.isMirrored) throw unmirroredFormat(format);
    final width = descriptor.width;
    final height = descriptor.height;
    final layers = descriptor.depthOrArrayLayers;
    final cube = descriptor.dimension == TextureDimension.cube;
    final side = cube
        ? limits.maxTextureDimension2D
        : (descriptor.dimension == TextureDimension.d1
              ? limits.maxTextureDimension1D
              : limits.maxTextureDimension2D);
    if (width > side || height > side) {
      throw ArgumentError(
        'createTexture: ${width}x$height is past this '
        "device's $side",
      );
    }
    if (descriptor.dimension == TextureDimension.d1 && height != 1) {
      throw ArgumentError('a 1D texture is one texel high, not $height');
    }
    if (layers != (cube ? 6 : 1)) {
      throw ArgumentError(
        'a ${descriptor.dimension.name} texture has ${cube ? 6 : 1} '
        '${cube ? "faces" : "layer"}, not $layers',
      );
    }
    if (cube && width != height) {
      throw ArgumentError('a cube face is square, not ${width}x$height');
    }
    final levels = descriptor.mipLevelCount;
    final allowed = gpu.Texture.fullMipCount(width, height);
    if (levels > allowed) {
      // flutter_gpu's own ceiling, which stops one level short of one by
      // one: a chain longer than it is refused here rather than trimmed,
      // because the descriptor promises the levels it names.
      throw ArgumentError(
        'createTexture: $levels levels asked of a '
        '${width}x$height texture; flutter_gpu allocates at most $allowed',
      );
    }
    final samples = descriptor.sampleCount;
    if (samples > 1) {
      features.require(
        DeviceFeature.offscreenMultisample,
        backend: impellerBackendName,
        reason: 'flutter_gpu reports no offscreen MSAA on this context',
      );
      if (samples > limits.maxSampleCount || levels > 1 || cube) {
        throw ArgumentError(
          'a multisampled texture is 2D with one level and at most '
          '${limits.maxSampleCount} samples here',
        );
      }
    }
    final usage = descriptor.usage;
    return createGpuTexture(
      descriptor.storageMode,
      width,
      height,
      format: format,
      sampleCount: samples,
      enableRenderTargetUsage: usage.contains(TextureUsage.renderTarget),
      // `readback` and `readPixels` read through `asImage`, which insists
      // on shader read; a copy source is sampled-in-all-but-name here.
      enableShaderReadUsage:
          descriptor.storageMode != StorageMode.deviceTransient &&
          (usage.contains(TextureUsage.sampled) ||
              usage.contains(TextureUsage.copySource)),
      mipLevelCount: levels,
      type: cube ? TextureType.textureCube : TextureType.texture2D,
      dimension: descriptor.dimension,
      usage: usage,
    );
  }

  /// Through `CommandBuffer.copyBufferToTexture`, which takes any region of
  /// any level of any slice: the bytes go into a staging `DeviceBuffer`,
  /// packed tight a layer at a time where [bytesPerRow] pads them, and one
  /// command buffer copies every layer. Queued, so visible from the next
  /// pass submitted.
  ///
  /// A depth or stencil target is refused: the contract has no aspect to
  /// name, and a combined depth-stencil texture has two.
  @override
  void writeTexture(
    TextureHandle target,
    ByteData data, {
    TextureRegion? region,
    int mipLevel = 0,
    int? bytesPerRow,
  }) {
    features.require(DeviceFeature.textureWrites, backend: impellerBackendName);
    final format = target.format;
    if (!format.isMirrored) throw unmirroredFormat(format);
    if (format.isDepthOrStencil) {
      throw ArgumentError(
        'writeTexture: ${format.name} is a depth or stencil format, and a '
        'write names no aspect of it',
      );
    }
    if (target.sampleCount > 1) {
      throw ArgumentError('writeTexture: a multisampled texture is drawn into');
    }
    final texture = target.gpuTexture;
    if (mipLevel < 0 || mipLevel >= texture.mipLevelCount) {
      throw RangeError.range(
        mipLevel,
        0,
        texture.mipLevelCount - 1,
        'mipLevel',
      );
    }
    final levelWidth = texture.getMipLevelWidth(mipLevel);
    final levelHeight = texture.getMipLevelHeight(mipLevel);
    final box =
        region ??
        TextureRegion(
          width: levelWidth,
          height: levelHeight,
          depthOrArrayLayers: target.sliceCount,
        );
    if (box.x < 0 ||
        box.y < 0 ||
        box.z < 0 ||
        box.width <= 0 ||
        box.height <= 0 ||
        box.depthOrArrayLayers <= 0 ||
        box.x + box.width > levelWidth ||
        box.y + box.height > levelHeight ||
        box.z + box.depthOrArrayLayers > target.sliceCount) {
      throw ArgumentError(
        'writeTexture: $box does not lie inside level $mipLevel '
        '(${levelWidth}x${levelHeight}x${target.sliceCount})',
      );
    }
    final pixel = format.toGpu();
    final blockWidth = pixel.blockWidth;
    final blockHeight = pixel.blockHeight;
    if (box.x % blockWidth != 0 ||
        box.y % blockHeight != 0 ||
        (box.width % blockWidth != 0 && box.x + box.width != levelWidth) ||
        (box.height % blockHeight != 0 && box.y + box.height != levelHeight)) {
      throw ArgumentError(
        'writeTexture: $box is not on ${format.name}\'s '
        '${blockWidth}x$blockHeight block grid',
      );
    }
    final tightRow =
        (box.width + blockWidth - 1) ~/ blockWidth * pixel.bytesPerBlock;
    final rows = (box.height + blockHeight - 1) ~/ blockHeight;
    final stride = bytesPerRow ?? tightRow;
    if (stride < tightRow) {
      throw ArgumentError(
        'writeTexture: bytesPerRow $stride is shorter than a row ($tightRow)',
      );
    }
    final needed = stride * (rows * box.depthOrArrayLayers - 1) + tightRow;
    if (data.lengthInBytes < needed) {
      throw ArgumentError(
        'writeTexture: ${data.lengthInBytes} bytes for $box at $stride bytes '
        'a row; it needs $needed',
      );
    }
    final source = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final layerBytes = tightRow * rows;
    final packed = Uint8List(layerBytes * box.depthOrArrayLayers);
    for (var layer = 0; layer < box.depthOrArrayLayers; layer++) {
      for (var row = 0; row < rows; row++) {
        final from = (layer * rows + row) * stride;
        packed.setRange(
          layer * layerBytes + row * tightRow,
          layer * layerBytes + (row + 1) * tightRow,
          source,
          from,
        );
      }
    }
    final staging = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(packed),
    );
    final buffer = gpu.gpuContext.createCommandBuffer();
    for (var layer = 0; layer < box.depthOrArrayLayers; layer++) {
      buffer.copyBufferToTexture(
        gpu.BufferView(
          staging,
          offsetInBytes: layer * layerBytes,
          lengthInBytes: layerBytes,
        ),
        gpu.TextureRegion(
          texture,
          x: box.x,
          y: box.y,
          width: box.width,
          height: box.height,
          mipLevel: mipLevel,
          slice: box.z + layer,
        ),
      );
    }
    buffer.submit(
      completionCallback: (bool ok) {
        if (!ok) noteRejectedSubmission();
      },
    );
  }

  /// A host-visible `DeviceBuffer` and the host's copy of it — see
  /// `gpu_buffer.dart`. Vertex and index usages hand out the same memory as
  /// [StorageBuffer.asVertices] and [StorageBuffer.asIndices]: a flutter_gpu
  /// buffer is untyped, as [uploadGeometry] says.
  @override
  StorageBuffer createBuffer(
    BufferDescriptor descriptor, {
    ByteData? contents,
  }) {
    features.require(DeviceFeature.buffers, backend: impellerBackendName);
    final usage = descriptor.usage;
    if (usage.contains(BufferUsage.storage)) {
      // TODO(impeller): no storage binding and no compute in flutter_gpu —
      // unblocked by flutter/flutter#188480.
      throw UnsupportedCapability(
        DeviceFeature.renderStageStorage,
        backend: impellerBackendName,
        reason:
            'a storage buffer needs compute or render-stage storage, and '
            'flutter_gpu has neither',
      );
    }
    if (usage.contains(BufferUsage.indirect)) {
      // TODO(impeller): flutter_gpu's RenderPass has no indirect draw —
      // unblocked by an upstream RenderPass.drawIndexedIndirect.
      throw UnsupportedCapability(
        DeviceFeature.indirectDraw,
        backend: impellerBackendName,
        reason: 'flutter_gpu has no indirect draw to read the arguments',
      );
    }
    final length = descriptor.lengthInBytes;
    if (contents != null && contents.lengthInBytes > length) {
      throw ArgumentError(
        'createBuffer: ${contents.lengthInBytes} bytes of contents for a '
        '$length-byte buffer',
      );
    }
    final buffer = GpuBuffer(length);
    if (contents != null) buffer.write(0, contents);
    GeometryBuffer? view(BufferUsage as) => usage.contains(as)
        ? wrapGeometry(
            backend: buffer.device,
            offsetInBytes: 0,
            lengthInBytes: length,
          )
        : null;
    return wrapStorageBuffer(
      owner: this,
      backend: buffer,
      lengthInBytes: length,
      hostReadable: usage.contains(BufferUsage.hostReadable),
      asVertices: view(BufferUsage.vertex),
      asIndices: view(BufferUsage.index),
      usage: usage,
    );
  }

  @override
  void writeBuffer(StorageBuffer target, int offsetInBytes, ByteData bytes) {
    features.require(DeviceFeature.buffers, backend: impellerBackendName);
    final backend = target.backend;
    if (backend is! GpuBuffer) {
      throw ArgumentError('writeBuffer: this buffer was not made here');
    }
    if (!target.usage.contains(BufferUsage.copyDestination)) {
      throw ArgumentError(
        'writeBuffer: this buffer was made without '
        'BufferUsage.copyDestination',
      );
    }
    if (offsetInBytes < 0 ||
        offsetInBytes + bytes.lengthInBytes > target.lengthInBytes) {
      throw ArgumentError(
        'writeBuffer: $offsetInBytes + ${bytes.lengthInBytes} does not fit '
        'inside a ${target.lengthInBytes}-byte buffer',
      );
    }
    backend.write(offsetInBytes, bytes);
  }

  // TODO(impeller): flutter_gpu has no query objects — no occlusion, timer
  // or pipeline-statistics queries — unblocked by an upstream query-set API
  // on its CommandBuffer / RenderPass.
  Never _noQueries(QueryType type) => throw UnsupportedCapability(
    type.feature,
    backend: impellerBackendName,
    reason: 'flutter_gpu has no ${type.name} queries',
  );

  @override
  QuerySet createQuerySet(QueryType type, int count) => _noQueries(type);

  @override
  Future<List<int>> readQueryResults(
    QuerySet querySet, {
    int first = 0,
    int? count,
  }) => _noQueries(querySet.type);

  @override
  void releaseQuerySet(QuerySet querySet) => _noQueries(querySet.type);

  @override
  TransferEncoder beginTransferPass({String? label}) => GpuTransferEncoder(
    features,
    onRejectedSubmission: noteRejectedSubmission,
  );

  /// Refused. The host copy `readBuffer` answers from would serve a read
  /// mapping too, but mapping is a promise about the buffer's own memory, and
  /// flutter_gpu gives no way to reach it.
  // TODO(impeller): a DeviceBuffer has overwrite and flush and no read or map
  // — unblocked by an upstream DeviceBuffer map/read API.
  @override
  Future<MappedBuffer> mapBuffer(
    StorageBuffer buffer,
    MapMode mode, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) => throw UnsupportedCapability(
    DeviceFeature.mappedBuffers,
    backend: impellerBackendName,
    reason: 'a flutter_gpu DeviceBuffer cannot be mapped',
  );

  // TODO(impeller): a DeviceBuffer has no read path, synchronous or not, so
  // this device is not a `SynchronousBufferReadback` — unblocked by the same
  // upstream DeviceBuffer read/map API.

  // TODO(impeller): flutter_gpu has no render bundles, and replaying a
  // recording here would also need every pass setter's state saved and
  // restored around it — unblocked by an upstream bundle API, or by the
  // encoder tracking its whole state.
  @override
  RenderBundleEncoder createRenderBundleEncoder(
    RenderBundleDescriptor descriptor,
  ) => throw UnsupportedCapability(
    DeviceFeature.renderBundles,
    backend: impellerBackendName,
    reason: 'flutter_gpu has no render bundles',
  );

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
              // A cube face is a slice here, in the same +X, −X, +Y, −Y, +Z,
              // −Z order `overwrite` takes one in. flutter_gpu validates both
              // against the texture and throws with the range, which is the
              // loud refusal `ColorTarget.mipLevel` promises on a device
              // whose `supportsRenderToMip` is false.
              slice: color.face,
              mipLevel: color.mipLevel,
            ),
        ],
        depthStencilAttachment: switch (descriptor.depth) {
          null => null,
          // The descriptor's to say, both halves. Its depth defaults — clear on
          // entry, discard on exit — are flutter_gpu's own, so a pass that
          // names neither is the pass it always was. See [DepthTarget].
          //
          // A read-only half keeps what is there — loaded and stored whatever
          // the actions say, as the contract says they are then ignored — and
          // `GpuCommandEncoder` keeps the pass from writing it. What
          // flutter_gpu cannot give is the other half of WebGPU's read-only
          // attachment: sampling the same texture inside the pass stays as
          // undefined here as it is with a writable one.
          // TODO(impeller): flutter_gpu's DepthStencilAttachment has no
          // read-only flag — unblocked by an upstream depthReadOnly /
          // stencilReadOnly on it.
          final DepthTarget depth => gpu.DepthStencilAttachment(
            texture: depth.texture.gpuTexture,
            depthLoadAction: depth.depthReadOnly
                ? gpu.LoadAction.load
                : depth.loadAction.toGpu(),
            depthStoreAction: depth.depthReadOnly
                ? gpu.StoreAction.store
                : depth.storeAction.toGpu(),
            depthClearValue: depth.clearValue,
            stencilLoadAction: depth.stencilReadOnly
                ? gpu.LoadAction.load
                : depth.stencilLoadAction.toGpu(),
            stencilStoreAction: depth.stencilReadOnly
                ? gpu.StoreAction.store
                : depth.stencilStoreAction.toGpu(),
            stencilClearValue: depth.stencilClearValue,
            // Above zero only where `renderToMipLevel` is — `checkFeatures`
            // has refused it already where it is not.
            mipLevel: depth.mipLevel,
            // A cube face is a slice, as for a colour attachment.
            slice: depth.face,
          ),
        },
      );
}

/// What the rest of this backend — the command encoder, a diagnostic — reaches
/// on the device. **Not exported** by `flutter3d_impeller.dart` since 1.0: a
/// `gpu.BufferView` in the public API made flutter_gpu's types part of this
/// package's semver, and the counters are a debugging aid, not a promise.
extension GpuRenderBackendInternals on GpuRenderBackend {
  /// See [GpuRenderBackend._emplace].
  gpu.BufferView emplace(ByteData bytes) => _emplace(bytes);

  /// See [GpuRenderBackend._noteRejectedSubmission].
  void noteRejectedSubmission() => _noteRejectedSubmission();

  /// How many transient allocators had to be rebuilt: for a person reading
  /// the backend in a debugger or a profiling session, not for code.
  int get debugTransientRecreations => _debugTransientRecreations;

  /// How many staging textures the readbacks have made so far: for a person
  /// reading the backend in a debugger or a profiling session, not for code.
  int get debugReadbackStagingCount => _debugReadbackStagingCount;
}
