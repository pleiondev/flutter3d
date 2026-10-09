/// A pass that records rather than draws.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import 'backend_handles.dart';
import 'testing_recorded.dart';

/// A pass that was opened, and everything that went into it.
///
/// **Given [stageBindings], it holds binds to the contract** the way a real
/// backend does: a block or sampler bound to a stage that does not declare it
/// answers false, bindings do not survive [bindPipeline], and a draw that
/// leaves a declared slot unbound is written to [violations]. A stage the map
/// does not name is taken on trust. Without the map it records and accepts
/// everything, which is what every test written before 0.8.0 expects.
///
/// **It is also the fake's render bundle encoder** — [FakePass.bundle] — so
/// that a bundle records exactly what a pass records; the members a bundle
/// may not record throw a [StateError] there, as the contract says.
final class FakePass extends PassEncoder
    with CommandEncoder, RenderBundleEncoder {
  FakePass(
    this.descriptor, {
    this.stageBindings,
    List<String>? violations,
    DeviceFeatures? features,
  }) : violations = violations ?? <String>[],
       features = features ?? DeviceFeatures.none,
       bundleDescriptor = null;

  /// A bundle encoder: records like a pass, and [finish]es into a
  /// [RenderBundle] whose backend object is this pass.
  FakePass.bundle(
    RenderBundleDescriptor this.bundleDescriptor, {
    DeviceFeatures? features,
  }) : descriptor = const RenderPassDescriptor(colors: <ColorTarget>[]),
       stageBindings = null,
       violations = <String>[],
       features = features ?? DeviceFeatures.none;

  /// What the pass was opened with; a descriptor with no attachments for a
  /// bundle, which has none of its own.
  final RenderPassDescriptor descriptor;

  /// What the bundle is recorded against; null for a pass.
  final RenderBundleDescriptor? bundleDescriptor;

  /// What the device that opened it reports. A 1.0-surface call the set
  /// lacks is refused with [UnsupportedCapability], as on a real backend;
  /// one it has is recorded as a [RecordedCall].
  final DeviceFeatures features;

  static const String _name = 'FakeBackend';

  void _gated(DeviceFeature feature, String name, [Object? arguments]) {
    features.require(feature, backend: _name);
    commands.add(RecordedCall(name, arguments));
  }

  void _passOnly(String member) {
    if (bundleDescriptor != null) {
      throw StateError('$member cannot be recorded into a render bundle');
    }
  }

  /// Stage name to what it declares, or null to accept every bind.
  final Map<String, StageBindings>? stageBindings;

  /// Declared slots a draw left unbound, one line each, with the pipeline and
  /// the stage. Shared with the device that opened the pass.
  final List<String> violations;

  String? _pipelineName;
  final Map<String, Set<String>> _boundBlocks = <String, Set<String>>{};
  final Map<String, Set<String>> _boundSamplers = <String, Set<String>>{};

  bool _declares(ShaderHandle shader, String name, {required bool sampler}) {
    final declared = stageBindings?[shader.name];
    if (declared == null) return true;
    return (sampler ? declared.samplers : declared.blocks).contains(name);
  }

  void _forget() {
    _boundBlocks.clear();
    _boundSamplers.clear();
  }

  /// Everything recorded, in order.
  final List<Recorded> commands = <Recorded>[];

  bool submitted = false;

  // Terminal state, which is what most assertions actually want: whether the
  // pass was left writing depth matters, the order the flag was toggled in
  // usually does not.
  PrimitiveType? primitiveType;
  PolygonMode? polygonMode;

  /// The last `setAlphaToCoverage`, or null when the pass never set it.
  bool? alphaToCoverage;
  CullMode? cullMode;
  WindingOrder? windingOrder;
  bool? depthWrite;
  CompareFunction? depthCompare;

  /// The stencil state the pass was left in, per face. Null means it was
  /// never mentioned, which is the answer every pass but the x-ray's gives.
  StencilState? stencilFront;
  StencilState? stencilBack;
  int? stencilReference;

  int get drawCount => commands.whereType<RecordedDraw>().length;

  ColorTarget get color => descriptor.colors.single;

  Iterable<T> recordedOf<T extends Recorded>() => commands.whereType<T>();

  @override
  void setViewport(ScreenRect rect) {
    _passOnly('setViewport');
    commands.add(RecordedViewport(rect));
  }

  @override
  void setScissor(ScreenRect rect) {
    _passOnly('setScissor');
    commands.add(RecordedScissor(rect));
  }

  @override
  void setPrimitiveType(PrimitiveType type) {
    primitiveType = type;
    commands.add(RecordedPrimitiveType(type));
  }

  @override
  void setPolygonMode(PolygonMode mode) {
    polygonMode = mode;
    commands.add(RecordedPolygonMode(mode));
  }

  @override
  void setAlphaToCoverage({required bool enabled}) {
    alphaToCoverage = enabled;
    commands.add(RecordedAlphaToCoverage(enabled));
  }

  @override
  void setCullMode(CullMode mode) {
    cullMode = mode;
    commands.add(RecordedCullMode(mode));
  }

  @override
  void setWindingOrder(WindingOrder order) {
    windingOrder = order;
    commands.add(RecordedWindingOrder(order));
  }

  @override
  void setDepthWrite({required bool enabled}) {
    depthWrite = enabled;
    commands.add(RecordedDepthWrite(enabled));
  }

  @override
  void setDepthCompare(CompareFunction compare) {
    depthCompare = compare;
    commands.add(RecordedDepthCompare(compare));
  }

  @override
  void setStencil(StencilState front, {StencilState? back}) {
    stencilFront = front;
    stencilBack = back ?? front;
    commands.add(RecordedStencil(front, back));
  }

  @override
  void setStencilReference(int value) {
    _passOnly('setStencilReference');
    stencilReference = value;
    commands.add(RecordedStencilReference(value));
  }

  @override
  void setBlend(BlendState? state, {int attachment = 0}) =>
      commands.add(RecordedBlend(state, attachment));

  @override
  void setBlendColor(Vector4 color) {
    _passOnly('setBlendColor');
    commands.add(RecordedBlendColor(color.clone()));
  }

  @override
  void bindPipeline(PipelineHandle pipeline) {
    commands.add(RecordedPipeline(pipeline));
    _pipelineName = pipeline.name;
    _forget();
  }

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) =>
      commands.add(RecordedVertices(vertexCount, transient: false, slot: slot));

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      commands.add(RecordedVertices(vertexCount, transient: true, slot: slot));

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    commands.add(RecordedIndices(type, indexCount, transient: false));
    _boundIndices = indexCount;
  }

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    commands.add(RecordedIndices(type, indexCount, transient: true));
    _boundIndices = indexCount;
  }

  /// How many indices the last binding carried, for holding a draw's window
  /// to it as every real backend does. Null until something is bound, and
  /// then a window is recorded as it was asked for: a test that draws with
  /// nothing bound is asserting on the order of calls, not on geometry.
  int? _boundIndices;

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    // `gfx-92n`: a block the compiled stage dropped is refused here, before
    // anything reaches the driver — binding one is a native crash on Metal.
    if (!shader.mayBindBlock(blockName)) return false;
    // Copied, as every real backend copies at the bind: the engine refills
    // one block object per draw (`H1`), and a recording that kept the map
    // would show every draw the last draw's values.
    commands.add(
      RecordedUniformBlock(shader, blockName, <String, Float32List>{
        for (final MapEntry(:key, :value) in members.entries)
          key: Float32List.fromList(value),
      }),
    );
    if (!_declares(shader, blockName, sampler: false)) return false;
    _boundBlocks.putIfAbsent(shader.name, () => <String>{}).add(blockName);
    return true;
  }

  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    if (!shader.mayBindSampler(slot)) return false;
    commands.add(RecordedTexture(slot, texture, sampler, shader: shader));
    if (!_declares(shader, slot, sampler: true)) return false;
    _boundSamplers.putIfAbsent(shader.name, () => <String>{}).add(slot);
    return true;
  }

  @override
  void clearBindings() {
    commands.add(const RecordedClearBindings());
    _forget();
    _boundIndices = null;
  }

  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) {
    final window = switch (_boundIndices) {
      final bound? => indexWindow(
        bound,
        firstIndex: firstIndex,
        indexCount: indexCount,
      ),
      null => (first: firstIndex, count: indexCount),
    };
    commands.add(
      RecordedDraw(
        instanceCount: instanceCount,
        firstIndex: window.first,
        indexCount: indexCount == null ? null : window.count,
      ),
    );
    final bindings = stageBindings;
    final pipeline = _pipelineName;
    if (bindings == null || pipeline == null) return;
    // The fake names its pipelines 'Vertex+Fragment'; see FakeBackend.
    for (final stage in pipeline.split('+')) {
      final declared = bindings[stage];
      if (declared == null) continue;
      for (final block in declared.blocks) {
        if (_boundBlocks[stage]?.contains(block) ?? false) continue;
        violations.add('$pipeline: $stage declares block "$block", unbound');
      }
      for (final sampler in declared.samplers) {
        if (_boundSamplers[stage]?.contains(sampler) ?? false) continue;
        violations.add(
          '$pipeline: $stage declares sampler "$sampler", unbound',
        );
      }
    }
  }

  @override
  void submit() => submitted = true;

  // ---------------------------------------------------------------- 1.0

  @override
  void setDepthBias(DepthBias bias) =>
      _gated(DeviceFeature.depthBias, 'setDepthBias', bias);

  @override
  void setColorWriteMask(ColorWriteMask mask, {int attachment = 0}) => _gated(
    DeviceFeature.colorWriteMask,
    'setColorWriteMask',
    (mask: mask, attachment: attachment),
  );

  @override
  void setDepthClamp({required bool enabled}) =>
      _gated(DeviceFeature.depthClamp, 'setDepthClamp', enabled);

  @override
  bool bindStorageBuffer(
    ShaderHandle shader,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    _gated(DeviceFeature.renderStageStorage, 'bindStorageBuffer', (
      shader: shader,
      name: name,
      buffer: buffer,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    ));
    return true;
  }

  @override
  bool bindStorageTexture(
    ShaderHandle shader,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  }) {
    _gated(DeviceFeature.renderStageStorage, 'bindStorageTexture', (
      shader: shader,
      name: name,
      texture: texture,
      mipLevel: mipLevel,
      access: access,
    ));
    return true;
  }

  @override
  bool bindUniformBytes(ShaderHandle shader, String blockName, ByteData bytes) {
    if (!shader.mayBindBlock(blockName)) return false;
    _gated(DeviceFeature.uniformBytes, 'bindUniformBytes', (
      shader: shader,
      blockName: blockName,
      lengthInBytes: bytes.lengthInBytes,
    ));
    return true;
  }

  @override
  void drawIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) => _gated(
    DeviceFeature.indirectDraw,
    'drawIndirect',
    (arguments: arguments, offsetInBytes: offsetInBytes),
  );

  @override
  void drawNonIndexed({
    required int vertexCount,
    int firstVertex = 0,
    int instanceCount = 1,
    int firstInstance = 0,
  }) => _gated(DeviceFeature.nonIndexedDraw, 'drawNonIndexed', (
    vertexCount: vertexCount,
    firstVertex: firstVertex,
    instanceCount: instanceCount,
    firstInstance: firstInstance,
  ));

  /// A draw with a zero base vertex and first instance is [draw], recorded
  /// as one, on every fake; anything else needs the feature.
  @override
  void drawIndexed(IndexedDraw draw) {
    if (!draw.usesBaseVertexOrInstance) {
      this.draw(
        instanceCount: draw.instanceCount,
        firstIndex: draw.firstIndex,
        indexCount: draw.indexCount,
      );
      return;
    }
    _gated(DeviceFeature.baseVertexBaseInstance, 'drawIndexed', draw);
  }

  @override
  void multiDraw(List<IndexedDraw> draws) => _gated(
    DeviceFeature.multiDraw,
    'multiDraw',
    List<IndexedDraw>.unmodifiable(draws),
  );

  @override
  void multiDrawIndirect(
    StorageBuffer arguments,
    int drawCount, {
    int offsetInBytes = 0,
    StorageBuffer? countBuffer,
    int countOffsetInBytes = 0,
  }) => _gated(DeviceFeature.multiDrawIndirect, 'multiDrawIndirect', (
    arguments: arguments,
    drawCount: drawCount,
    offsetInBytes: offsetInBytes,
    countBuffer: countBuffer,
    countOffsetInBytes: countOffsetInBytes,
  ));

  @override
  void executeBundles(List<RenderBundle> bundles) {
    _passOnly('executeBundles');
    _gated(
      DeviceFeature.renderBundles,
      'executeBundles',
      List<RenderBundle>.unmodifiable(bundles),
    );
    _forget();
    _boundIndices = null;
  }

  @override
  void beginOcclusionQuery(int queryIndex) {
    _passOnly('beginOcclusionQuery');
    _gated(DeviceFeature.occlusionQuery, 'beginOcclusionQuery', queryIndex);
  }

  @override
  void endOcclusionQuery() {
    _passOnly('endOcclusionQuery');
    _gated(DeviceFeature.occlusionQuery, 'endOcclusionQuery');
  }

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) {
    _passOnly('beginPipelineStatisticsQuery');
    _gated(
      DeviceFeature.pipelineStatisticsQuery,
      'beginPipelineStatisticsQuery',
      (querySet: querySet, queryIndex: queryIndex),
    );
  }

  @override
  void endPipelineStatisticsQuery() {
    _passOnly('endPipelineStatisticsQuery');
    _gated(DeviceFeature.pipelineStatisticsQuery, 'endPipelineStatisticsQuery');
  }

  @override
  RenderBundle finish({String? label}) {
    final bundle = bundleDescriptor;
    if (bundle == null) {
      throw StateError('finish ends a render bundle; a pass is submitted');
    }
    return wrapRenderBundle(backend: this, descriptor: bundle, label: label);
  }
}

