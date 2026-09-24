/// A pass that records rather than draws.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import 'testing_recorded.dart';

/// A pass that was opened, and everything that went into it.
///
/// **Given [stageBindings], it holds binds to the contract** the way a real
/// backend does: a block or sampler bound to a stage that does not declare it
/// answers false, bindings do not survive [bindPipeline], and a draw that
/// leaves a declared slot unbound is written to [violations]. A stage the map
/// does not name is taken on trust. Without the map it records and accepts
/// everything, which is what every test written before 0.8.0 expects.
final class FakePass implements CommandEncoder {
  FakePass(
    this.descriptor, {
    this.stageBindings,
    List<String>? violations,
  }) : violations = violations ?? <String>[];

  final RenderPassDescriptor descriptor;

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
  void setViewport(ScreenRect rect) => commands.add(RecordedViewport(rect));

  @override
  void setScissor(ScreenRect rect) => commands.add(RecordedScissor(rect));

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
  void setDepthWrite(bool enabled) {
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
    stencilReference = value;
    commands.add(RecordedStencilReference(value));
  }

  @override
  void setBlend(BlendState? state, {int attachment = 0}) =>
      commands.add(RecordedBlend(state, attachment));

  @override
  void setBlendColor(Vector4 color) =>
      commands.add(RecordedBlendColor(color.clone()));

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
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) =>
      commands.add(RecordedIndices(type, indexCount, transient: false));

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) =>
      commands.add(RecordedIndices(type, indexCount, transient: true));

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    // `gfx-92n`: a block the compiled stage dropped is refused here, before
    // anything reaches the driver — binding one is a native crash on Metal.
    if (!shader.mayBindBlock(blockName)) return false;
    commands.add(RecordedUniformBlock(shader, blockName, members));
    if (!_declares(shader, blockName, sampler: false)) return false;
    _boundBlocks.putIfAbsent(shader.name, () => <String>{}).add(blockName);
    return true;
  }

  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerOptions? sampler,
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
  }

  @override
  void draw({int instanceCount = 1}) {
    commands.add(RecordedDraw(instanceCount: instanceCount));
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
}
