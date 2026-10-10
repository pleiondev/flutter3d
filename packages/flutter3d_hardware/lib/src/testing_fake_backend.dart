/// A device that records rather than draws, and the shader library it answers
/// every name with.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapability;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'backend_handles.dart';
import 'testing_fake_pass.dart';
import 'testing_recorded.dart';

/// A bundle that has every stage anybody asks for, except the ones it is told
/// to withhold.
///
/// Withholding matters: `ParticleContributor` draws nothing when its stages are
/// missing, and that path had never been exercised.
final class FakeShaderLibrary with ShaderLibrary {
  FakeShaderLibrary({this.missing = const <String>{}, this.stageBindings});

  final Set<String> missing;

  /// Handed to every stage as `ShaderHandle.kept`, the way a real backend
  /// hands the compiled bundle's table — `gfx-92n`.
  final Map<String, StageBindings>? stageBindings;
  final Map<String, ShaderHandle> _handles = <String, ShaderHandle>{};

  @override
  ShaderHandle? operator [](String name) => missing.contains(name)
      ? null
      : _handles.putIfAbsent(
          name,
          () => wrapShader(
            backend: name,
            name: name,
            kept: stageBindings?[name],
            release: (ShaderHandle h) => forgetShader(_handles, h),
          ),
        );
}

/// What [FakeBackend.loadShaders] hands back: the bundle's own names, answered
/// with handles that survive a reload.
///
/// A fake keeps the one promise that matters about a loaded library — a
/// handle already handed out is the same handle after [refresh] — because the
/// renderer holds its vertex stages for its lifetime and a test of the reload
/// path needs a device that behaves the way the three real ones do.
final class FakeLoadedShaderLibrary with ShaderLibrary, LoadedShaderLibrary {
  FakeLoadedShaderLibrary(ShaderBundle bundle) : _bundle = bundle;

  ShaderBundle _bundle;
  final Map<String, ShaderHandle> _handles = <String, ShaderHandle>{};

  /// How many times [refresh] has been called, for a test that wants to know
  /// an editor's watcher fired.
  int refreshes = 0;

  @override
  String get name => _bundle.name;

  /// The stages the last accepted bundle claimed.
  Iterable<String> get names => _bundle.names;

  @override
  ShaderHandle? operator [](String name) => _bundle.names.contains(name)
      ? _handles.putIfAbsent(
          name,
          () => wrapShader(
            backend: name,
            name: name,
            release: (ShaderHandle h) => forgetShader(_handles, h),
          ),
        )
      : null;

  @override
  void refresh(ByteData bytes) {
    final bundle = ShaderBundle.decode(bytes);
    // The other half of the promise, kept the way the real backends keep it:
    // a bundle that dropped a stage somebody holds is refused, naming it.
    final dropped = _handles.keys
        .where((String n) => !bundle.names.contains(n))
        .toList();
    if (dropped.isNotEmpty) {
      throw ShaderBundleException(
        name: bundle.name,
        reason:
            'it no longer has the stage${dropped.length == 1 ? '' : 's'} '
            '${dropped.map((String n) => '"$n"').join(', ')}, which '
            '${dropped.length == 1 ? 'is' : 'are'} already in use',
      );
    }
    _bundle = bundle;
    refreshes++;
  }
}

/// A device that records rather than draws.
///
/// **Its capabilities are a [DeviceFeatures] set like every backend's**, built
/// from the constructor's flags. The 0.9 surface is off unless a test
/// names it in `extraFeatures`; a feature named there is *recorded* — each
/// call becomes a [RecordedCall] in the pass or in [calls] — and a feature
/// not named is refused with [UnsupportedCapability], exactly as a real
/// backend without it refuses. Compute is never available: a fake runs no
/// stage, and `extraFeatures` may not name it.
final class FakeBackend extends GraphicsDevice with SynchronousBufferReadback {
  // The 0.8 cycle's half of the contract, declared in 0.8.0 and not built
  // here yet — see the end of `GraphicsDevice`. Each answer is the one that
  // makes a caller take its fallback.

  @override
  void onGpuTimings(void Function(GpuFrameTimings timings)? listener) {}

  @override
  StorageBuffer createStorageBuffer(
    ByteData bytes, {
    bool hostReadable = false,
    bool bindableAsIndices = false,
  }) => throw _noCompute();

  @override
  ComputePipelineHandle createComputePipeline(ShaderHandle shader) =>
      throw _noCompute();

