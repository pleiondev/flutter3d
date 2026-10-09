/// What a device can do, as one typed answer instead of a getter per question.
///
/// **Why this replaced the `supportsX` getters.** Fifteen booleans and three
/// numbers had grown on `GraphicsDevice` one capability at a time, each added
/// when a caller first needed to ask, and each a new member every backend had
/// to implement. A capability the interface had not thought of yet had no
/// place to be reported at all, so a backend that *could* do something had no
/// way to say so, and a caller had no way to find out short of trying. A
/// [DeviceFeatures] set is open: a feature added in a later release is a new
/// constant, every backend that does not list it answers false without being
/// touched, and a caller asks one question in one shape.
///
/// The reference model is WebGPU's — features and limits, named the way its
/// specification names them where it has a name — because it is the portable
/// intersection of Metal, Vulkan and Direct3D 12 that somebody else has already
/// argued over. Where this engine needs a word WebGPU does not have (a backend
/// that cannot attach a mip level, a context with no stencil), the feature is
/// the engine's own and says so.
///
/// **An unsupported feature is a refusal, never a substitution.** Every call a
/// feature gates throws [UnsupportedCapability] — a [CapabilityException]
/// that names the feature and the backend — on a device that does not list
/// it. The
/// conformance check `every capability a device reports is honest` holds both
/// directions: a listed feature must work, an unlisted one must refuse.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show CapabilityException;
import 'package:meta/meta.dart';

import 'formats.dart';

/// Whether a [DeviceFeature] has calls behind it yet.
enum FeatureStability {
  /// Part of the 1.0 contract: its calls exist, are promised under semver,
  /// and change only with a major version. A backend that lacks it refuses
  /// them with [UnsupportedCapability] — which is a complete answer, and the
  /// one a later backend release turns into "yes" without the API moving.
  stable,

  /// Named so that nothing else takes the name, and implemented nowhere. No
  /// backend may report one — [DeviceFeatures] refuses it — and no call exists
  /// for it yet. Giving one its calls is additive: a minor release adds the
  /// calls and turns it [stable], and every backend that does not list it is
  /// unaffected.
  reserved,
}

/// One optional capability of a device.
///
/// **A final class with const instances, not an enum**, so that a capability
/// added later is not a breaking change to every `switch` written against the
/// list — the same shape `LightingModel` has, and for the same reason. Compare
/// by identity or by [name]; both are stable.
@immutable
final class DeviceFeature {
  const DeviceFeature._(this.name, this.stability);

  /// The stable identifier: WebGPU's spelling where WebGPU has the feature,
  /// the engine's own otherwise. Used in reports, snapshots and refusals.
  final String name;

  /// Whether its calls are promised, still moving, or not built anywhere.
  final FeatureStability stability;

  // ---------------------------------------------------------------- stable
  // The capabilities the `supportsX` getters asked about before 0.9, each
  // under the name it is reported by now. Their getters forward here.

  /// A multisampled offscreen target can be allocated and resolved. Was
  /// `supportsOffscreenMsaa`.
  static const offscreenMultisample = DeviceFeature._(
    'offscreen-multisample',
    FeatureStability.stable,
  );

  /// `PassEncoder.setBlendColor` reaches the hardware, and the four
  /// constant-reading `BlendFactor`s may be named. Was `supportsBlendColor`.
  static const blendConstant = DeviceFeature._(
    'blend-constant',
    FeatureStability.stable,
  );

  /// A texture with a hand-supplied mip chain samples correctly. Was
  /// `supportsMipmaps`.
  static const manualMipmaps = DeviceFeature._(
    'manual-mipmaps',
    FeatureStability.stable,
  );

  /// Cube textures can be created, sampled and drawn into face by face. Was
  /// `supportsCubeTextures`.
  static const cubeTextures = DeviceFeature._(
    'cube-textures',
    FeatureStability.stable,
  );

  /// A pass can draw into a mip level below the base. Was
  /// `supportsRenderToMip`.
  static const renderToMipLevel = DeviceFeature._(
    'render-to-mip-level',
    FeatureStability.stable,
  );

  /// `PolygonMode.line` draws edges. Was `supportsWireframe`.
  static const wireframe = DeviceFeature._(
    'wireframe',
    FeatureStability.stable,
  );

  /// `PassEncoder.setAlphaToCoverage` spreads alpha over a multisampled
  /// pixel's samples. Was `supportsAlphaToCoverage`.
  static const alphaToCoverage = DeviceFeature._(
    'alpha-to-coverage',
    FeatureStability.stable,
  );

