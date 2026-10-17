/// A live device that answers as if it lacked some of its features —
/// since 1.0.0-rc.1+2.
///
/// **Why.** Every capability the engine branches on has a fallback: a pass
/// per view without `multiview`, the CPU without `compute`, a copy without
/// `bufferCopy`, nearest filtering without `float32Filterable`. A fallback
/// runs only on a machine that lacks the feature, and the machines a test
/// runs on mostly have it, so the branch that a phone or a browser takes is
/// the one nobody ran. [MaskedDevice] takes any device and removes features
/// from its answer, so the fallback runs on the machine at hand, CI
/// included, against the real device's pixels and bytes for everything the
/// mask leaves alone.
///
/// **What the mask covers.** The report (`features`, the `limits` a
/// removed feature zeroes, `textureFormatSupport` for the format-table
/// features, `preferredSampleCount`, `shareableKinds`) and the refusal of
/// every call a masked feature gates, at the device, in a render pass, a
/// compute pass and a transfer pass, with the descriptors' own
/// `checkFeatures` asked against the masked set. The capability honesty
/// check of the conformance suite holds a mask to the same rule as a
/// backend: what it removes is refused by name, what it keeps works.
///
/// **What it does not cover**, by design: the shader-language features
/// (`shaderF16`, `subgroups`, `clipDistances`), which a bundle compiled
/// with them carries and only the device's own `loadShaders` can refuse; a
/// render bundle's encoder, which is the inner device's; and the type
/// capabilities a device mixes in (`EncodedImageUpload`,
/// `PlatformTextures`), which the mask does not carry, so a caller takes
/// the path for a device without them. `SynchronousBufferReadback` is
/// carried exactly when the inner device has it and the mask keeps
/// `synchronousReadback`.
///
/// **A member a minor adds to `GraphicsDevice` or an encoder is forwarded
/// here in the same change**, gated by its feature. Left out, the mask
/// would answer with the base class's refusing default and hide a call the
/// inner device has; the honesty test through the mask
/// (`flutter3d_cpu/test/masked_device_conformance_test.dart`) is what
/// notices.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor;

import 'capabilities.dart';
import 'command_encoder.dart';
import 'compute.dart';
import 'compute_checks.dart';
import 'formats.dart';
import 'geometry_buffer.dart';
import 'gpu_timings.dart';
import 'graphics_device.dart';
import 'pipeline_descriptor.dart';
import 'pipeline_refusal.dart';
import 'resources.dart';
import 'sampler.dart';
import 'shader.dart';
import 'sharing.dart';
import 'synchronous_readback.dart';
import 'texture.dart';
import 'transfer.dart';
import 'vertex_layout_spec.dart';

/// The float formats `float32Filterable`, `float32Renderable` and
/// `float32Blendable` speak for.
const Set<TextureFormat> _float32 = <TextureFormat>{
  TextureFormat.r32Float,
  TextureFormat.r32g32Float,
  TextureFormat.r32g32b32a32Float,
};

/// The formats each compression family's feature speaks for.
const Map<DeviceFeature, Set<TextureFormat>> _families =
    <DeviceFeature, Set<TextureFormat>>{
      DeviceFeature.textureCompressionBC: <TextureFormat>{
        TextureFormat.bc1RGBAUNormInt,
        TextureFormat.bc1RGBAUNormIntSRGB,
        TextureFormat.bc3RGBAUNormInt,
        TextureFormat.bc3RGBAUNormIntSRGB,
        TextureFormat.bc5RGUNormInt,
        TextureFormat.bc7RGBAUNormInt,
        TextureFormat.bc7RGBAUNormIntSRGB,
      },
      DeviceFeature.textureCompressionETC2: <TextureFormat>{
        TextureFormat.etc2RGB8UNormInt,
        TextureFormat.etc2RGB8UNormIntSRGB,
        TextureFormat.etc2RGBA8UNormInt,
        TextureFormat.etc2RGBA8UNormIntSRGB,
      },
      DeviceFeature.textureCompressionASTC: <TextureFormat>{
        TextureFormat.astc4x4LDR,
        TextureFormat.astc4x4LDRSRGB,
        TextureFormat.astc8x8LDR,
        TextureFormat.astc8x8LDRSRGB,
      },
      DeviceFeature.textureCompressionASTCHdr: <TextureFormat>{
        TextureFormat.astc4x4HDR,
        TextureFormat.astc8x8HDR,
      },
    };

