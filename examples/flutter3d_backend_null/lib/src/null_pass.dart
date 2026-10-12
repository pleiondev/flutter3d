import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'null_device.dart';

/// A render pass of the null backend: it takes every state a pass takes,
/// refuses by name what the device does not report, and skips each draw,
/// reporting its pipeline as refused once.
///
/// **Only the members without a body are here.** Every feature-gated member
/// of [PassEncoder] (indirect draws, storage buffers, the blend constant,
/// bundles) has a default that refuses with the feature named, which is
/// this device's answer; a backend that has the feature overrides it.
final class NullPass extends PassEncoder with CommandEncoder {
  NullPass(this.device);

  final NullDevice device;

  PipelineHandle? _pipeline;
  bool _submitted = false;

  void _open(String operation) {
    if (_submitted) {
      throw StateError('$operation: the pass was already submitted');
    }
  }

  /// Refuses with [feature] named, unless the device reports it.
  void _need(DeviceFeature feature) =>
      device.features.require(feature, backend: NullDevice.name);

  @override
  void setViewport(ScreenRect rect) => _open('setViewport');

  @override
  void setScissor(ScreenRect rect) => _open('setScissor');

  @override
  void setPrimitiveType(PrimitiveType type) => _open('setPrimitiveType');

  /// A fill is taken; edges are refused, since this device reports no
  /// wireframe and a refused line mode is never quietly filled.
  @override
  void setPolygonMode(PolygonMode mode) {
    _open('setPolygonMode');
    if (mode == PolygonMode.line) _need(DeviceFeature.wireframe);
  }

  @override
  void setCullMode(CullMode mode) => _open('setCullMode');

  @override
  void setWindingOrder(WindingOrder order) => _open('setWindingOrder');

  @override
  void setDepthWrite({required bool enabled}) => _open('setDepthWrite');

  @override
  void setDepthCompare(CompareFunction compare) => _open('setDepthCompare');

  @override
  void setStencil(StencilState front, {StencilState? back}) =>
      _need(DeviceFeature.stencil);

  @override
  void setStencilReference(int value) => _need(DeviceFeature.stencil);

  /// A blend that reads the constant or a second output, or takes a minimum
  /// or a maximum, is refused by the feature it needs: the state answers
  /// which, so a blend a later release adds is refused here too.
  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    _open('setBlend');
    state?.checkFeatures(device.features, backend: NullDevice.name);
  }

  @override
  void bindPipeline(PipelineHandle pipeline) {
    _open('bindPipeline');
    debugCheckLive(pipeline, 'bindPipeline');
    _pipeline = pipeline;
  }

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) {
    _open('bindVertexBuffer');
    debugCheckLive(buffer, 'bindVertexBuffer');
  }

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      _open('bindVertexData');

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    _open('bindIndexBuffer');
    debugCheckLive(buffer, 'bindIndexBuffer');
  }

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) =>
      _open('bindIndexData');

  /// True: with no compiled stage there is nothing to reflect, so every
  /// block is taken, as a backend without reflection takes it.
  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    _open('bindUniformBlock');
    return true;
  }

  /// True, for the reason [bindUniformBlock] gives. A sampler asking for a
  /// comparison, a level clamp or a border is refused by the feature it
  /// needs, none of which this device reports; the sampler answers which,
  /// so a comparison alone is refused by the comparison.
  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    _open('bindTexture');
    debugCheckLive(texture, 'bindTexture');
    sampler?.checkFeatures(device.features, backend: NullDevice.name);
    return true;
  }

  @override
  void clearBindings() => _open('clearBindings');

  /// Skipped, and the pipeline reported refused the first time it draws:
  /// this device rasterises nothing, and no rebuild changes that.
  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) {
    _open('draw');
    final pipeline = _pipeline;
    if (pipeline == null) {
      throw StateError('draw: no pipeline is bound');
    }
    if (device.pipelineRefusals.isRefused(pipeline)) return;
    device.pipelineRefusals.report(
      pipeline,
      PipelineRefusedException(
        pipeline: pipeline.name,
        backend: NullDevice.name,
        reason: PipelineRefusalReason.other,
        detail: 'this backend rasterises nothing',
      ),
      retry: false,
    );
  }

  @override
  void submit() {
    _open('submit');
    _submitted = true;
  }
}

/// The null backend's copies: texture to texture, which it does at once,
/// and the rest refused by their features through [TransferEncoder]'s own
/// defaults, since it has no buffers.
final class NullTransfer extends TransferEncoder {
  NullTransfer(this.device);

  final NullDevice device;

  @override
  void copyTextureToTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    if (source.texture.format != destination.texture.format) {
      throw ArgumentError(
        'copyTextureToTexture: ${source.texture.format.name} into '
        '${destination.texture.format.name}; a copy keeps its format',
      );
    }
    for (var layer = 0; layer < depthOrArrayLayers; layer++) {
      device
          .texelsOf(destination.texture)
          .copyFrom(
            device.texelsOf(source.texture),
            from: TextureCopyLocation(
              source.texture,
              mipLevel: source.mipLevel,
              x: source.x,
              y: source.y,
              z: source.z + layer,
            ),
            to: TextureCopyLocation(
              destination.texture,
              mipLevel: destination.mipLevel,
              x: destination.x,
              y: destination.y,
              z: destination.z + layer,
            ),
            width: width,
            height: height,
          );
    }
  }

  @override
  void submit() {}
}