  /// The depth attachment carries a stencil `PassEncoder.setStencil` tests
  /// against. Was `supportsStencil`.
  static const stencil = DeviceFeature._('stencil', FeatureStability.stable);

  /// Each labelled pass is timed on the GPU and reported through
  /// `GraphicsDevice.onGpuTimings`. Was `supportsGpuTimestamps`. Explicit
  /// query sets are [timestampQuery].
  static const gpuTimestamps = DeviceFeature._(
    'gpu-timestamps',
    FeatureStability.stable,
  );

  /// Compute pipelines, storage buffers, compute passes and buffer readback.
  /// Was `supportsCompute`.
  static const compute = DeviceFeature._('compute', FeatureStability.stable);

  /// A 32-bit float texture samples with linear filtering. WebGPU's
  /// `float32-filterable`. Half of what `supportsFloat32Filtering` asked.
  static const float32Filterable = DeviceFeature._(
    'float32-filterable',
    FeatureStability.stable,
  );

  /// A 32-bit float texture can be a colour attachment. The other half of
  /// what `supportsFloat32Filtering` asked — that getter answers true only
  /// when a device has both.
  static const float32Renderable = DeviceFeature._(
    'float32-renderable',
    FeatureStability.stable,
  );

  /// Each colour attachment of a pass blends with its own state. Was
  /// `supportsIndependentBlend`.
  static const independentBlend = DeviceFeature._(
    'independent-blend',
    FeatureStability.stable,
  );

  // ------------------------------------------------------------- since 1.0
  // What WebGPU and WebGL2 can do between them and the contract could not
  // express before 1.0. Every one has its calls; a backend lacking one
  // refuses them by name.

  /// `TextureDimension.d2Array` textures: created, sampled, written.
  static const textureArrays = DeviceFeature._(
    '2d-array-textures',
    FeatureStability.stable,
  );

  /// `TextureDimension.d3` textures: created, sampled, written.
  static const texture3D = DeviceFeature._(
    '3d-textures',
    FeatureStability.stable,
  );

  /// `TextureDimension.cubeArray` textures. Optional in WebGL2 (absent),
  /// core in WebGPU.
  static const cubeArrayTextures = DeviceFeature._(
    'cube-array-textures',
    FeatureStability.stable,
  );

  /// A pass can draw into one layer of an array texture or one slice of a 3D
  /// texture — `ColorTarget.layer` above zero.
  static const renderToArrayLayer = DeviceFeature._(
    'render-to-array-layer',
    FeatureStability.stable,
  );

  /// `GraphicsDevice.createTexture` and
  /// `GraphicsDevice.writeTexture`: any format, level and layer, not only the
  /// RGBA8 base level `overwriteTexture` takes. Colour formats: a depth or
  /// stencil texture is filled by a pass, and `writeTexture` refuses one
  /// with an [ArgumentError], as WebGPU does.
  static const textureWrites = DeviceFeature._(
    'texture-writes',
    FeatureStability.stable,
  );

  /// `GraphicsDevice.createBuffer` and `GraphicsDevice.writeBuffer` for the
  /// buffer usages that are not storage — vertex, index, uniform, copy, map.
  /// Storage usage additionally needs [compute] or [renderStageStorage].
  /// `GraphicsDevice.readBuffer` of a buffer made here with
  /// `BufferUsage.hostReadable` belongs to this feature too, so a device
  /// with buffers and no compute can still read one back.
  static const buffers = DeviceFeature._('buffers', FeatureStability.stable);

  /// `TransferEncoder.copyBufferToBuffer` and `TransferEncoder.clearBuffer`.
  static const bufferCopy = DeviceFeature._(
    'buffer-copy',
    FeatureStability.stable,
  );

  /// `TransferEncoder.copyTextureToTexture`.
  static const textureCopy = DeviceFeature._(
    'texture-copy',
    FeatureStability.stable,
  );

  /// `TransferEncoder.copyBufferToTexture` and
  /// `TransferEncoder.copyTextureToBuffer`.
  static const bufferTextureCopy = DeviceFeature._(
    'buffer-texture-copy',
    FeatureStability.stable,
  );

