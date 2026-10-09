/// Render bundles, recorded and replayed — `GraphicsDevice.createRenderBundleEncoder`.
///
/// **WebGL has no native bundle, and the contract allows a replay.** Each
/// call a bundle encoder takes is checked against the device's features at
/// record time, exactly as a pass would check it, and kept as a closure; a
/// pass that executes the bundle runs the closures against itself. What a
/// bundle saves on WebGPU — validation and encoding done once — is not saved
/// here, and nothing claims it is: what is kept is the contract's shape, so
/// a caller written against bundles runs unchanged on this backend.
///
/// The members that belong to a pass rather than to its draws throw a
/// [StateError] at record time, as the contract says: replayed, they would
/// apply to whatever pass the bundle was executed in.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' show Vector4;
import 'package:web/web.dart' as web;

import 'webgl_device.dart';
import 'webgl_shaders.dart';

/// What a [RenderBundle] carries on this backend: the recorded calls.
final class WebGlBundle {
  WebGlBundle(List<void Function(PassEncoder pass)> calls)
    : calls = List<void Function(PassEncoder pass)>.unmodifiable(calls);

  final List<void Function(PassEncoder pass)> calls;
}

/// Records a [WebGlBundle]. See the library note.
final class WebGlRenderBundleEncoder extends PassEncoder
    with RenderBundleEncoder {
  WebGlRenderBundleEncoder(this._device, this._gl, this._descriptor);

  final WebGlDevice _device;
  final web.WebGL2RenderingContext _gl;
  final RenderBundleDescriptor _descriptor;
  final List<void Function(PassEncoder pass)> _calls =
      <void Function(PassEncoder pass)>[];
  bool _finished = false;

  void _record(void Function(PassEncoder pass) call) {
    _open();
    _calls.add(call);
  }

  void _open() {
    if (_finished) {
      throw StateError('this bundle was already finished');
    }
  }

  Never _passOnly(String member) => throw StateError(
    '$member belongs to a pass, not to a bundle: a bundle replayed into a '
    'pass would set it on that pass',
  );

  @override
  RenderBundle finish({String? label}) {
    _open();
    _finished = true;
    return wrapRenderBundle(
      backend: WebGlBundle(_calls),
      descriptor: _descriptor,
      label: label ?? _descriptor.label,
    );
  }

  // ------------------------------------------------- what a pass owns

  @override
  void setViewport(ScreenRect rect) => _passOnly('setViewport');

  @override
  void setScissor(ScreenRect rect) => _passOnly('setScissor');

  @override
  void setBlendColor(Vector4 color) => _passOnly('setBlendColor');

  @override
  void setStencilReference(int value) => _passOnly('setStencilReference');

  @override
  void beginOcclusionQuery(int queryIndex) => _passOnly('beginOcclusionQuery');

  @override
  void endOcclusionQuery() => _passOnly('endOcclusionQuery');

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) =>
      _passOnly('beginPipelineStatisticsQuery');

  @override
  void endPipelineStatisticsQuery() => _passOnly('endPipelineStatisticsQuery');

  @override
  void executeBundles(List<RenderBundle> bundles) =>
      _passOnly('executeBundles');

  // ------------------------------------------------- state, gated now

  @override
  void setPrimitiveType(PrimitiveType type) =>
      _record((PassEncoder p) => p.setPrimitiveType(type));

  @override
  void setPolygonMode(PolygonMode mode) {
    webglGatePolygonMode(mode);
    _record((PassEncoder p) => p.setPolygonMode(mode));
  }

  @override
  void setCullMode(CullMode mode) =>
      _record((PassEncoder p) => p.setCullMode(mode));

  @override
  void setWindingOrder(WindingOrder order) =>
      _record((PassEncoder p) => p.setWindingOrder(order));

  @override
  void setDepthWrite({required bool enabled}) =>
      _record((PassEncoder p) => p.setDepthWrite(enabled: enabled));

  @override
  void setDepthCompare(CompareFunction compare) =>
      _record((PassEncoder p) => p.setDepthCompare(compare));

  @override
  void setStencil(StencilState front, {StencilState? back}) =>
      _record((PassEncoder p) => p.setStencil(front, back: back));

  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    webglGateBlend(_device, state);
    _record((PassEncoder p) => p.setBlend(state, attachment: attachment));
  }

  @override
  void setAlphaToCoverage({required bool enabled}) =>
      _record((PassEncoder p) => p.setAlphaToCoverage(enabled: enabled));

  @override
  void setDepthBias(DepthBias bias) {
    webglGateDepthBias(_device, bias);
    _record((PassEncoder p) => p.setDepthBias(bias));
  }

  @override
  void setColorWriteMask(ColorWriteMask mask, {int attachment = 0}) {
    _device.features.require(
      DeviceFeature.colorWriteMask,
      backend: webglBackendName,
    );
    _record(
      (PassEncoder p) => p.setColorWriteMask(mask, attachment: attachment),
    );
  }

  @override
  void setDepthClamp({required bool enabled}) {
    webglGateDepthClamp(_device);
    _record((PassEncoder p) => p.setDepthClamp(enabled: enabled));
  }

  // ------------------------------------------------- bindings

  @override
  void bindPipeline(PipelineHandle pipeline) =>
      _record((PassEncoder p) => p.bindPipeline(pipeline));

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) => _record(
    (PassEncoder p) => p.bindVertexBuffer(buffer, vertexCount, slot: slot),
  );

  /// The bytes are copied now: a caller may reuse its buffer the moment this
  /// returns, and the replay happens later.
  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) {
    final kept = _copy(bytes);
    _record((PassEncoder p) => p.bindVertexData(kept, vertexCount, slot: slot));
  }

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) =>
      _record((PassEncoder p) => p.bindIndexBuffer(buffer, type, indexCount));

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    final kept = _copy(bytes);
    _record((PassEncoder p) => p.bindIndexData(kept, type, indexCount));
  }

  /// Answered from what [shader] declares, which is what a pass checks
  /// beside its bound program; the replay binds it for real.
  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    _open();
    if (!_declaresBlock(shader, blockName)) return false;
    final kept = <String, Float32List>{
      for (final MapEntry(key: name, value: values) in members.entries)
        name: Float32List.fromList(values),
    };
    _record((PassEncoder p) => p.bindUniformBlock(shader, blockName, kept));
    return true;
  }

  @override
  bool bindUniformBytes(ShaderHandle shader, String blockName, ByteData bytes) {
    _device.features.require(
      DeviceFeature.uniformBytes,
      backend: webglBackendName,
    );
    _open();
    if (!_declaresBlock(shader, blockName)) return false;
    final kept = _copy(bytes);
    _record((PassEncoder p) => p.bindUniformBytes(shader, blockName, kept));
    return true;
  }

  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    webglGateSampler(_device, sampler);
    _open();
    if (!shader.mayBindSampler(slot) ||
        !(shader.backend as WebGlShader)
            .declaredIn(_gl)
            .samplers
            .contains(slot)) {
      return false;
    }
    _record(
      (PassEncoder p) => p.bindTexture(shader, slot, texture, sampler: sampler),
    );
    return true;
  }

  @override
  bool bindStorageBuffer(
    ShaderHandle shader,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) => webglRefuseRenderStageStorage();

  @override
  bool bindStorageTexture(
    ShaderHandle shader,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  }) => webglRefuseRenderStageStorage();

  @override
  void clearBindings() => _record((PassEncoder p) => p.clearBindings());

  // ------------------------------------------------- draws

  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) =>
      _record(
        (PassEncoder p) => p.draw(
          instanceCount: instanceCount,
          firstIndex: firstIndex,
          indexCount: indexCount,
        ),
      );

  @override
  void drawIndexed(IndexedDraw draw) {
    webglGateIndexedDraw(_device, draw);
    _record((PassEncoder p) => p.drawIndexed(draw));
  }

  @override
  void multiDraw(List<IndexedDraw> draws) {
    _device.features.require(
      DeviceFeature.multiDraw,
      backend: webglBackendName,
    );
    for (final draw in draws) {
      webglGateIndexedDraw(_device, draw);
    }
    final kept = List<IndexedDraw>.unmodifiable(draws);
    _record((PassEncoder p) => p.multiDraw(kept));
  }

  @override
  void drawNonIndexed({
    required int vertexCount,
    int firstVertex = 0,
    int instanceCount = 1,
    int firstInstance = 0,
  }) {
    webglGateNonIndexed(_device, firstInstance);
    _record(
      (PassEncoder p) => p.drawNonIndexed(
        vertexCount: vertexCount,
        firstVertex: firstVertex,
        instanceCount: instanceCount,
        firstInstance: firstInstance,
      ),
    );
  }

  @override
  void drawIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) =>
      webglRefuseIndirect(DeviceFeature.indirectDraw);

  @override
  void multiDrawIndirect(
    StorageBuffer arguments,
    int drawCount, {
    int offsetInBytes = 0,
    StorageBuffer? countBuffer,
    int countOffsetInBytes = 0,
  }) => webglRefuseIndirect(DeviceFeature.multiDrawIndirect);

  bool _declaresBlock(ShaderHandle shader, String block) =>
      shader.mayBindBlock(block) &&
      (shader.backend as WebGlShader).declaredIn(_gl).blocks.contains(block);

  static ByteData _copy(ByteData bytes) => ByteData.sublistView(
    Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    ),
  );
}