/// [inner], answering as if it lacked [MaskedDevice.disabledFeatures].
///
/// Disposing the mask disposes [inner]: the mask is the device the caller
/// holds. Handles are [inner]'s, so a texture made through the mask is
/// released by [inner] whichever of the two is asked.
final class MaskedDevice extends GraphicsDevice {
  /// [inner] without [disabledFeatures]. A feature [inner] does not have,
  /// or a reserved one, may be named and changes nothing.
  ///
  /// The answer is a device that mixes in `SynchronousBufferReadback` only
  /// when [inner] does and the mask keeps `synchronousReadback`, so a
  /// caller asking with `is` gets the masked answer too.
  factory MaskedDevice(
    GraphicsDevice inner, {
    required Iterable<DeviceFeature> disabledFeatures,
  }) {
    final disabled = Set<DeviceFeature>.unmodifiable(disabledFeatures);
    return inner is SynchronousBufferReadback &&
            !disabled.contains(DeviceFeature.synchronousReadback)
        ? _MaskedReadbackDevice._(inner, disabled)
        : MaskedDevice._(inner, disabled);
  }

  MaskedDevice._(this.inner, this.disabledFeatures)
    : features = inner.features.without(<DeviceFeature>{
        ...disabledFeatures,
        for (final feature in disabledFeatures) ...?_implied[feature],
      });

  /// What cannot stay once a feature goes, by what the features mean: a
  /// format nothing renders into blends nothing.
  static const Map<DeviceFeature, List<DeviceFeature>> _implied =
      <DeviceFeature, List<DeviceFeature>>{
        DeviceFeature.float32Renderable: <DeviceFeature>[
          DeviceFeature.float32Blendable,
        ],
      };

  /// The device every call that is not refused goes through to.
  final GraphicsDevice inner;

  /// What this mask removes from [inner]'s answer, as it was asked.
  final Set<DeviceFeature> disabledFeatures;

  /// [inner]'s features without [disabledFeatures], and without what a
  /// disabled feature cannot be had without: `float32Blendable` goes with
  /// `float32Renderable`.
  @override
  final DeviceFeatures features;

  bool _off(DeviceFeature feature) => !features.has(feature);

  void _require(DeviceFeature feature) => features.require(
    feature,
    backend: backendName,
    reason: disabledFeatures.contains(feature) ? _reason : null,
  );

  static const String _reason = 'masked by a MaskedDevice';

  // ------------------------------------------------------------- identity

  /// [inner]'s, so a refusal names the device it came from.
  @override
  String get backendName => inner.backendName;

  /// [inner]'s: a mask is not another backend.
  @override
  String get backendId => inner.backendId;

  @override
  bool get isSoftware => inner.isSoftware;

  @override
  Stream<DeviceLoss> get lost => inner.lost;

  @override
  bool get isLost => inner.isLost;

  @override
  Stream<DeviceError> get errors => inner.errors;

  @override
  PipelineRefusals get pipelineRefusals => inner.pipelineRefusals;

  @override
  void setLabel(Object resource, String label) =>
      inner.setLabel(resource, label);

  @override
  String? labelOf(Object resource) => inner.labelOf(resource);

  // ---------------------------------------------------------------- report