  /// A compute stage writes (or only reads) a texture —
  /// `ComputeEncoder.bindStorageTexture` with `StorageTextureAccess.writeOnly`
  /// or `readOnly`, in a format whose `TextureFormatSupport.storage` is true.
  static const storageTextures = DeviceFeature._(
    'storage-textures',
    FeatureStability.stable,
  );

  /// `StorageTextureAccess.readWrite`, in a format whose
  /// `TextureFormatSupport.storageReadWrite` is true.
  static const readWriteStorageTextures = DeviceFeature._(
    'read-write-storage-textures',
    FeatureStability.stable,
  );

  /// Storage buffers and storage textures bound to a render pipeline's
  /// stages — `PassEncoder.bindStorageBuffer` and
  /// `PassEncoder.bindStorageTexture`.
  static const renderStageStorage = DeviceFeature._(
    'render-stage-storage',
    FeatureStability.stable,
  );

  /// `PassEncoder.drawIndirect`: an indexed draw whose counts a buffer holds,
  /// written by a compute pass and never read back.
  static const indirectDraw = DeviceFeature._(
    'indirect-draw',
    FeatureStability.stable,
  );

  /// `ComputeEncoder.dispatchIndirect`: a dispatch whose grid a buffer holds.
  static const indirectDispatch = DeviceFeature._(
    'indirect-dispatch',
    FeatureStability.stable,
  );

  /// An indirect draw honours a non-zero first instance. WebGPU's
  /// `indirect-first-instance`.
  static const indirectFirstInstance = DeviceFeature._(
    'indirect-first-instance',
    FeatureStability.stable,
  );

  /// `PassEncoder.drawNonIndexed`: vertices drawn in order, no index buffer.
  static const nonIndexedDraw = DeviceFeature._(
    'non-indexed-draw',
    FeatureStability.stable,
  );

  /// `PassEncoder.setDepthBias`: constant and slope-scaled depth offset.
  static const depthBias = DeviceFeature._(
    'depth-bias',
    FeatureStability.stable,
  );

  /// `PassEncoder.setColorWriteMask`: channels a draw leaves alone.
  static const colorWriteMask = DeviceFeature._(
    'color-write-mask',
    FeatureStability.stable,
  );

  /// `PassEncoder.setDepthClamp`: depth clamped to the range instead of
  /// clipped. WebGPU's `depth-clip-control` (`unclippedDepth`).
  static const depthClamp = DeviceFeature._(
    'depth-clip-control',
    FeatureStability.stable,
  );

  /// `BlendOperation.min` and `BlendOperation.max`.
  static const minMaxBlend = DeviceFeature._(
    'min-max-blend',
    FeatureStability.stable,
  );

  /// The four `BlendFactor`s that read a fragment's second output. WebGPU's
  /// `dual-source-blending`.
  static const dualSourceBlending = DeviceFeature._(
    'dual-source-blending',
    FeatureStability.stable,
  );

  /// `SamplerDescriptor.compare`: a sampler that answers a depth comparison.
  static const samplerCompare = DeviceFeature._(
    'sampler-compare',
    FeatureStability.stable,
  );

  /// `SamplerDescriptor.lodMinClamp` and `SamplerDescriptor.lodMaxClamp`.
  static const samplerLodClamp = DeviceFeature._(
    'sampler-lod-clamp',
    FeatureStability.stable,
  );

  /// `SamplerDescriptor.borderColor`: clamp to a border colour. Not in WebGPU
  /// or WebGL2; Metal and Vulkan have it.
  static const samplerBorderColor = DeviceFeature._(
    'sampler-border-color',
    FeatureStability.stable,
  );

  /// Occlusion query sets — `QueryType.occlusion`,
  /// `PassEncoder.beginOcclusionQuery`.
  static const occlusionQuery = DeviceFeature._(
    'occlusion-query',
    FeatureStability.stable,
  );

  /// Timestamp query sets — `QueryType.timestamp`, `PassTimestampWrites`.
  /// WebGPU's `timestamp-query`.
  static const timestampQuery = DeviceFeature._(
    'timestamp-query',
    FeatureStability.stable,
  );

  /// Every BC format `TextureFormat` names samples on this device — BC1, BC3,
  /// BC5 and BC7, with their sRGB variants — which is what WebGPU's
  /// `texture-compression-bc` means. A device with only part of the family
  /// (WebGL2 with BPTC alone) does not report this, and says per format
  /// through `textureFormatSupport`.
  static const textureCompressionBC = DeviceFeature._(
    'texture-compression-bc',
    FeatureStability.stable,
  );

