/// A pass that records rather than draws.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import 'testing_recorded.dart';

/// A pass that was opened, and everything that went into it.
final class FakePass implements CommandEncoder {
  FakePass(this.descriptor);

  final RenderPassDescriptor descriptor;

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
  void bindPipeline(PipelineHandle pipeline) =>
      commands.add(RecordedPipeline(pipeline));

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
    commands.add(RecordedUniformBlock(shader, blockName, members));
    return true;
  }

  @override
  void bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerOptions? sampler,
  }) => commands.add(RecordedTexture(slot, texture, sampler));

  @override
  void clearBindings() => commands.add(const RecordedClearBindings());

  @override
  void draw({int instanceCount = 1}) =>
      commands.add(RecordedDraw(instanceCount: instanceCount));

  @override
  void submit() => submitted = true;
}