  /// [inner]'s limits, with what a removed feature takes along: the
  /// compute limits without `compute`, one sample without
  /// `offscreenMultisample`, no views without `multiview`.
  @override
  DeviceLimits get limits {
    final l = inner.limits;
    final map = l.toMap();
    final noCompute = _off(DeviceFeature.compute);
    int pick(String name, {required bool zero, int to = 0}) =>
        zero ? to : map[name]!;
    return DeviceLimits(
      maxTextureDimension1D: l.maxTextureDimension1D,
      maxTextureDimension2D: l.maxTextureDimension2D,
      maxTextureDimension3D: l.maxTextureDimension3D,
      maxTextureArrayLayers: l.maxTextureArrayLayers,
      maxColorAttachments: l.maxColorAttachments,
      maxColorAttachmentBytesPerSample: l.maxColorAttachmentBytesPerSample,
      maxSampleCount: pick(
        'maxSampleCount',
        zero: _off(DeviceFeature.offscreenMultisample),
        to: 1,
      ),
      maxSamplerAnisotropy: l.maxSamplerAnisotropy,
      maxBindGroups: l.maxBindGroups,
      maxSampledTexturesPerShaderStage: l.maxSampledTexturesPerShaderStage,
      maxSamplersPerShaderStage: l.maxSamplersPerShaderStage,
      maxStorageBuffersPerShaderStage: l.maxStorageBuffersPerShaderStage,
      maxStorageTexturesPerShaderStage: l.maxStorageTexturesPerShaderStage,
      maxUniformBuffersPerShaderStage: l.maxUniformBuffersPerShaderStage,
      maxUniformBufferBindingSize: l.maxUniformBufferBindingSize,
      maxStorageBufferBindingSize: l.maxStorageBufferBindingSize,
      maxBufferSize: l.maxBufferSize,
      minUniformBufferOffsetAlignment: l.minUniformBufferOffsetAlignment,
      minStorageBufferOffsetAlignment: l.minStorageBufferOffsetAlignment,
      maxVertexBuffers: l.maxVertexBuffers,
      maxVertexAttributes: l.maxVertexAttributes,
      maxVertexBufferArrayStride: l.maxVertexBufferArrayStride,
      maxInterStageShaderVariables: l.maxInterStageShaderVariables,
      maxComputeWorkgroupStorageSize: pick(
        'maxComputeWorkgroupStorageSize',
        zero: noCompute,
      ),
      maxComputeInvocationsPerWorkgroup: pick(
        'maxComputeInvocationsPerWorkgroup',
        zero: noCompute,
      ),
      maxComputeWorkgroupSizeX: pick(
        'maxComputeWorkgroupSizeX',
        zero: noCompute,
      ),
      maxComputeWorkgroupSizeY: pick(
        'maxComputeWorkgroupSizeY',
        zero: noCompute,
      ),
      maxComputeWorkgroupSizeZ: pick(
        'maxComputeWorkgroupSizeZ',
        zero: noCompute,
      ),
      maxComputeWorkgroupsPerDimension: pick(
        'maxComputeWorkgroupsPerDimension',
        zero: noCompute,
      ),
      maxImmediateDataSize: l.maxImmediateDataSize,
      maxMultiviewViews: pick(
        'maxMultiviewViews',
        zero: _off(DeviceFeature.multiview),
      ),
    );
  }