  /// ETC2 samples on this device. WebGPU's `texture-compression-etc2`.
  static const textureCompressionETC2 = DeviceFeature._(
    'texture-compression-etc2',
    FeatureStability.stable,
  );

  /// ASTC LDR samples on this device. WebGPU's `texture-compression-astc`.
  static const textureCompressionASTC = DeviceFeature._(
    'texture-compression-astc',
    FeatureStability.stable,
  );

  /// ASTC HDR samples on this device.
  static const textureCompressionASTCHdr = DeviceFeature._(
    'texture-compression-astc-hdr',
    FeatureStability.stable,
  );

  /// A 32-bit float attachment blends. WebGPU's `float32-blendable`.
  static const float32Blendable = DeviceFeature._(
    'float32-blendable',
    FeatureStability.stable,
  );

  /// `TextureFormat.r11g11b10UFloat` is a colour attachment. WebGPU's
  /// `rg11b10ufloat-renderable`.
  static const rg11b10Renderable = DeviceFeature._(
    'rg11b10ufloat-renderable',
    FeatureStability.stable,
  );

  /// Shaders may use 16-bit floats. WebGPU's `shader-f16`. A shader-language
  /// feature: a bundle needing it is refused by `loadShaders` where it is
  /// absent, and no call here is gated by it.
  static const shaderF16 = DeviceFeature._(
    'shader-f16',
    FeatureStability.stable,
  );

  /// Subgroup operations in compute and fragment stages. WebGPU's
  /// `subgroups`. A shader-language feature, as [shaderF16].
  static const subgroups = DeviceFeature._(
    'subgroups',
    FeatureStability.stable,
  );

  /// User clip distances in a vertex stage. WebGPU's `clip-distances`. A
  /// shader-language feature, as [shaderF16].
  static const clipDistances = DeviceFeature._(
    'clip-distances',
    FeatureStability.stable,
  );

  /// `PassEncoder.bindUniformBytes` and `ComputeEncoder.bindUniformBytes`: a
  /// block filled from laid-out bytes rather than named float members, for
  /// integer and packed uniforms. The nearest portable thing to push
  /// constants; see [immediateData] for the real one.
  static const uniformBytes = DeviceFeature._(
    'uniform-bytes',
    FeatureStability.stable,
  );

  /// `GraphicsDevice.mapBuffer`: a buffer range mapped into host memory for
  /// reading or writing — the staging-buffer path. WebGPU's `mapAsync`.
  static const mappedBuffers = DeviceFeature._(
    'mapped-buffers',
    FeatureStability.stable,
  );

  /// `GraphicsDevice.readBufferSync`: a buffer read back in the calling
  /// turn, stalling until the GPU is done with it. WebGL2's
  /// `getBufferSubData`; WebGPU has no such call by design.
  static const synchronousReadback = DeviceFeature._(
    'synchronous-readback',
    FeatureStability.stable,
  );

  /// [QueryType.pipelineStatistics] query sets and
  /// `PassEncoder.beginPipelineStatisticsQuery`.
  static const pipelineStatisticsQuery = DeviceFeature._(
    'pipeline-statistics-query',
    FeatureStability.stable,
  );

  /// `GraphicsDevice.createRenderBundleEncoder` and
  /// `PassEncoder.executeBundles`: draws recorded once, replayed often.
  static const renderBundles = DeviceFeature._(
    'render-bundles',
    FeatureStability.stable,
  );

  /// `PassEncoder.multiDraw`: several indexed draws in one call. WebGL2's
  /// `WEBGL_multi_draw`.
  static const multiDraw = DeviceFeature._(
    'multi-draw',
    FeatureStability.stable,
  );

  /// `PassEncoder.multiDrawIndirect`: many indirect draws from one call,
  /// optionally with a GPU-written count. WebGPU's `multi-draw-indirect`.
  static const multiDrawIndirect = DeviceFeature._(
    'multi-draw-indirect',
    FeatureStability.stable,
  );

  /// A non-zero `IndexedDraw.baseVertex` or `IndexedDraw.firstInstance` on a
  /// direct draw. Core in WebGPU; WebGL2's
  /// `WEBGL_draw_instanced_base_vertex_base_instance`.
  static const baseVertexBaseInstance = DeviceFeature._(
    'base-vertex-base-instance',
    FeatureStability.stable,
  );

