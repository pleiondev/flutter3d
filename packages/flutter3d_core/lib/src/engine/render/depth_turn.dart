/// Depth tests spoken in the ordinary convention and turned on their way to
/// a pass whose depth runs reversed — `A2.8`.
///
/// Its own library, not a part of `renderer.dart`, because two encoders turn
/// depth: the renderer's reversed passes, and a contributor's render bundle
/// recorded for one of them (`ContributorFrame.createRenderBundleEncoder`).
/// Not exported by `flutter3d_core.dart`.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'pass_contributor.dart' show ContributorFrame;

/// A pass whose depth runs from one at the near plane to nought at the far
/// one, spoken to as though it ran the ordinary way.
///
/// **Every caller keeps writing `less`.** The scene's state, a material's
/// `depthCompare`, the x-ray's `greater` for "behind what is drawn", a
/// contributor that never heard of any of this: each says which depth wins
/// in the ordinary convention, and this turns the comparison round on its
/// way to the device. `less` becomes `greater`, `lessEqual` becomes
/// `greaterEqual`, and the two that do not order — `equal`, `notEqual` —
/// and the two that do not compare — `always`, `never` — pass as they are.
/// A depth bias pulls the other way for the same reason.
///
/// The alternative was a branch at each of the dozen places that name a
/// test, and a plugin's own draws would have been the thirteenth, which
/// nothing here can reach. The stencil test compares stencil values, not
/// depths, and is passed through untouched.
abstract base class DepthTurningEncoder extends PassEncoder {
  DepthTurningEncoder(this._inner);

  final PassEncoder _inner;

  /// [compare] as the reversed buffer has to be asked it.
  static CompareFunction turned(CompareFunction compare) => switch (compare) {
    CompareFunction.less => CompareFunction.greater,
    CompareFunction.lessEqual => CompareFunction.greaterEqual,
    CompareFunction.greater => CompareFunction.less,
    CompareFunction.greaterEqual => CompareFunction.lessEqual,
    CompareFunction.never ||
    CompareFunction.always ||
    CompareFunction.equal ||
    CompareFunction.notEqual => compare,
  };

  @override
  void setDepthCompare(CompareFunction compare) =>
      _inner.setDepthCompare(turned(compare));

  @override
  void setDepthBias(DepthBias bias) => _inner.setDepthBias(
    bias == DepthBias.none
        ? bias
        : DepthBias(
            constant: -bias.constant,
            slopeScale: -bias.slopeScale,
            clamp: -bias.clamp,
          ),
  );

  @override
  void setViewport(ScreenRect rect) => _inner.setViewport(rect);

  @override
  void setScissor(ScreenRect rect) => _inner.setScissor(rect);

  @override
  void setPrimitiveType(PrimitiveType type) => _inner.setPrimitiveType(type);

  @override
  void setPolygonMode(PolygonMode mode) => _inner.setPolygonMode(mode);

  @override
  void setCullMode(CullMode mode) => _inner.setCullMode(mode);

  @override
  void setWindingOrder(WindingOrder order) => _inner.setWindingOrder(order);

  @override
  void setDepthWrite({required bool enabled}) =>
      _inner.setDepthWrite(enabled: enabled);

  @override
  void setStencil(StencilState front, {StencilState? back}) =>
      _inner.setStencil(front, back: back);

  @override
  void setStencilReference(int value) => _inner.setStencilReference(value);

  @override
  void setBlend(BlendState? state, {int attachment = 0}) =>
      _inner.setBlend(state, attachment: attachment);

  @override
  void setAlphaToCoverage({required bool enabled}) =>
      _inner.setAlphaToCoverage(enabled: enabled);

  @override
  void setBlendColor(vm.Vector4 color) => _inner.setBlendColor(color);

  @override
  void bindPipeline(PipelineHandle pipeline) => _inner.bindPipeline(pipeline);

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) => _inner.bindVertexBuffer(buffer, vertexCount, slot: slot);

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      _inner.bindVertexData(bytes, vertexCount, slot: slot);

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) =>
      _inner.bindIndexBuffer(buffer, type, indexCount);

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) =>
      _inner.bindIndexData(bytes, type, indexCount);

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) => _inner.bindUniformBlock(shader, blockName, members);

  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) => _inner.bindTexture(shader, slot, texture, sampler: sampler);

  @override
  void clearBindings() => _inner.clearBindings();

  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) =>
      _inner.draw(
        instanceCount: instanceCount,
        firstIndex: firstIndex,
        indexCount: indexCount,
      );

  @override
  void drawIndexed(IndexedDraw draw) => _inner.drawIndexed(draw);

  @override
  void multiDraw(List<IndexedDraw> draws) => _inner.multiDraw(draws);

  @override
  void multiDrawIndirect(
    StorageBuffer arguments,
    int drawCount, {
    int offsetInBytes = 0,
    StorageBuffer? countBuffer,
    int countOffsetInBytes = 0,
  }) => _inner.multiDrawIndirect(
    arguments,
    drawCount,
    offsetInBytes: offsetInBytes,
    countBuffer: countBuffer,
    countOffsetInBytes: countOffsetInBytes,
  );

  /// Passed through as recorded: a bundle's depth tests were set when it
  /// was recorded and cannot be turned here, which is why
  /// [ContributorFrame.createRenderBundleEncoder] records them turned.
  @override
  void executeBundles(List<RenderBundle> bundles) =>
      _inner.executeBundles(bundles);

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) =>
      _inner.beginPipelineStatisticsQuery(querySet, queryIndex);

  @override
  void endPipelineStatisticsQuery() => _inner.endPipelineStatisticsQuery();

  @override
  void setColorWriteMask(ColorWriteMask mask, {int attachment = 0}) =>
      _inner.setColorWriteMask(mask, attachment: attachment);

  @override
  void setDepthClamp({required bool enabled}) =>
      _inner.setDepthClamp(enabled: enabled);

  @override
  bool bindStorageBuffer(
    ShaderHandle shader,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) => _inner.bindStorageBuffer(
    shader,
    name,
    buffer,
    offsetInBytes: offsetInBytes,
    sizeInBytes: sizeInBytes,
  );

  @override
  bool bindStorageTexture(
    ShaderHandle shader,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  }) => _inner.bindStorageTexture(
    shader,
    name,
    texture,
    mipLevel: mipLevel,
    access: access,
  );

  @override
  bool bindUniformBytes(
    ShaderHandle shader,
    String blockName,
    ByteData bytes,
  ) => _inner.bindUniformBytes(shader, blockName, bytes);

  @override
  void drawIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) =>
      _inner.drawIndirect(arguments, offsetInBytes: offsetInBytes);

  @override
  void drawNonIndexed({
    required int vertexCount,
    int firstVertex = 0,
    int instanceCount = 1,
    int firstInstance = 0,
  }) => _inner.drawNonIndexed(
    vertexCount: vertexCount,
    firstVertex: firstVertex,
    instanceCount: instanceCount,
    firstInstance: firstInstance,
  );

  @override
  void beginOcclusionQuery(int queryIndex) =>
      _inner.beginOcclusionQuery(queryIndex);

  @override
  void endOcclusionQuery() => _inner.endOcclusionQuery();
}

/// A render bundle recorded for a reversed pass, its depth tests turned as
/// they are written — `A2.8`.
///
/// **Turned when recorded, since they cannot be turned when replayed.** A
/// bundle keeps the state it was recorded with, so a pass that turns every
/// test it is given cannot reach the ones inside a bundle: one recorded with
/// `less` and replayed into a reversed pass kept only what lay behind
/// everything. What [ContributorFrame.createRenderBundleEncoder] hands out
/// under reversed depth.
final class TurnedBundleEncoder extends DepthTurningEncoder
    with RenderBundleEncoder {
  TurnedBundleEncoder(RenderBundleEncoder super.inner);

  @override
  RenderBundle finish({String? label}) {
    final bundle = (_inner as RenderBundleEncoder).finish(label: label);
    _turned[bundle] = true;
    return bundle;
  }
}

final Expando<bool> _turned = Expando<bool>('recorded turned');

/// Whether [bundle] was recorded through a [TurnedBundleEncoder], for a
/// pass whose depth runs reversed.
bool isRecordedTurned(RenderBundle bundle) => _turned[bundle] ?? false;
