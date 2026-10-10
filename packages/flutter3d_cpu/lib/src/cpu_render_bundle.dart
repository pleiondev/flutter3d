/// Render bundles on the software rasteriser: calls recorded once and
/// replayed into a pass.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import 'cpu_resources.dart';
import 'cpu_shader.dart';

/// What a [RenderBundle] holds here: the calls, in order.
final class CpuRenderBundle {
  CpuRenderBundle(List<void Function(PassEncoder)> calls)
    : calls = List<void Function(PassEncoder)>.unmodifiable(calls);

  final List<void Function(PassEncoder)> calls;
}

/// Records a bundle — `GraphicsDevice.createRenderBundleEncoder`.
///
/// **Recorded and replayed, which is all a bundle can be on a backend with
/// no command buffer.** Each call is checked here, where the caller made
/// it — a missing feature, a bad usage, a binding a pass would refuse — and
/// kept as a call; `PassEncoder.executeBundles` makes them again against the
/// pass. Bytes handed to [bindVertexData], [bindIndexData] and
/// [bindUniformBlock] are copied when recorded, as a pass consumes them when
/// it is handed them. What the contract keeps out of a bundle throws a
/// [StateError]: the viewport, scissor, blend constant, stencil reference,
/// queries and nested bundles belong to the pass replaying it.
final class CpuRenderBundleEncoder extends PassEncoder
    with RenderBundleEncoder {
  CpuRenderBundleEncoder(
    this._descriptor, {
    required this._features,
    required this._support,
  });

  final RenderBundleDescriptor _descriptor;
  final DeviceFeatures _features;
  final TextureFormatSupport Function(TextureFormat) _support;
  final List<void Function(PassEncoder)> _calls =
      <void Function(PassEncoder)>[];
  bool _finished = false;

  void _record(void Function(PassEncoder) call) {
    if (_finished) {
      throw StateError('a call recorded into a finished render bundle');
    }
    _calls.add(call);
  }

  static Never _notInBundle(String member) => throw StateError(
    '$member belongs to the pass a bundle is replayed into, not to the '
    'bundle',
  );

  @override
  RenderBundle finish({String? label}) {
    if (_finished) throw StateError('a render bundle finished twice');
    _finished = true;
    return wrapRenderBundle(
      backend: CpuRenderBundle(_calls),
      descriptor: _descriptor,
      label: label ?? _descriptor.label,
    );
  }

  @override
  void setViewport(ScreenRect rect) => _notInBundle('setViewport');

  @override
  void setScissor(ScreenRect rect) => _notInBundle('setScissor');

  @override
  void setBlendColor(Vector4 color) => _notInBundle('setBlendColor');

  @override
  void setStencilReference(int value) => _notInBundle('setStencilReference');

  @override
  void beginOcclusionQuery(int queryIndex) =>
      _notInBundle('beginOcclusionQuery');

  @override
  void endOcclusionQuery() => _notInBundle('endOcclusionQuery');

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) =>
      _notInBundle('beginPipelineStatisticsQuery');

  @override
  void endPipelineStatisticsQuery() =>
      _notInBundle('endPipelineStatisticsQuery');

  @override
  void executeBundles(List<RenderBundle> bundles) =>
      _notInBundle('executeBundles');

  @override
  void setPrimitiveType(PrimitiveType type) =>
      _record((p) => p.setPrimitiveType(type));

  @override
  void setPolygonMode(PolygonMode mode) {
    if (mode == PolygonMode.line) {
      _features.require(
        DeviceFeature.wireframe,
        backend: cpuBackendName,
        reason: wireframeRefusal,
      );
    }
    _record((p) => p.setPolygonMode(mode));
  }

  @override
  void setCullMode(CullMode mode) => _record((p) => p.setCullMode(mode));

  @override
  void setWindingOrder(WindingOrder order) =>
      _record((p) => p.setWindingOrder(order));

  @override
  void setDepthWrite({required bool enabled}) =>
      _record((p) => p.setDepthWrite(enabled: enabled));

  @override
  void setDepthCompare(CompareFunction compare) =>
      _record((p) => p.setDepthCompare(compare));

  @override
  void setStencil(StencilState front, {StencilState? back}) =>
      _record((p) => p.setStencil(front, back: back));

  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    if (state != null) checkBlend(state, attachment, _features);
    _record((p) => p.setBlend(state, attachment: attachment));
  }

  @override
  void setAlphaToCoverage({required bool enabled}) =>
      _record((p) => p.setAlphaToCoverage(enabled: enabled));

  @override
  void setDepthBias(DepthBias bias) {
    _features.require(DeviceFeature.depthBias, backend: cpuBackendName);
    _record((p) => p.setDepthBias(bias));
  }

  @override
  void setColorWriteMask(ColorWriteMask mask, {int attachment = 0}) {
    _features.require(DeviceFeature.colorWriteMask, backend: cpuBackendName);
    _record((p) => p.setColorWriteMask(mask, attachment: attachment));
  }

  @override
  void setDepthClamp({required bool enabled}) {
    _features.require(DeviceFeature.depthClamp, backend: cpuBackendName);
    _record((p) => p.setDepthClamp(enabled: enabled));
  }

  @override
  void bindPipeline(PipelineHandle pipeline) =>
      _record((p) => p.bindPipeline(pipeline));

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) => _record((p) => p.bindVertexBuffer(buffer, vertexCount, slot: slot));

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) {
    final kept = _copy(bytes);
    _record((p) => p.bindVertexData(kept, vertexCount, slot: slot));
  }

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) =>
      _record((p) => p.bindIndexBuffer(buffer, type, indexCount));

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    final kept = _copy(bytes);
    _record((p) => p.bindIndexData(kept, type, indexCount));
  }

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    if (!shader.mayBindBlock(blockName)) return false;
    final kept = <String, Float32List>{
      for (final MapEntry(:key, :value) in members.entries)
        key: Float32List.fromList(value),
    };
    _record((p) => p.bindUniformBlock(shader, blockName, kept));
    return true;
  }

  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    checkSampler(sampler, _features);
    if (!shader.mayBindSampler(slot)) return false;
    _record((p) => p.bindTexture(shader, slot, texture, sampler: sampler));
    return true;
  }

  @override
  bool bindStorageBuffer(
    ShaderHandle shader,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    _features.require(
      DeviceFeature.renderStageStorage,
      backend: cpuBackendName,
    );
    storageRangeOf(
      buffer,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
    if (!declaresStorage(shader, name, undeclared: false)) return false;
    _record(
      (p) => p.bindStorageBuffer(
        shader,
        name,
        buffer,
        offsetInBytes: offsetInBytes,
        sizeInBytes: sizeInBytes,
      ),
    );
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
    _features.require(
      DeviceFeature.renderStageStorage,
      backend: cpuBackendName,
    );
    CpuStorageTexture.bind(
      texture,
      mipLevel: mipLevel,
      access: access,
      features: _features,
      support: _support(texture.format),
      backend: cpuBackendName,
    );
    if (!declaresStorage(shader, name, undeclared: false)) return false;
    _record(
      (p) => p.bindStorageTexture(
        shader,
        name,
        texture,
        mipLevel: mipLevel,
        access: access,
      ),
    );
    return true;
  }

  @override
  bool bindUniformBytes(
    ShaderHandle shader,
    String blockName,
    ByteData bytes,
  ) => throw uniformBytesRefusal();

  @override
  void clearBindings() => _record((p) => p.clearBindings());

  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) =>
      _record(
        (p) => p.draw(
          instanceCount: instanceCount,
          firstIndex: firstIndex,
          indexCount: indexCount,
        ),
      );

  @override
  void drawIndexed(IndexedDraw draw) {
    checkIndexedDraw(draw, _features);
    _record((p) => p.drawIndexed(draw));
  }

  @override
  void multiDraw(List<IndexedDraw> draws) {
    _features.require(DeviceFeature.multiDraw, backend: cpuBackendName);
    for (final draw in draws) {
      checkIndexedDraw(draw, _features);
    }
    final kept = List<IndexedDraw>.of(draws);
    _record((p) => p.multiDraw(kept));
  }

  @override
  void multiDrawIndirect(
    StorageBuffer arguments,
    int drawCount, {
    int offsetInBytes = 0,
    StorageBuffer? countBuffer,
    int countOffsetInBytes = 0,
  }) {
    _features.require(DeviceFeature.multiDrawIndirect, backend: cpuBackendName);
    _record(
      (p) => p.multiDrawIndirect(
        arguments,
        drawCount,
        offsetInBytes: offsetInBytes,
        countBuffer: countBuffer,
        countOffsetInBytes: countOffsetInBytes,
      ),
    );
  }

  @override
  void drawIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) {
    _features.require(DeviceFeature.indirectDraw, backend: cpuBackendName);
    _record((p) => p.drawIndirect(arguments, offsetInBytes: offsetInBytes));
  }

  @override
  void drawNonIndexed({
    required int vertexCount,
    int firstVertex = 0,
    int instanceCount = 1,
    int firstInstance = 0,
  }) {
    _features.require(DeviceFeature.nonIndexedDraw, backend: cpuBackendName);
    _record(
      (p) => p.drawNonIndexed(
        vertexCount: vertexCount,
        firstVertex: firstVertex,
        instanceCount: instanceCount,
        firstInstance: firstInstance,
      ),
    );
  }

  static ByteData _copy(ByteData bytes) => ByteData.sublistView(
    Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    ),
  );
}