  /// [inner]'s answer, with a masked compression family answering
  /// [TextureFormatSupport.none] and the masked float32 features taking
  /// their half of the 32-bit float formats' answer away.
  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) {
    for (final MapEntry(key: feature, value: formats) in _families.entries) {
      if (_off(feature) && formats.contains(format)) {
        return TextureFormatSupport.none;
      }
    }
    final s = inner.textureFormatSupport(format);
    if (!_float32.contains(format)) return s;
    final renderable = s.renderable && !_off(DeviceFeature.float32Renderable);
    return TextureFormatSupport(
      sampled: s.sampled,
      filterable: s.filterable && !_off(DeviceFeature.float32Filterable),
      renderable: renderable,
      blendable:
          renderable && s.blendable && !_off(DeviceFeature.float32Blendable),
      multisample: renderable && s.multisample,
      resolve: renderable && s.resolve,
      depthStencil: s.depthStencil,
      storage: s.storage,
      storageReadWrite: s.storageReadWrite,
    );
  }

  @override
  int get preferredSampleCount =>
      _off(DeviceFeature.offscreenMultisample) ? 1 : inner.preferredSampleCount;

  @override
  TextureFormat get defaultColorFormat => inner.defaultColorFormat;

  @override
  TextureFormat get defaultDepthStencilFormat =>
      inner.defaultDepthStencilFormat;

  @override
  TextureFormat get hdrColorFormat => inner.hdrColorFormat;

  @override
  List<TextureFormat> get hdrOutputFormats => inner.hdrOutputFormats;

  @override
  FramebufferOrigin get framebufferOrigin => inner.framebufferOrigin;

  @override
  DepthRange get depthRange => inner.depthRange;

  @override
  ShaderLibrary get shaders => inner.shaders;

  /// [inner]'s timings, or none at all without `gpuTimestamps`.
  @override
  void onGpuTimings(void Function(GpuFrameTimings timings)? listener) =>
      inner.onGpuTimings(_off(DeviceFeature.gpuTimestamps) ? null : listener);

  // ------------------------------------------------------------- textures

  /// Refuses a format whose masked answer cannot hold what is asked: a
  /// masked compression family at all, a masked float32 render target.
  void _checkFormat(TextureFormat format, {required bool target}) {
    for (final MapEntry(key: feature, value: formats) in _families.entries) {
      if (formats.contains(format)) _require(feature);
    }
    if (target && _float32.contains(format)) {
      _require(DeviceFeature.float32Renderable);
    }
  }

  @override
  TextureHandle createTexture(TextureDescriptor descriptor) {
    descriptor.checkFeatures(features, backend: backendName);
    _checkFormat(
      descriptor.format,
      target: descriptor.usage.contains(TextureUsage.renderTarget),
    );
    return inner.createTexture(descriptor);
  }

  @override
  void releaseTexture(TextureHandle texture) => inner.releaseTexture(texture);

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    _checkFormat(format, target: false);
    return inner.createTextureFromPixels(
      width: width,
      height: height,
      format: format,
      pixels: pixels,
      mipLevels: mipLevels,
    );
  }

  @override
  TextureHandle createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) {
    _require(DeviceFeature.cubeTextures);
    _checkFormat(format, target: false);
    return inner.createCubeTextureFromPixels(
      size: size,
      format: format,
      faces: faces,
      mipLevels: mipLevels,
    );
  }

  @override
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) {
    _require(DeviceFeature.cubeTextures);
    if (mipLevels > 1) _require(DeviceFeature.renderToMipLevel);
    _checkFormat(format, target: true);
    return inner.createCubeRenderTarget(
      size: size,
      format: format,
      mipLevels: mipLevels,
    );
  }

  @override
  Future<void> overwriteTexture(
    TextureHandle target,
    ByteData rgba, {
    ScreenRect? region,
    int mipLevel = 0,
  }) =>
      inner.overwriteTexture(target, rgba, region: region, mipLevel: mipLevel);

  @override
  void writeTexture(
    TextureHandle target,
    ByteData data, {
    TextureRegion? region,
    int mipLevel = 0,
    int? bytesPerRow,
  }) {
    _require(DeviceFeature.textureWrites);
    inner.writeTexture(
      target,
      data,
      region: region,
      mipLevel: mipLevel,
      bytesPerRow: bytesPerRow,
    );
  }

  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) =>
      inner.readback(texture, region: region);

  @override
  void releaseSampler(SamplerDescriptor sampler) =>
      inner.releaseSampler(sampler);

  // ------------------------------------------------------------- geometry

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) =>
      inner.uploadGeometry(bytes, usage);

  @override
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  ) => inner.overwriteGeometry(target, offsetInBytes, bytes);

  @override
  void releaseGeometry(GeometryBuffer geometry) =>
      inner.releaseGeometry(geometry);

  // ------------------------------------------------------------- shaders

  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) =>
      inner.loadShaders(bytes);

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) => inner.createPipeline(vertex, fragment, layout: layout);

  @override
  Future<PipelineHandle> createPipelineAsync(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) => inner.createPipelineAsync(vertex, fragment, layout: layout);

  @override
  PipelineHandle createPipelineFrom(PipelineDescriptor descriptor) =>
      inner.createPipelineFrom(descriptor);

  @override
  Future<PipelineHandle> createPipelineFromAsync(
    PipelineDescriptor descriptor,
  ) => inner.createPipelineFromAsync(descriptor);

  @override
  void releasePipeline(PipelineHandle pipeline) =>
      inner.releasePipeline(pipeline);

  // --------------------------------------------------------------- frames

  @override
  void beginFrame() => inner.beginFrame();

  @override
  void onFrameComplete(void Function() whenDone) =>
      inner.onFrameComplete(whenDone);

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    descriptor
      ..checkFeatures(features, backend: backendName)
      ..checkAttachmentLimit(limits.maxColorAttachments, backend: backendName);
    return _MaskedPass(this, inner.beginRenderPass(descriptor));
  }

  @override
  RenderBundleEncoder createRenderBundleEncoder(
    RenderBundleDescriptor descriptor,
  ) {
    _require(DeviceFeature.renderBundles);
    return inner.createRenderBundleEncoder(descriptor);
  }

  @override
  void releaseRenderBundle(RenderBundle bundle) =>
      inner.releaseRenderBundle(bundle);

  @override
  TransferEncoder beginTransferPass({String? label}) =>
      _MaskedTransfer(this, inner.beginTransferPass(label: label));

  /// Disposes [inner].
  @override
  void dispose() => inner.dispose();

  // -------------------------------------------------------------- compute

  @override
  ComputePipelineHandle createComputePipeline(ShaderHandle shader) {
    _require(DeviceFeature.compute);
    return inner.createComputePipeline(shader);
  }

  @override
  Future<ComputePipelineHandle> createComputePipelineAsync(
    ShaderHandle shader,
  ) async {
    _require(DeviceFeature.compute);
    return inner.createComputePipelineAsync(shader);
  }

  @override
  ComputePipelineHandle createComputePipelineFrom(
    ComputePipelineDescriptor descriptor,
  ) {
    _require(DeviceFeature.compute);
    return inner.createComputePipelineFrom(descriptor);
  }

  @override
  Future<ComputePipelineHandle> createComputePipelineFromAsync(
    ComputePipelineDescriptor descriptor,
  ) async {
    _require(DeviceFeature.compute);
    return inner.createComputePipelineFromAsync(descriptor);
  }

  @override
  void releaseComputePipeline(ComputePipelineHandle pipeline) =>
      inner.releaseComputePipeline(pipeline);

  @override
  ComputeEncoder beginComputePass({
    String? label,
    PassTimestampWrites? timestampWrites,
  }) {
    _require(DeviceFeature.compute);
    if (timestampWrites != null) _require(DeviceFeature.timestampQuery);
    return _MaskedCompute(
      this,
      inner.beginComputePass(label: label, timestampWrites: timestampWrites),
    );
  }

  // -------------------------------------------------------------- buffers

  @override
  StorageBuffer createBuffer(
    BufferDescriptor descriptor, {
    ByteData? contents,
  }) {
    descriptor.checkFeatures(features, backend: backendName);
    return inner.createBuffer(descriptor, contents: contents);
  }

  @override
  void writeBuffer(StorageBuffer target, int offsetInBytes, ByteData bytes) {
    _require(DeviceFeature.buffers);
    inner.writeBuffer(target, offsetInBytes, bytes);
  }

  /// Refused without both `compute` and `buffers`, either of which makes a
  /// buffer the host may read.
  @override
  Future<ByteData> readBuffer(StorageBuffer buffer) async {
    if (_off(DeviceFeature.compute)) _require(DeviceFeature.buffers);
    return inner.readBuffer(buffer);
  }

  @override
  Future<MappedBuffer> mapBuffer(
    StorageBuffer buffer,
    MapMode mode, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) async {
    _require(DeviceFeature.mappedBuffers);
    return inner.mapBuffer(
      buffer,
      mode,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
  }

  @override
  void releaseStorageBuffer(StorageBuffer buffer) =>
      inner.releaseStorageBuffer(buffer);

  // -------------------------------------------------------------- queries

  @override
  QuerySet createQuerySet(QueryType type, int count) {
    _require(type.feature);
    return inner.createQuerySet(type, count);
  }

  @override
  Future<List<int>> readQueryResults(
    QuerySet querySet, {
    int first = 0,
    int? count,
  }) async {
    _require(querySet.type.feature);
    return inner.readQueryResults(querySet, first: first, count: count);
  }

  @override
  void releaseQuerySet(QuerySet querySet) => inner.releaseQuerySet(querySet);

  // -------------------------------------------------------------- sharing

  /// [inner]'s kinds, or none once every sharing feature is masked.
  @override
  Set<NativeHandleKind> get shareableKinds =>
      _off(DeviceFeature.sharedTextures) &&
          _off(DeviceFeature.sharedBuffers) &&
          _off(DeviceFeature.sharedFences)
      ? const <NativeHandleKind>{}
      : inner.shareableKinds;

  @override
  NativeHandle exportTexture(TextureHandle texture, {NativeHandleKind? kind}) {
    _require(DeviceFeature.sharedTextures);
    return inner.exportTexture(texture, kind: kind);
  }

  @override
  TextureHandle importTexture(
    NativeHandle handle,
    TextureDescriptor descriptor,
  ) {
    _require(DeviceFeature.sharedTextures);
    return inner.importTexture(handle, descriptor);
  }

  @override
  NativeHandle exportBuffer(StorageBuffer buffer, {NativeHandleKind? kind}) {
    _require(DeviceFeature.sharedBuffers);
    return inner.exportBuffer(buffer, kind: kind);
  }

  @override
  StorageBuffer importBuffer(NativeHandle handle, BufferDescriptor descriptor) {
    _require(DeviceFeature.sharedBuffers);
    return inner.importBuffer(handle, descriptor);
  }

  @override
  GpuFence createFence() {
    _require(DeviceFeature.sharedFences);
    return inner.createFence();
  }

  @override
  void signalFence(GpuFence fence, int value) {
    _require(DeviceFeature.sharedFences);
    inner.signalFence(fence, value);
  }

  @override
  void waitFence(GpuFence fence, int value) {
    _require(DeviceFeature.sharedFences);
    inner.waitFence(fence, value);
  }

  @override
  NativeHandle exportFence(GpuFence fence, {NativeHandleKind? kind}) {
    _require(DeviceFeature.sharedFences);
    return inner.exportFence(fence, kind: kind);
  }

  @override
  GpuFence importFence(NativeHandle handle) {
    _require(DeviceFeature.sharedFences);
    return inner.importFence(handle);
  }

  @override
  void releaseFence(GpuFence fence) => inner.releaseFence(fence);

  @override
  String toString() =>
      'MaskedDevice($backendName without '
      '${disabledFeatures.map((DeviceFeature f) => f.name).join(', ')})';
}