/// A mapping of bytes a fake never had: zeros, handed back on [unmap].
final class FakeMapping extends MappedBuffer {
  FakeMapping(this.bytes);

  @override
  final ByteData bytes;

  /// Whether [unmap] has been called.
  bool unmapped = false;

  @override
  void unmap() => unmapped = true;
}

/// A transfer pass that records its copies into the device's `calls`, and
/// refuses those the device's features lack.
final class FakeTransfer extends TransferEncoder {
  FakeTransfer(this.features, this.calls);

  final DeviceFeatures features;

  /// Shared with the device that opened it.
  final List<RecordedCall> calls;

  /// Whether [submit] has been called.
  bool submitted = false;

  void _gated(DeviceFeature feature, String name, Object? arguments) {
    features.require(feature, backend: 'FakeBackend');
    calls.add(RecordedCall(name, arguments));
  }

  @override
  void copyBufferToBuffer(
    StorageBuffer source,
    int sourceOffset,
    StorageBuffer destination,
    int destinationOffset,
    int size,
  ) => _gated(DeviceFeature.bufferCopy, 'copyBufferToBuffer', (
    source: source,
    sourceOffset: sourceOffset,
    destination: destination,
    destinationOffset: destinationOffset,
    size: size,
  ));

  @override
  void clearBuffer(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) => _gated(DeviceFeature.bufferCopy, 'clearBuffer', (
    buffer: buffer,
    offsetInBytes: offsetInBytes,
    sizeInBytes: sizeInBytes,
  ));

  @override
  void copyTextureToTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) => _gated(DeviceFeature.textureCopy, 'copyTextureToTexture', (
    source: source,
    destination: destination,
    width: width,
    height: height,
    depthOrArrayLayers: depthOrArrayLayers,
  ));

  @override
  void copyBufferToTexture(
    StorageBuffer source,
    BufferTextureLayout layout,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) => _gated(DeviceFeature.bufferTextureCopy, 'copyBufferToTexture', (
    source: source,
    layout: layout,
    destination: destination,
    width: width,
    height: height,
    depthOrArrayLayers: depthOrArrayLayers,
  ));

  @override
  void copyTextureToBuffer(
    TextureCopyLocation source,
    StorageBuffer destination,
    BufferTextureLayout layout, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) => _gated(DeviceFeature.bufferTextureCopy, 'copyTextureToBuffer', (
    source: source,
    destination: destination,
    layout: layout,
    width: width,
    height: height,
    depthOrArrayLayers: depthOrArrayLayers,
  ));

  @override
  void resolveTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination,
  ) => _gated(DeviceFeature.offscreenMultisample, 'resolveTexture', (
    source: source,
    destination: destination,
  ));

  @override
  void submit() => submitted = true;
}