  @override
  ComputeEncoder beginComputePass({
    String? label,
    PassTimestampWrites? timestampWrites,
  }) => throw _noCompute();

  /// Zeros of the buffer's length: a fake keeps no bytes. Refused for a
  /// buffer that was not made host-readable, as every backend refuses it.
  @override
  Future<ByteData> readBuffer(StorageBuffer buffer) async {
    features.require(DeviceFeature.buffers, backend: _name);
    if (!buffer.hostReadable) {
      throw ArgumentError.value(buffer, 'buffer', 'is not hostReadable');
    }
    return ByteData(buffer.lengthInBytes);
  }

  @override
  void releaseStorageBuffer(StorageBuffer buffer) =>
      calls.add(RecordedCall('releaseStorageBuffer', buffer));

  static UnsupportedCapability _noCompute() => UnsupportedCapability(
    DeviceFeature.compute,
    backend: _name,
    reason: 'a fake runs no compute stage',
  );

  @override
  Future<MappedBuffer> mapBuffer(
    StorageBuffer buffer,
    MapMode mode, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) async {
    features.require(DeviceFeature.mappedBuffers, backend: _name);
    final size = sizeInBytes ?? buffer.lengthInBytes - offsetInBytes;
    calls.add(
      RecordedCall('mapBuffer', (
        mode: mode,
        offsetInBytes: offsetInBytes,
        sizeInBytes: size,
      )),
    );
    return FakeMapping(ByteData(size));
  }

  @override
  ByteData readBufferSync(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    features.require(DeviceFeature.synchronousReadback, backend: _name);
    return ByteData(sizeInBytes ?? buffer.lengthInBytes - offsetInBytes);
  }

  @override
  RenderBundleEncoder createRenderBundleEncoder(
    RenderBundleDescriptor descriptor,
  ) {
    features.require(DeviceFeature.renderBundles, backend: _name);
    return FakePass.bundle(descriptor, features: features);
  }

  @override
  List<TextureFormat> get hdrOutputFormats => const <TextureFormat>[];

  /// [maxAnisotropy] and [maxColorAttachments] become [limits]; the flags and
  /// [extraFeatures] become [features]. See the class doc for what a feature
  /// named in [extraFeatures] does on a fake.
  FakeBackend({
    Set<String> missingShaders = const <String>{},
    bool supportsWireframe = true,
    bool supportsAlphaToCoverage = true,
    bool supportsStencil = true,
    bool supportsRenderToMip = true,
    this.unsupportedFormats = const <TextureFormat>{},
    int maxAnisotropy = 16,
    int maxColorAttachments = 2,
    this.stageBindings,
    this.framebufferOrigin = FramebufferOrigin.topLeft,
    Iterable<DeviceFeature> extraFeatures = const <DeviceFeature>[],
  }) : assert(
         !extraFeatures.contains(DeviceFeature.compute),
         'a fake runs no compute stage, so it cannot report compute',
       ),
       shaders = FakeShaderLibrary(
         missing: missingShaders,
         stageBindings: stageBindings,
       ),
       limits = DeviceLimits(
         maxSamplerAnisotropy: maxAnisotropy,
         maxColorAttachments: maxColorAttachments,
         maxComputeWorkgroupStorageSize: 0,
         maxComputeInvocationsPerWorkgroup: 0,
         maxComputeWorkgroupSizeX: 0,
         maxComputeWorkgroupSizeY: 0,
         maxComputeWorkgroupSizeZ: 0,
         maxComputeWorkgroupsPerDimension: 0,
       ),
       _features = DeviceFeatures(<DeviceFeature>{
         DeviceFeature.offscreenMultisample,
         // Recorded, not evaluated: this device blends nothing, so the honest
         // answer is the one that lets a caller under test set the constant
         // and be recorded doing it.
         DeviceFeature.blendConstant,
         // True, because a fake has nothing to be incapable with. The real
         // answer is a device property, and the backends disagree.
         DeviceFeature.manualMipmaps,
         DeviceFeature.cubeTextures,
         // Settable for the same reason as wireframe: the interesting case
         // is the backend that says no — flutter_gpu on OpenGL ES — and the
         // renderer is supposed to build a probe without a chain there.
         if (supportsRenderToMip) DeviceFeature.renderToMipLevel,
         // Settable, because the interesting case is the backend that says
         // no — OpenGL ES has no `glPolygonMode`, and the engine is supposed
         // to decline its own wireframe setting rather than let the request
         // reach a backend that would refuse it mid-frame.
         if (supportsWireframe) DeviceFeature.wireframe,
         // Settable: two of the four real backends say no, and the engine is
         // meant to draw the hard alpha test there and report it.
         if (supportsAlphaToCoverage) DeviceFeature.alphaToCoverage,
         // Settable: the case worth a test is the device that says no, where
         // the x-ray stage has to draw nothing rather than configure a test
         // against an attachment with no stencil in it.
         if (supportsStencil) DeviceFeature.stencil,
         ...extraFeatures,
       });