/// The mask over a device that reads buffers in the calling turn, keeping
/// `synchronousReadback`.
final class _MaskedReadbackDevice extends MaskedDevice
    with SynchronousBufferReadback {
  _MaskedReadbackDevice._(super.inner, super.disabledFeatures) : super._();

  @override
  ByteData readBufferSync(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) => (inner as SynchronousBufferReadback).readBufferSync(
    buffer,
    offsetInBytes: offsetInBytes,
    sizeInBytes: sizeInBytes,
  );
}

/// A render pass of [_device]'s, refusing what the mask removed before the
/// inner pass sees it.
final class _MaskedPass extends PassEncoder with CommandEncoder {
  _MaskedPass(this._device, this._inner);

  final MaskedDevice _device;
  final CommandEncoder _inner;

  DeviceFeatures get _features => _device.features;
  String get _backend => _device.backendName;
  bool _off(DeviceFeature feature) => _device._off(feature);
  void _require(DeviceFeature feature) => _device._require(feature);

  /// The attachment a call for [attachment] lands on: zero without
  /// `independentBlend`, as the contract says such a device does.
  int _attachment(int attachment) =>
      _off(DeviceFeature.independentBlend) ? 0 : attachment;

  @override
  void setViewport(PassViewport viewport) {
    viewport.checkFeatures(_features, backend: _backend);
    _inner.setViewport(viewport);
  }