  /// A reversed projection keeps its precision here: clip space puts depth
  /// in `[0, 1]` (`GraphicsDevice.depthRange` is `DepthRange.zeroToOne`) and
  /// `GraphicsDevice.defaultDepthStencilFormat` stores floating point.
  ///
  /// **A property of two answers the device already gives, not a call.**
  /// Any device draws a reversed projection — near at one, far at nought,
  /// cleared to nought and tested with `greater` — and draws it correctly.
  /// What this says is whether doing so *gains* anything. A float's
  /// precision follows its exponent, so with near at one and far at nought
  /// the precision lost to a perspective divide is handed back as the
  /// distance grows; with depth stored in 24 fixed bits, or squeezed into
  /// `[-1, 1]` first, the two cancel nowhere and the reversal buys nothing.
  ///
  /// Metal and Vulkan through Impeller where the context's depth format is
  /// `d32FloatS8UInt`, WebGPU, WebGL2 with `EXT_clip_control`, and the
  /// software rasteriser, whose depth is a float everywhere.
  static const reversedDepth = DeviceFeature._(
    'reversed-depth',
    FeatureStability.stable,
  );

  // --------------------------------------------------------------- reserved
  // Named, not built. No backend may report these and no call exists yet.

  /// LocalRay queries against an acceleration structure from any stage.
  static const rayQuery = DeviceFeature._(
    'ray-query',
    FeatureStability.reserved,
  );

  /// Task and mesh stages in place of vertex assembly.
  static const meshShaders = DeviceFeature._(
    'mesh-shaders',
    FeatureStability.reserved,
  );

  /// Resources indexed from a shader by number rather than bound by name.
  static const bindlessResources = DeviceFeature._(
    'bindless-resources',
    FeatureStability.reserved,
  );

  /// Bytes recorded straight into the command stream for a draw — push
  /// constants. WebGPU's `immediate-data` proposal; see `uniformBytes` for
  /// what is portable today.
  static const immediateData = DeviceFeature._(
    'immediate-data',
    FeatureStability.reserved,
  );

  /// Every feature this version of the contract names, in declaration order.
  ///
  /// What a capability report lists and what the conformance honesty check
  /// walks. A later version appends; nothing is ever removed from it.
  static const List<DeviceFeature> values = <DeviceFeature>[
    offscreenMultisample,
    blendConstant,
    manualMipmaps,
    cubeTextures,
    renderToMipLevel,
    wireframe,
    alphaToCoverage,
    stencil,
    gpuTimestamps,
    compute,
    float32Filterable,
    float32Renderable,
    independentBlend,
    textureArrays,
    texture3D,
    cubeArrayTextures,
    renderToArrayLayer,
    textureWrites,
    buffers,
    bufferCopy,
    textureCopy,
    bufferTextureCopy,
    storageTextures,
    readWriteStorageTextures,
    renderStageStorage,
    indirectDraw,
    indirectDispatch,
    indirectFirstInstance,
    nonIndexedDraw,
    depthBias,
    colorWriteMask,
    depthClamp,
    minMaxBlend,
    dualSourceBlending,
    samplerCompare,
    samplerLodClamp,
    samplerBorderColor,
    occlusionQuery,
    timestampQuery,
    textureCompressionBC,
    textureCompressionETC2,
    textureCompressionASTC,
    textureCompressionASTCHdr,
    float32Blendable,
    rg11b10Renderable,
    shaderF16,
    subgroups,
    clipDistances,
    uniformBytes,
    mappedBuffers,
    synchronousReadback,
    pipelineStatisticsQuery,
    renderBundles,
    multiDraw,
    multiDrawIndirect,
    baseVertexBaseInstance,
    reversedDepth,
    rayQuery,
    meshShaders,
    bindlessResources,
    immediateData,
  ];

  /// The feature called [name], or null for a name this version does not
  /// know — which is what a report written by a newer version carries.
  static DeviceFeature? byName(String name) {
    for (final feature in values) {
      if (feature.name == name) return feature;
    }
    return null;
  }

  @override
  String toString() => 'DeviceFeature($name)';
}