  /// What this fake reports. Mutable only through [supportsOffscreenMsaa]'s
  /// setter, the one capability tests flip after construction.
  DeviceFeatures _features;

  @override
  DeviceFeatures get features => _features;

  /// Sixteen taps and two attachments unless the constructor said otherwise
  /// — `gfx-50n`. **Two is a parameter because the device it stands in for
  /// cannot be asked**: Impeller on OpenGL ES aborts rather than refusing, so
  /// there is no way to run the no-MRT path on the hardware that has it.
  /// This fake answers what a pass was *opened* with; `CpuDevice`, which
  /// takes the same number, answers what came out the other end as pixels.
  @override
  final DeviceLimits limits;

  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) =>
      unsupportedFormats.contains(format)
      ? TextureFormatSupport.none
      : const TextureFormatSupport(
          sampled: true,
          filterable: true,
          renderable: true,
          blendable: true,
          multisample: true,
          resolve: true,
          depthStencil: true,
        );

  /// The backend name a refusal from this fake carries.
  static const String _name = 'FakeBackend';

  /// Every device-level 0.9 call, in order, for a test that wants to know a
  /// buffer was written or a copy recorded. Pass-level calls go into the
  /// pass's own `commands`.
  final List<RecordedCall> calls = <RecordedCall>[];

  /// True, and settable so a test can be the device that answers no —
  /// `gfx-20n`.
  ///
  /// The reason it is worth setting: a frame that stops multisampling because
  /// the device cannot and a frame that stops because something reads the
  /// surface buffer look identical from outside, and
  /// `FrameResult.antiAliasing` exists to tell them apart. A fake that could
  /// only say yes leaves half of that untested.
  set supportsOffscreenMsaa(bool supported) => _features = supported
      ? _features.union(const <DeviceFeature>[
          DeviceFeature.offscreenMultisample,
        ])
      : _features.without(const <DeviceFeature>[
          DeviceFeature.offscreenMultisample,
        ]);

  @override
  TextureHandle createTexture(TextureDescriptor descriptor) {
    if (descriptor is RenderTargetDescriptor) return _createTarget(descriptor);
    features.require(DeviceFeature.textureWrites, backend: _name);
    final shape = switch (descriptor.dimension) {
      TextureDimension.d2Array => DeviceFeature.textureArrays,
      TextureDimension.d3 => DeviceFeature.texture3D,
      TextureDimension.cube => DeviceFeature.cubeTextures,
      TextureDimension.cubeArray => DeviceFeature.cubeArrayTextures,
      TextureDimension.d1 || TextureDimension.d2 => null,
    };
    if (shape != null) features.require(shape, backend: _name);
    if (descriptor.usage.contains(TextureUsage.storage)) {
      features.require(DeviceFeature.storageTextures, backend: _name);
    }
    calls.add(RecordedCall('createTexture', descriptor));
    return wrapTexture(
      owner: this,
      backend: 'fake ${_serial++}',
      width: descriptor.width,
      height: descriptor.height,
      format: descriptor.format,
      sampleCount: descriptor.sampleCount,
      storageMode: descriptor.storageMode,
      type: descriptor.dimension == TextureDimension.cube
          ? TextureType.textureCube
          : TextureType.texture2D,
      dimension: descriptor.dimension,
      depthOrArrayLayers: descriptor.depthOrArrayLayers,
      mipLevelCount: descriptor.mipLevelCount,
      usage: descriptor.usage,
    );
  }

  @override
  void writeTexture(
    TextureHandle target,
    ByteData data, {
    TextureRegion? region,
    int mipLevel = 0,
    int? bytesPerRow,
  }) {
    features.require(DeviceFeature.textureWrites, backend: _name);
    calls.add(
      RecordedCall('writeTexture', (
        target: target,
        bytes: data.lengthInBytes,
        region: region,
        mipLevel: mipLevel,
      )),
    );
  }

  @override
  StorageBuffer createBuffer(
    BufferDescriptor descriptor, {
    ByteData? contents,
  }) {
    features.require(DeviceFeature.buffers, backend: _name);
    if (descriptor.usage.contains(BufferUsage.storage)) {
      features.require(DeviceFeature.renderStageStorage, backend: _name);
    }
    calls.add(RecordedCall('createBuffer', descriptor));
    final serial = _serial++;
    GeometryBuffer? view(BufferUsage usage) => descriptor.usage.contains(usage)
        ? wrapGeometry(
            backend: 'fake buffer $serial',
            offsetInBytes: 0,
            lengthInBytes: descriptor.lengthInBytes,
          )
        : null;
    return wrapStorageBuffer(
      owner: this,
      backend: 'fake buffer $serial',
      lengthInBytes: descriptor.lengthInBytes,
      hostReadable: descriptor.usage.contains(BufferUsage.hostReadable),
      asIndices: view(BufferUsage.index),
      asVertices: view(BufferUsage.vertex),
      usage: descriptor.usage,
    );
  }

  @override
  void writeBuffer(StorageBuffer target, int offsetInBytes, ByteData bytes) {
    features.require(DeviceFeature.buffers, backend: _name);
    if (offsetInBytes < 0 ||
        offsetInBytes + bytes.lengthInBytes > target.lengthInBytes) {
      throw ArgumentError(
        'writeBuffer: $offsetInBytes + ${bytes.lengthInBytes} does not fit '
        'inside a ${target.lengthInBytes}-byte buffer',
      );
    }
    calls.add(
      RecordedCall('writeBuffer', (
        offsetInBytes: offsetInBytes,
        lengthInBytes: bytes.lengthInBytes,
      )),
    );
  }

  @override
  QuerySet createQuerySet(QueryType type, int count) {
    features.require(type.feature, backend: _name);
    calls.add(RecordedCall('createQuerySet', (type: type, count: count)));
    return wrapQuerySet(
      owner: this,
      backend: 'fake queries ${_serial++}',
      type: type,
      count: count,
    );
  }

  /// Zeros: nothing was drawn, so nothing passed and no time went by.
  @override
  Future<List<int>> readQueryResults(
    QuerySet querySet, {
    int first = 0,
    int? count,
  }) async => List<int>.filled(count ?? querySet.count - first, 0);

  @override
  void releaseQuerySet(QuerySet querySet) =>
      calls.add(RecordedCall('releaseQuerySet', querySet));

  @override
  TransferEncoder beginTransferPass({String? label}) =>
      FakeTransfer(features, calls);

  /// What each stage declares, by name, or null to accept every bind.
  ///
  /// Given it, every pass this device opens holds binds to the contract and
  /// writes each declared slot a draw left unbound to [bindingViolations]. The
  /// engine's own map is compiled from the real bundle: `stageBindings` in
  /// `flutter3d_shaders`. This is what lets a missing or misdirected bind fail
  /// on the VM instead of on the one backend that happens to crash on it.
  final Map<String, StageBindings>? stageBindings;

  /// Declared slots left unbound at a draw, across every pass. See
  /// [stageBindings].
  final List<String> bindingViolations = <String>[];

  @override
  final FakeShaderLibrary shaders;

  /// The formats this fake says it cannot sample, so a test can be the
  /// device that has no BC7 and see what a loader does about it.
  final Set<TextureFormat> unsupportedFormats;

  /// Every library [loadShaders] has handed out, in order, so a test can
  /// reach the one an application holds and count its refreshes.
  final List<FakeLoadedShaderLibrary> loadedLibraries =
      <FakeLoadedShaderLibrary>[];

  /// Decodes the bundle — so bytes that are not one are refused the way every
  /// real backend refuses them — and answers its names. No section is read:
  /// a fake compiles nothing, which is also the software rasteriser's answer.
  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) async {
    final library = FakeLoadedShaderLibrary(ShaderBundle.decode(bytes));
    loadedLibraries.add(library);
    return library;
  }

  /// Every cube a pass may draw into, with the level count it was asked for,
  /// so a test can see that a probe allocated what it meant to.
  final List<({int size, TextureFormat format, int mipLevels})>
  createdCubeRenderTargets =
      <({int size, TextureFormat format, int mipLevels})>[];

  @override
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) {
    createdCubeRenderTargets.add((
      size: size,
      format: format,
      mipLevels: mipLevels,
    ));
    return wrapTexture(
      owner: this,
      backend: 'fake cube ${_serial++}',
      width: size,
      height: size,
      format: format,
      type: TextureType.textureCube,
    );
  }

  @override
  TextureHandle createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    // Recorded by no fake and refused by none: this backend answers the shape
    // of a call, not the contents of a texture.
    List<List<ByteData>>? mipLevels,
  }) => faces.length == 6
      ? wrapTexture(
          owner: this,
          backend: const Object(),
          width: size,
          height: size,
          format: format,
          type: TextureType.textureCube,
        )
      : throw refuseResource(
          'createCubeTextureFromPixels',
          'a cube has six faces and ${faces.length} were given',
        );

  /// The engine's own convention by default, so a fake never exercises the
  /// remap. The backends that need the other one are covered by running
  /// them; a test that pins what the engine hands such a backend asks for
  /// [FramebufferOrigin.bottomLeft].
  @override
  final FramebufferOrigin framebufferOrigin;

  @override
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  @override
  int get preferredSampleCount => 4;

  /// Every pass ever opened, in the order it was opened.
  final List<FakePass> passes = <FakePass>[];

  final List<RenderTargetDescriptor> createdTextures =
      <RenderTargetDescriptor>[];

  int frames = 0;
  int _serial = 0;

  @override
  TextureFormat get defaultColorFormat => TextureFormat.b8g8r8a8UNormInt;

  @override
  TextureFormat get defaultDepthStencilFormat => TextureFormat.d24UnormS8Uint;

  TextureHandle _createTarget(RenderTargetDescriptor spec) {
    createdTextures.add(spec);
    return wrapTexture(
      owner: this,
      backend: 'fake ${_serial++}',
      width: spec.width,
      height: spec.height,
      format: spec.format,
      sampleCount: spec.sampleCount,
      storageMode: spec.storageMode,
    );
  }

  /// Frames whose work the GPU has not "finished".
  ///
  /// Held rather than run, so a test can decide when a frame is over — which is
  /// the whole question the renderer's finished-frame textures turn on.
  final List<void Function()> pendingFrames = <void Function()>[];

  /// Whether [onFrameComplete] runs its callback at once.
  ///
  /// True by default, so every test that does not care about this sees a
  /// backend that finishes as it goes.
  bool completesImmediately = true;

  @override
  void onFrameComplete(void Function() whenDone) {
    if (completesImmediately) {
      whenDone();
      return;
    }
    pendingFrames.add(whenDone);
  }

  /// Lets the oldest unfinished frame complete.
  void finishOldestFrame() {
    if (pendingFrames.isEmpty) return;
    pendingFrames.removeAt(0)();
  }

  /// Pixel uploads, in order, so a test can assert what reached the device.
  final List<RenderTargetDescriptor> uploadedTextures =
      <RenderTargetDescriptor>[];

  /// The bytes of each of those, for a test that cares what colour it was.
  final List<ByteData> uploadedPixels = <ByteData>[];

  /// The chain each of those came with — null for an upload that brought
  /// none — so a test can tell a base level from a base level and its mips.
  final List<List<ByteData>?> uploadedMipLevels = <List<ByteData>?>[];

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    final spec = RenderTargetDescriptor(
      width: width,
      height: height,
      format: format,
      storageMode: StorageMode.hostVisible,
    );
    uploadedTextures.add(spec);
    uploadedPixels.add(pixels);
    uploadedMipLevels.add(mipLevels);
    return createTexture(spec);
  }

  /// Every call [overwriteTexture] has recorded, in order — wiring, not
  /// content, the same promise [uploadedPixels] already makes for a whole
  /// upload.
  final List<({TextureFormat format, ScreenRect region, int mipLevel})>
  overwrittenTextures =
      <({TextureFormat format, ScreenRect region, int mipLevel})>[];

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
    overwrittenTextures.add((
      format: target.format,
      region: rect,
      mipLevel: mipLevel,
    ));
  }

  /// Every pair linked so far, by name and in order, so a test can tell
  /// whether a frame linked anything — a renderer that relinked drops every
  /// pipeline it held and links each one again, and one it forgot to drop
  /// shows up here as a link that did not happen.
  final List<String> linkedPipelines = <String>[];

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) {
    final name = '${vertex.name}+${fragment.name}';
    linkedPipelines.add(name);
    return wrapPipeline(owner: this, backend: name, name: name);
  }

  /// Recorded with its usage, because a backend exists that cannot change its
  /// mind about one later.
  final List<GeometryUsage> uploads = <GeometryUsage>[];

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    uploads.add(usage);
    return _geometry(bytes, release: releaseGeometry);
  }

  GeometryBuffer _geometry(
    ByteData bytes, {
    void Function(GeometryBuffer)? release,
  }) => wrapGeometry(
    backend: 'uploaded ${_serial++}',
    offsetInBytes: 0,
    lengthInBytes: bytes.lengthInBytes,
    release: release,
  );

  /// Every call [overwriteGeometry] has recorded, in order — a test asks this
  /// rather than the bytes themselves, because this backend keeps none: it
  /// records wiring, not content, the same promise [uploads] already makes.
  final List<({Object backend, int offsetInBytes, int lengthInBytes})>
  overwrites = <({Object backend, int offsetInBytes, int lengthInBytes})>[];

  @override
  void overwriteGeometry(
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
    overwrites.add((
      backend: target.backend,
      offsetInBytes: target.offsetInBytes + offsetInBytes,
      lengthInBytes: bytes.lengthInBytes,
    ));
  }

  @override
  void beginFrame() => frames++;

  /// Every readback asked for, in order: which texture and which region.
  ///
  /// Recorded because the thing worth testing about a readback off a device is
  /// that it was asked for at all, of the right texture, for the right pixel —
  /// what comes back is the backend's business, and this one has no pixels.
  final List<({TextureHandle texture, ScreenRect region})> readbacks =
      <({TextureHandle texture, ScreenRect region})>[];

  /// What a readback answers, or null for a region of zeros.
  ///
  /// A test that wants the renderer to *act* on a readback — an exposure that
  /// climbs, a pick that finds something — sets this to hand back the bytes
  /// the pass would have produced.
  ByteData Function(TextureHandle texture, ScreenRect region)? answerReadback;

  /// Refuses what the contract refuses, records the rest, and answers zeros
  /// unless [answerReadback] says otherwise. A whole texture outside
  /// [readbackFormats] is "converted" to zeros of its size, and recorded as a
  /// readback of all of it.
  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) {
    final resolved = readbackConverts(texture, region: region)
        ? ScreenRect.of(texture)
        : readbackRegionOf(texture, region);
    readbacks.add((texture: texture, region: resolved));
    final answer = answerReadback;
    return Future<ByteData>.value(
      answer == null
          ? ByteData(resolved.width * resolved.height * 4)
          : answer(texture, resolved),
    );
  }

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    // `gfx-50n`. The fake refuses what a real device would refuse, because a
    // fake that accepted more would let a test record a pass no backend could
    // open — and a test that passes on a device nobody has is worse than no
    // test.
    descriptor
      ..checkAttachmentLimit(
        limits.maxColorAttachments,
        backend: 'this fake device',
      )
      ..checkFeatures(features, backend: _name);
    final pass = FakePass(
      descriptor,
      stageBindings: stageBindings,
      violations: bindingViolations,
      features: features,
    );
    passes.add(pass);
    return pass;
  }

  /// Whether [dispose] has been called, for a test that wants to assert a
  /// device was actually torn down rather than merely dropped.
  bool get isDisposed => _isDisposed;
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_lost.close());
  }

  /// Loses the device as a backend would, for a test of whoever listens to
  /// [lost]: [isLost] becomes true unless [loss] is the `restored` event that
  /// ends a recoverable loss, and [loss] goes out on [lost].
  void lose(DeviceLoss loss) {
    _isLost = !loss.restored;
    _lost.add(loss);
  }

  final StreamController<DeviceLoss> _lost =
      StreamController<DeviceLoss>.broadcast();
  bool _isLost = false;

  @override
  Stream<DeviceLoss> get lost => _lost.stream;

  @override
  bool get isLost => _isLost;

  /// What was handed back one at a time, in the order it was handed back.
  ///
  /// Recorded rather than ignored because the thing worth testing about a
  /// release is that it happened at all: the leak this contract exists for is
  /// a caller that reallocates and never calls it, which is invisible to a
  /// backend whose own release is a no-op.
  final List<TextureHandle> releasedTextures = <TextureHandle>[];
  final List<GeometryBuffer> releasedGeometry = <GeometryBuffer>[];

  @override
  void releaseTexture(TextureHandle texture) => releasedTextures.add(texture);

  @override
  void releaseGeometry(GeometryBuffer geometry) =>
      releasedGeometry.add(geometry);
}