  @override
  void setScissor(ScreenRect rect) => _inner.setScissor(rect);

  @override
  void setPrimitiveType(PrimitiveType type) {
    type.checkFeatures(_features, backend: _backend);
    _inner.setPrimitiveType(type);
  }

  @override
  void setPolygonMode(PolygonMode mode) {
    if (mode == PolygonMode.line) _require(DeviceFeature.wireframe);
    _inner.setPolygonMode(mode);
  }

  @override
  void setCullMode(CullMode mode) => _inner.setCullMode(mode);

  @override
  void setWindingOrder(WindingOrder order) => _inner.setWindingOrder(order);

  @override
  void setDepthWrite({required bool enabled}) =>
      _inner.setDepthWrite(enabled: enabled);

  @override
  void setDepthCompare(CompareFunction compare) =>
      _inner.setDepthCompare(compare);

  /// Refused without `stencil`, unless the state turns the test off.
  @override
  void setStencil(StencilState front, {StencilState? back}) {
    if (front != StencilState.disabled ||
        (back != null && back != StencilState.disabled)) {
      _require(DeviceFeature.stencil);
    }
    _inner.setStencil(front, back: back);
  }

  @override
  void setStencilReference(int value) => _inner.setStencilReference(value);

  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    state?.checkFeatures(_features, backend: _backend);
    _inner.setBlend(state, attachment: _attachment(attachment));
  }

  /// Ignored without `alphaToCoverage`, as the contract says such a device
  /// ignores it.
  @override
  void setAlphaToCoverage({required bool enabled}) {
    if (_off(DeviceFeature.alphaToCoverage)) return;
    _inner.setAlphaToCoverage(enabled: enabled);
  }

  @override
  void setBlendColor(LinearColor color) {
    _require(DeviceFeature.blendConstant);
    _inner.setBlendColor(color);
  }

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
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    type.checkFeatures(_features, backend: _backend);
    _inner.bindIndexBuffer(buffer, type, indexCount);
  }

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    type.checkFeatures(_features, backend: _backend);
    _inner.bindIndexData(bytes, type, indexCount);
  }

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
  }) {
    sampler?.checkFeatures(_features, backend: _backend);
    return _inner.bindTexture(shader, slot, texture, sampler: sampler);
  }

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
  void drawIndexed(IndexedDraw draw) {
    if (draw.usesBaseVertexOrInstance) {
      _require(DeviceFeature.baseVertexBaseInstance);
    }
    _inner.drawIndexed(draw);
  }

  @override
  void multiDraw(List<IndexedDraw> draws) {
    _require(DeviceFeature.multiDraw);
    if (draws.any((IndexedDraw d) => d.usesBaseVertexOrInstance)) {
      _require(DeviceFeature.baseVertexBaseInstance);
    }
    _inner.multiDraw(draws);
  }

  @override
  void multiDrawIndirect(
    StorageBuffer arguments,
    int drawCount, {
    int offsetInBytes = 0,
    StorageBuffer? countBuffer,
    int countOffsetInBytes = 0,
  }) {
    _require(DeviceFeature.multiDrawIndirect);
    _inner.multiDrawIndirect(
      arguments,
      drawCount,
      offsetInBytes: offsetInBytes,
      countBuffer: countBuffer,
      countOffsetInBytes: countOffsetInBytes,
    );
  }

  @override
  void executeBundles(List<RenderBundle> bundles) {
    _require(DeviceFeature.renderBundles);
    _inner.executeBundles(bundles);
  }

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) {
    _require(DeviceFeature.pipelineStatisticsQuery);
    _inner.beginPipelineStatisticsQuery(querySet, queryIndex);
  }

  @override
  void endPipelineStatisticsQuery() {
    _require(DeviceFeature.pipelineStatisticsQuery);
    _inner.endPipelineStatisticsQuery();
  }

  @override
  void setDepthBias(DepthBias bias) {
    bias.checkFeatures(_features, backend: _backend);
    _inner.setDepthBias(bias);
  }

  @override
  void setColorWriteMask(ColorWriteMask mask, {int attachment = 0}) {
    _require(DeviceFeature.colorWriteMask);
    _inner.setColorWriteMask(mask, attachment: _attachment(attachment));
  }

  @override
  void setDepthClamp({required bool enabled}) {
    _require(DeviceFeature.depthClamp);
    _inner.setDepthClamp(enabled: enabled);
  }

  @override
  bool bindStorageBuffer(
    ShaderHandle shader,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    _require(DeviceFeature.renderStageStorage);
    return _inner.bindStorageBuffer(
      shader,
      name,
      buffer,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
  }

  @override
  bool bindStorageTexture(
    ShaderHandle shader,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  }) {
    _require(DeviceFeature.renderStageStorage);
    if (access == StorageTextureAccess.readWrite) {
      _require(DeviceFeature.readWriteStorageTextures);
    }
    return _inner.bindStorageTexture(
      shader,
      name,
      texture,
      mipLevel: mipLevel,
      access: access,
    );
  }

  @override
  bool bindUniformBytes(ShaderHandle shader, String blockName, ByteData bytes) {
    _require(DeviceFeature.uniformBytes);
    return _inner.bindUniformBytes(shader, blockName, bytes);
  }

  @override
  bool bindUniformBuffer(
    ShaderHandle stage,
    String blockName,
    StorageBuffer buffer,
    int offsetInBytes,
    int sizeInBytes,
  ) {
    _require(DeviceFeature.uniformBuffers);
    return _inner.bindUniformBuffer(
      stage,
      blockName,
      buffer,
      offsetInBytes,
      sizeInBytes,
    );
  }

  @override
  void drawIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) {
    _require(DeviceFeature.indirectDraw);
    _inner.drawIndirect(arguments, offsetInBytes: offsetInBytes);
  }

  @override
  void drawNonIndexed({
    required int vertexCount,
    int firstVertex = 0,
    int instanceCount = 1,
    int firstInstance = 0,
  }) {
    _require(DeviceFeature.nonIndexedDraw);
    if (firstInstance != 0) _require(DeviceFeature.baseVertexBaseInstance);
    _inner.drawNonIndexed(
      vertexCount: vertexCount,
      firstVertex: firstVertex,
      instanceCount: instanceCount,
      firstInstance: firstInstance,
    );
  }

  @override
  void beginOcclusionQuery(int queryIndex) {
    _require(DeviceFeature.occlusionQuery);
    _inner.beginOcclusionQuery(queryIndex);
  }

  @override
  void endOcclusionQuery() {
    _require(DeviceFeature.occlusionQuery);
    _inner.endOcclusionQuery();
  }

  @override
  void pushDebugGroup(String label) => _inner.pushDebugGroup(label);

  @override
  void popDebugGroup() => _inner.popDebugGroup();

  @override
  void insertDebugMarker(String label) => _inner.insertDebugMarker(label);

  @override
  void submit() => _inner.submit();
}