/// The features one device has: a set that answers [has], and that can say
/// what it refuses in words a caller can act on.
@immutable
final class DeviceFeatures {
  /// The features in [features]. Throws an [ArgumentError] for a
  /// [FeatureStability.reserved] one: nothing implements those, so a device
  /// listing one would be reporting something no call can deliver.
  DeviceFeatures(Iterable<DeviceFeature> features)
    : _features = Set<DeviceFeature>.unmodifiable(features) {
    final reserved = _features
        .where((DeviceFeature f) => f.stability == FeatureStability.reserved)
        .map((DeviceFeature f) => f.name)
        .toList();
    if (reserved.isNotEmpty) {
      throw ArgumentError(
        'reserved features cannot be reported — nothing implements '
        '${reserved.join(', ')} yet',
      );
    }
  }

  /// A device that has none: what a fake starts from.
  static final DeviceFeatures none = DeviceFeatures(const <DeviceFeature>[]);

  final Set<DeviceFeature> _features;

  /// Whether the device has [feature].
  bool has(DeviceFeature feature) => _features.contains(feature);

  /// Every feature the device has, in [DeviceFeature.values] order.
  List<DeviceFeature> get all => <DeviceFeature>[
    for (final feature in DeviceFeature.values)
      if (_features.contains(feature)) feature,
  ];

  /// Every feature this version names that the device does not have,
  /// reserved ones included — what a report prints as "no".
  List<DeviceFeature> get missing => <DeviceFeature>[
    for (final feature in DeviceFeature.values)
      if (!_features.contains(feature)) feature,
  ];

  /// These features and [more].
  DeviceFeatures union(Iterable<DeviceFeature> more) =>
      DeviceFeatures(<DeviceFeature>{..._features, ...more});

  /// These features without [fewer] — what a test fake narrows a real
  /// device's answer with.
  DeviceFeatures without(Iterable<DeviceFeature> fewer) {
    final drop = fewer.toSet();
    return DeviceFeatures(_features.where((f) => !drop.contains(f)));
  }

  /// Throws [UnsupportedCapability] unless the device has [feature].
  ///
  /// **For a backend, on the way into every call [feature] gates**, so that
  /// all of them refuse in the same words. [backend] names the backend as a
  /// person would ("WebGL2", "the software rasteriser"); [reason] says why
  /// this one does not have it, and is the part a reader acts on.
  void require(
    DeviceFeature feature, {
    required String backend,
    String? reason,
  }) {
    if (has(feature)) return;
    throw UnsupportedCapability(feature, backend: backend, reason: reason);
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceFeatures &&
      other._features.length == _features.length &&
      other._features.containsAll(_features);

  @override
  int get hashCode => Object.hashAllUnordered(_features);

  @override
  String toString() =>
      'DeviceFeatures(${all.map((DeviceFeature f) => f.name).join(', ')})';
}

/// The refusal every feature-gated call throws on a device without the
/// feature: a [CapabilityException] that names what was asked for and who
/// refused it.
///
/// **One type, so that a caller and the conformance suite can tell a refusal
/// the contract promised from a backend falling over.** Before 0.9 each
/// backend wrote its own sentence into a bare [UnsupportedError], and a check
/// that wanted to know whether a throw was *the* refusal had only the message
/// to go on.
///
/// **An exception and not an [UnsupportedError] since 1.0**, because a
/// caller meets it in a correct program: a device that lacks a feature is a
/// fact about the hardware, not a mistake in the code that asked. A caller
/// who asks `GraphicsDevice.features` first never sees it.
final class UnsupportedCapability extends CapabilityException {
  const UnsupportedCapability(
    this.feature, {
    required this.backend,
    this.reason,
  });

  /// What was asked for.
  final DeviceFeature feature;

  /// Who refused, as a person would name the backend.
  final String backend;

  /// Why this backend does not have it, when it can say.
  final String? reason;

  @override
  String get message =>
      '$backend does not support ${feature.name}'
      '${reason == null ? '' : ': $reason'}. Ask whether '
      '`GraphicsDevice.features` has it before calling.';