/// A compute pass of [_device]'s.
final class _MaskedCompute extends ComputeEncoder {
  _MaskedCompute(this._device, this._inner);

  final MaskedDevice _device;
  final ComputeEncoder _inner;

  void _require(DeviceFeature feature) => _device._require(feature);

  @override
  void bindPipeline(ComputePipelineHandle pipeline) =>
      _inner.bindPipeline(pipeline);

  @override
  bool bindStorageBuffer(
    ShaderHandle stage,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    // Against the masked limits, which a caller sized its work from.
    checkStorageBinding(
      buffer,
      _device.limits,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
    return _inner.bindStorageBuffer(
      stage,
      name,
      buffer,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
  }

  @override
  bool bindTexture(
    ShaderHandle stage,
    String name,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    sampler?.checkFeatures(_device.features, backend: _device.backendName);
    return _inner.bindTexture(stage, name, texture, sampler: sampler);
  }

  @override
  bool bindStorageTexture(
    ShaderHandle stage,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  }) {
    _require(DeviceFeature.storageTextures);
    if (access == StorageTextureAccess.readWrite) {
      _require(DeviceFeature.readWriteStorageTextures);
    }
    return _inner.bindStorageTexture(
      stage,
      name,
      texture,
      mipLevel: mipLevel,
      access: access,
    );
  }

  @override
  bool bindUniformBytes(ShaderHandle stage, String block, ByteData bytes) {
    _require(DeviceFeature.uniformBytes);
    return _inner.bindUniformBytes(stage, block, bytes);
  }

  @override
  bool bindUniformBlock(
    ShaderHandle stage,
    String block,
    Map<String, Float32List> members,
  ) => _inner.bindUniformBlock(stage, block, members);

  @override
  void dispatch(int x, [int y = 1, int z = 1]) {
    checkDispatch(_device.limits, x, y, z);
    _inner.dispatch(x, y, z);
  }

  @override
  void dispatchIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) {
    _require(DeviceFeature.indirectDispatch);
    _inner.dispatchIndirect(arguments, offsetInBytes: offsetInBytes);
  }

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) {
    _require(DeviceFeature.pipelineStatisticsQuery);
    _inner.beginPipelineStatisticsQuery(querySet, queryIndex);
  }

  @override
  void endPipelineStatisticsQuery() {
    _require(DeviceFeature.pipelineStatisticsQuery);
    _inner.endPipelineStatisticsQuery();
  }

  @override
  void pushDebugGroup(String label) => _inner.pushDebugGroup(label);

  @override
  void popDebugGroup() => _inner.popDebugGroup();

  @override
  void insertDebugMarker(String label) => _inner.insertDebugMarker(label);

  @override
  void submit() => _inner.submit();
}