  @override
  String toString() => 'UnsupportedCapability: $message';
}

/// How much of everything a device has: sizes, counts and alignments.
///
/// The defaults are WebGPU's guaranteed minimums, which is what a portable
/// caller may assume without asking; a backend constructs one with the
/// numbers it actually has. Compute limits are zero on a device without
/// [DeviceFeature.compute] — a backend says so rather than inheriting the
/// defaults.
@immutable
final class DeviceLimits {
  const DeviceLimits({
    this.maxTextureDimension1D = 8192,
    this.maxTextureDimension2D = 8192,
    this.maxTextureDimension3D = 2048,
    this.maxTextureArrayLayers = 256,
    this.maxColorAttachments = 8,
    this.maxColorAttachmentBytesPerSample = 32,
    this.maxSampleCount = 4,
    this.maxSamplerAnisotropy = 16,
    this.maxBindGroups = 4,
    this.maxSampledTexturesPerShaderStage = 16,
    this.maxSamplersPerShaderStage = 16,
    this.maxStorageBuffersPerShaderStage = 8,
    this.maxStorageTexturesPerShaderStage = 4,
    this.maxUniformBuffersPerShaderStage = 12,
    this.maxUniformBufferBindingSize = 65536,
    this.maxStorageBufferBindingSize = 134217728,
    this.maxBufferSize = 268435456,
    this.minUniformBufferOffsetAlignment = 256,
    this.minStorageBufferOffsetAlignment = 256,
    this.maxVertexBuffers = 8,
    this.maxVertexAttributes = 16,
    this.maxVertexBufferArrayStride = 2048,
    this.maxInterStageShaderVariables = 16,
    this.maxComputeWorkgroupStorageSize = 16384,
    this.maxComputeInvocationsPerWorkgroup = 256,
    this.maxComputeWorkgroupSizeX = 256,
    this.maxComputeWorkgroupSizeY = 256,
    this.maxComputeWorkgroupSizeZ = 64,
    this.maxComputeWorkgroupsPerDimension = 65535,
    this.maxImmediateDataSize = 0,
  });

  /// WebGPU's guaranteed minimums, which the constructor's defaults are.
  ///
  /// For a portable caller deciding what it may assume without asking a
  /// device, and for a third-party backend comparing what it reports against
  /// the baseline.
  static const DeviceLimits webgpuDefaults = DeviceLimits();

  final int maxTextureDimension1D;
  final int maxTextureDimension2D;
  final int maxTextureDimension3D;
  final int maxTextureArrayLayers;

  /// How many colour attachments one pass may open. What
  /// `GraphicsDevice.maxColorAttachments` forwards to.
  final int maxColorAttachments;
  final int maxColorAttachmentBytesPerSample;

  /// The largest sample count a multisampled target may have.
  final int maxSampleCount;

  /// The most taps a sampler may take; one for a device that filters
  /// isotropically only. What `GraphicsDevice.maxAnisotropy` forwards to.
  final int maxSamplerAnisotropy;

  final int maxBindGroups;
  final int maxSampledTexturesPerShaderStage;
  final int maxSamplersPerShaderStage;
  final int maxStorageBuffersPerShaderStage;
  final int maxStorageTexturesPerShaderStage;
  final int maxUniformBuffersPerShaderStage;
  final int maxUniformBufferBindingSize;
  final int maxStorageBufferBindingSize;
  final int maxBufferSize;
  final int minUniformBufferOffsetAlignment;
  final int minStorageBufferOffsetAlignment;
  final int maxVertexBuffers;
  final int maxVertexAttributes;
  final int maxVertexBufferArrayStride;
  final int maxInterStageShaderVariables;
  final int maxComputeWorkgroupStorageSize;
  final int maxComputeInvocationsPerWorkgroup;
  final int maxComputeWorkgroupSizeX;
  final int maxComputeWorkgroupSizeY;
  final int maxComputeWorkgroupSizeZ;
  final int maxComputeWorkgroupsPerDimension;

  /// Bytes of immediate data (push constants) a draw may carry. Zero
  /// everywhere: [DeviceFeature.immediateData] is reserved.
  final int maxImmediateDataSize;

  /// Every limit by its WebGPU name, in declaration order — what a capability
  /// report prints and what [==] compares.
  Map<String, int> toMap() => <String, int>{
    'maxTextureDimension1D': maxTextureDimension1D,
    'maxTextureDimension2D': maxTextureDimension2D,
    'maxTextureDimension3D': maxTextureDimension3D,
    'maxTextureArrayLayers': maxTextureArrayLayers,
    'maxColorAttachments': maxColorAttachments,
    'maxColorAttachmentBytesPerSample': maxColorAttachmentBytesPerSample,
    'maxSampleCount': maxSampleCount,
    'maxSamplerAnisotropy': maxSamplerAnisotropy,
    'maxBindGroups': maxBindGroups,
    'maxSampledTexturesPerShaderStage': maxSampledTexturesPerShaderStage,
    'maxSamplersPerShaderStage': maxSamplersPerShaderStage,
    'maxStorageBuffersPerShaderStage': maxStorageBuffersPerShaderStage,
    'maxStorageTexturesPerShaderStage': maxStorageTexturesPerShaderStage,
    'maxUniformBuffersPerShaderStage': maxUniformBuffersPerShaderStage,
    'maxUniformBufferBindingSize': maxUniformBufferBindingSize,
    'maxStorageBufferBindingSize': maxStorageBufferBindingSize,
    'maxBufferSize': maxBufferSize,
    'minUniformBufferOffsetAlignment': minUniformBufferOffsetAlignment,
    'minStorageBufferOffsetAlignment': minStorageBufferOffsetAlignment,
    'maxVertexBuffers': maxVertexBuffers,
    'maxVertexAttributes': maxVertexAttributes,
    'maxVertexBufferArrayStride': maxVertexBufferArrayStride,
    'maxInterStageShaderVariables': maxInterStageShaderVariables,
    'maxComputeWorkgroupStorageSize': maxComputeWorkgroupStorageSize,
    'maxComputeInvocationsPerWorkgroup': maxComputeInvocationsPerWorkgroup,
    'maxComputeWorkgroupSizeX': maxComputeWorkgroupSizeX,
    'maxComputeWorkgroupSizeY': maxComputeWorkgroupSizeY,
    'maxComputeWorkgroupSizeZ': maxComputeWorkgroupSizeZ,
    'maxComputeWorkgroupsPerDimension': maxComputeWorkgroupsPerDimension,
    'maxImmediateDataSize': maxImmediateDataSize,
  };

  @override
  bool operator ==(Object other) {
    if (other is! DeviceLimits) return false;
    final mine = toMap();
    final theirs = other.toMap();
    return mine.keys.every((String k) => mine[k] == theirs[k]);
  }

  @override
  int get hashCode => Object.hashAll(toMap().values);

  @override
  String toString() => 'DeviceLimits(${toMap()})';
}

/// What one [TextureFormat] can be used for on one device.
///
/// WebGPU's per-format capability table, asked per device: a format can be
/// sampled without being filterable, rendered to without being blendable, and
/// so on, and each "no" is a different fallback for the caller.
@immutable
final class TextureFormatSupport {
  const TextureFormatSupport({
    this.sampled = false,
    this.filterable = false,
    this.renderable = false,
    this.blendable = false,
    this.multisample = false,
    this.resolve = false,
    this.depthStencil = false,
    this.storage = false,
    this.storageReadWrite = false,
  });

  /// A format the device has nothing for.
  static const TextureFormatSupport none = TextureFormatSupport();

  /// A texture in it can be created and sampled. What
  /// `GraphicsDevice.supportsTextureFormat` forwards to.
  final bool sampled;

  /// A sampler may filter it linearly.
  final bool filterable;

  /// It can be a colour attachment.
  final bool renderable;

  /// A colour attachment in it can blend.
  final bool blendable;

  /// A multisampled texture can be made in it.
  final bool multisample;

  /// A multisampled attachment can resolve into it.
  final bool resolve;

  /// It can be a depth or stencil attachment.
  final bool depthStencil;

  /// A compute stage can bind it as a storage texture, write-only or
  /// read-only — [DeviceFeature.storageTextures].
  final bool storage;

  /// A compute stage can bind it read-write —
  /// [DeviceFeature.readWriteStorageTextures].
  final bool storageReadWrite;

  /// The uses as names, for a report.
  List<String> get uses => <String>[
    if (sampled) 'sampled',
    if (filterable) 'filterable',
    if (renderable) 'renderable',
    if (blendable) 'blendable',
    if (multisample) 'multisample',
    if (resolve) 'resolve',
    if (depthStencil) 'depth-stencil',
    if (storage) 'storage',
    if (storageReadWrite) 'storage-read-write',
  ];

  @override
  bool operator ==(Object other) =>
      other is TextureFormatSupport &&
      other.sampled == sampled &&
      other.filterable == filterable &&
      other.renderable == renderable &&
      other.blendable == blendable &&
      other.multisample == multisample &&
      other.resolve == resolve &&
      other.depthStencil == depthStencil &&
      other.storage == storage &&
      other.storageReadWrite == storageReadWrite;

  @override
  int get hashCode => Object.hash(
    sampled,
    filterable,
    renderable,
    blendable,
    multisample,
    resolve,
    depthStencil,
    storage,
    storageReadWrite,
  );

  @override
  String toString() => 'TextureFormatSupport(${uses.join(', ')})';
}