/// A transfer pass of [_device]'s.
final class _MaskedTransfer extends TransferEncoder {
  _MaskedTransfer(this._device, this._inner);

  final MaskedDevice _device;
  final TransferEncoder _inner;

  void _require(DeviceFeature feature) => _device._require(feature);

  @override
  void copyBufferToBuffer(
    StorageBuffer source,
    int sourceOffset,
    StorageBuffer destination,
    int destinationOffset,
    int size,
  ) {
    _require(DeviceFeature.bufferCopy);
    _inner.copyBufferToBuffer(
      source,
      sourceOffset,
      destination,
      destinationOffset,
      size,
    );
  }

  @override
  void clearBuffer(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    _require(DeviceFeature.bufferCopy);
    _inner.clearBuffer(
      buffer,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
  }

  @override
  void copyTextureToTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    _require(DeviceFeature.textureCopy);
    _inner.copyTextureToTexture(
      source,
      destination,
      width: width,
      height: height,
      depthOrArrayLayers: depthOrArrayLayers,
    );
  }

  @override
  void copyBufferToTexture(
    StorageBuffer source,
    BufferTextureLayout layout,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    _require(DeviceFeature.bufferTextureCopy);
    _inner.copyBufferToTexture(
      source,
      layout,
      destination,
      width: width,
      height: height,
      depthOrArrayLayers: depthOrArrayLayers,
    );
  }

  @override
  void copyTextureToBuffer(
    TextureCopyLocation source,
    StorageBuffer destination,
    BufferTextureLayout layout, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    _require(DeviceFeature.bufferTextureCopy);
    _inner.copyTextureToBuffer(
      source,
      destination,
      layout,
      width: width,
      height: height,
      depthOrArrayLayers: depthOrArrayLayers,
    );
  }

  @override
  void resolveTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination,
  ) {
    _require(DeviceFeature.offscreenMultisample);
    _inner.resolveTexture(source, destination);
  }

  @override
  void pushDebugGroup(String label) => _inner.pushDebugGroup(label);

  @override
  void popDebugGroup() => _inner.popDebugGroup();

  @override
  void insertDebugMarker(String label) => _inner.insertDebugMarker(label);

  @override
  void submit() => _inner.submit();
}
