/// A device that remembers everything asked of it — `H3`.
///
/// [RecordingDevice] decorates any [GraphicsDevice]: every call goes through
/// to the device underneath unchanged, and the call itself is kept as a
/// [TraceEvent] in [events]. Handed to a renderer in place of the real device,
/// it turns one frame into a trace that `replayTrace` can draw again on any
/// backend — the same frame on the software rasteriser and on WebGL2, or the
/// same frame before and after a change.
///
/// **Resources are named by the order they were made in.** A texture handle
/// or a buffer object means nothing in another process, so each one gets the
/// next number when it is created and every later event names it by that.
/// Geometry is keyed by its backend object rather than by the handle, because
/// a slice of a buffer is a new handle around the same object.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' show Vector4;

import '../capabilities.dart';
import '../command_encoder.dart';
import '../compute.dart';
import '../formats.dart';
import '../geometry_buffer.dart';
import '../gpu_timings.dart';
import '../graphics_device.dart';
import '../render_target_pool.dart';
import '../resources.dart';
import '../sampler.dart';
import '../shader.dart';
import '../texture.dart';
import '../transfer.dart';
import '../vertex_layout_spec.dart';
import 'trace_event.dart';

final class RecordingDevice extends GraphicsDevice
    with SynchronousBufferReadback {
  RecordingDevice(this.inner);

  /// The device every call goes through to.
  final GraphicsDevice inner;

  @override
  String get backendName => inner.backendName;

  @override
  Stream<DeviceLoss> get lost => inner.lost;

  @override
  bool get isLost => inner.isLost;

  /// Passed through, and written into the trace for a texture, a geometry
  /// buffer, a pipeline or a storage buffer the trace made, so a replay
  /// gives it the same label. Any other resource is passed through and
  /// listed in [unrecorded].
  @override
  void setLabel(Object resource, String label) {
    final named = switch (resource) {
      final TextureHandle texture => (
        TraceLabeled.texture,
        _textureIds[texture],
      ),
      final GeometryBuffer buffer => (
        TraceLabeled.geometry,
        _geometryIds[buffer.backend],
      ),
      final PipelineHandle pipeline => (
        TraceLabeled.pipeline,
        _pipelineIds[pipeline],
      ),
      final StorageBuffer buffer => (TraceLabeled.storage, _storageIds[buffer]),
      _ => null,
    };
    switch (named) {
      case (final kind, final int id):
        events.add(TraceSetLabel(resource: kind, id: id, label: label));
      default:
        _unrecorded('setLabel');
    }
    inner.setLabel(resource, label);
  }

  @override
  String? labelOf(Object resource) => inner.labelOf(resource);

  @override
  void releasePipeline(PipelineHandle pipeline) =>
      inner.releasePipeline(pipeline);

  @override
  void releaseSampler(SamplerDescriptor sampler) =>
      inner.releaseSampler(sampler);

  /// What was asked, in order.
  final List<TraceEvent> events = <TraceEvent>[];

  final Map<Object, int> _geometryIds = <Object, int>{};
  final Map<Object, int> _textureIds = <Object, int>{};
  final Map<Object, int> _pipelineIds = <Object, int>{};
  final Map<Object, int> _storageIds = <Object, int>{};
  final Map<Object, int> _computePipelineIds = <Object, int>{};
  int _nextId = 0;
  int _nextPass = 0;

  /// Maps rather than expandos, because a backend object may be a string or
  /// a record — the fake's and the software rasteriser's are — and an expando
  /// takes neither. Equality rather than identity for the same reason: a
  /// record has no identity to key on. Everything a trace names is kept
  /// alive by it anyway.
  int _name(Map<Object, int> ids, Object key) => ids[key] ??= _nextId++;

  int _texture(TextureHandle texture) => _name(_textureIds, texture);

  /// Where each uploaded buffer started in its backend object. A slice is
  /// recorded relative to that, because another backend's upload may hand
  /// back the same bytes at a different offset into a buffer of its own.
  final Map<Object, int> _baseOffsets = <Object, int>{};

  TraceGeometryRange _range(GeometryBuffer buffer) => (
    buffer: _name(_geometryIds, buffer.backend),
    offset: buffer.offsetInBytes - (_baseOffsets[buffer.backend] ?? 0),
    length: buffer.lengthInBytes,
  );

  static ByteData _copy(ByteData bytes) => ByteData.sublistView(
    Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    ),
  );

  static Map<String, Float32List> _copyMembers(
    Map<String, Float32List> members,
  ) => <String, Float32List>{
    for (final MapEntry(:key, :value) in members.entries)
      key: Float32List.fromList(value),
  };

  // ---------------------------------------------------------- questions

  @override
  TextureFormat get defaultColorFormat => inner.defaultColorFormat;
  @override
  TextureFormat get defaultDepthStencilFormat =>
      inner.defaultDepthStencilFormat;
  @override
  FramebufferOrigin get framebufferOrigin => inner.framebufferOrigin;
  @override
  DepthRange get depthRange => inner.depthRange;
  @override
  TextureFormat get hdrColorFormat => inner.hdrColorFormat;
  @override
  int get preferredSampleCount => inner.preferredSampleCount;

  @override
  ShaderLibrary get shaders => inner.shaders;

  @override
  List<TextureFormat> get hdrOutputFormats => inner.hdrOutputFormats;
  @override
  void onGpuTimings(void Function(GpuFrameTimings timings)? listener) =>
      inner.onGpuTimings(listener);

  // ---------------------------------------------------------- resources

  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) {
    events.add(TraceLoadShaders(_copy(bytes)));
    return inner.loadShaders(bytes);
  }

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) {
    final pipeline = inner.createPipeline(vertex, fragment, layout: layout);
    events.add(
      TraceCreatePipeline(
        id: _name(_pipelineIds, pipeline),
        vertex: vertex.name,
        fragment: fragment.name,
        layout: layout,
      ),
    );
    return pipeline;
  }

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    final buffer = inner.uploadGeometry(bytes, usage);
    _baseOffsets[buffer.backend] = buffer.offsetInBytes;
    events.add(
      TraceUploadGeometry(
        id: _name(_geometryIds, buffer.backend),
        usage: usage,
        bytes: _copy(bytes),
      ),
    );
    return buffer;
  }

  @override
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  ) {
    events.add(
      TraceOverwriteGeometry(
        target: _range(target),
        offset: offsetInBytes,
        bytes: _copy(bytes),
      ),
    );
    inner.overwriteGeometry(target, offsetInBytes, bytes);
  }

  @override
  void releaseGeometry(GeometryBuffer geometry) {
    events.add(TraceReleaseGeometry(_range(geometry).buffer));
    inner.releaseGeometry(geometry);
  }

  /// A [RenderTargetDescriptor] is recorded; any other shape goes through
  /// unrecorded, as it did when it had a call of its own.
  @override
  TextureHandle createTexture(TextureDescriptor descriptor) {
    final texture = inner.createTexture(descriptor);
    if (descriptor is RenderTargetDescriptor) {
      events.add(TraceCreateTexture(id: _texture(texture), spec: descriptor));
    } else {
      _unrecorded('createTexture');
    }
    return texture;
  }

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    final texture = inner.createTextureFromPixels(
      width: width,
      height: height,
      format: format,
      pixels: pixels,
      mipLevels: mipLevels,
    );
    events.add(
      TraceCreateTextureFromPixels(
        id: _texture(texture),
        width: width,
        height: height,
        format: format,
        pixels: _copy(pixels),
        mipLevels: mipLevels?.map(_copy).toList(),
      ),
    );
    return texture;
  }

  @override
  TextureHandle createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) {
    final texture = inner.createCubeTextureFromPixels(
      size: size,
      format: format,
      faces: faces,
      mipLevels: mipLevels,
    );
    events.add(
      TraceCreateCubeTextureFromPixels(
        id: _texture(texture),
        size: size,
        format: format,
        faces: faces.map(_copy).toList(),
        mipLevels: mipLevels?.map((face) => face.map(_copy).toList()).toList(),
      ),
    );
    return texture;
  }

  @override
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) {
    final texture = inner.createCubeRenderTarget(
      size: size,
      format: format,
      mipLevels: mipLevels,
    );
    events.add(
      TraceCreateCubeRenderTarget(
        id: _texture(texture),
        size: size,
        format: format,
        mipLevels: mipLevels,
      ),
    );
    return texture;
  }

  @override
  Future<void> overwriteTexture(
    TextureHandle target,
    ByteData rgba, {
    ScreenRect? region,
    int mipLevel = 0,
  }) {
    events.add(
      TraceOverwriteTexture(
        texture: _texture(target),
        rgba: _copy(rgba),
        region: region,
        mipLevel: mipLevel,
      ),
    );
    return inner.overwriteTexture(
      target,
      rgba,
      region: region,
      mipLevel: mipLevel,
    );
  }

  @override
  void releaseTexture(TextureHandle texture) {
    events.add(TraceReleaseTexture(_texture(texture)));
    inner.releaseTexture(texture);
  }

  // -------------------------------------------------------------- frames

  @override
  void beginFrame() {
    events.add(const TraceBeginFrame());
    inner.beginFrame();
  }

  @override
  void onFrameComplete(void Function() whenDone) =>
      inner.onFrameComplete(whenDone);

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) {
    final pass = _nextPass++;
    // The trace's pass carries face and level but none of the 1.0 fields.
    final depth = descriptor.depth;
    if (descriptor.colors.any((ColorTarget c) => c.layer != 0) ||
        depth != null &&
            (depth.layer != 0 ||
                depth.face != 0 ||
                depth.mipLevel != 0 ||
                depth.depthReadOnly ||
                depth.stencilReadOnly) ||
        descriptor.occlusionQuerySet != null ||
        descriptor.timestampWrites != null) {
      _unrecorded('beginRenderPass descriptor fields');
    }
    events.add(
      TraceBeginRenderPass(
        pass: pass,
        label: descriptor.label,
        colors: <TraceColorTarget>[
          for (final c in descriptor.colors)
            (
              texture: _texture(c.texture),
              resolveTexture: c.resolveTexture == null
                  ? null
                  : _texture(c.resolveTexture!),
              loadAction: c.loadAction,
              storeAction: c.storeAction,
              clearValue: c.clearValue?.clone(),
              face: c.face,
              mipLevel: c.mipLevel,
            ),
        ],
        depth: switch (descriptor.depth) {
          null => null,
          final d => (
            texture: _texture(d.texture),
            clearValue: d.clearValue,
            loadAction: d.loadAction,
            storeAction: d.storeAction,
            stencilLoadAction: d.stencilLoadAction,
            stencilStoreAction: d.stencilStoreAction,
            stencilClearValue: d.stencilClearValue,
          ),
        },
      ),
    );
    return _RecordingEncoder(this, pass, inner.beginRenderPass(descriptor));
  }

  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) {
    events.add(TraceReadback(texture: _texture(texture), region: region));
    return inner.readback(texture, region: region);
  }

  @override
  void dispose() => inner.dispose();

  // ------------------------------------------------------------- compute

  @override
  StorageBuffer createStorageBuffer(
    ByteData bytes, {
    bool hostReadable = false,
    bool bindableAsIndices = false,
  }) {
    final buffer = inner.createStorageBuffer(
      bytes,
      hostReadable: hostReadable,
      bindableAsIndices: bindableAsIndices,
    );
    final indices = buffer.asIndices;
    events.add(
      TraceCreateStorageBuffer(
        id: _name(_storageIds, buffer),
        bytes: _copy(bytes),
        hostReadable: hostReadable,
        // Named as geometry, so a draw that binds it is recorded as one
        // binding any other index buffer — `H11`.
        indices: indices == null ? null : _name(_geometryIds, indices.backend),
      ),
    );
    return buffer;
  }

  @override
  void releaseStorageBuffer(StorageBuffer buffer) {
    events.add(TraceReleaseStorageBuffer(_name(_storageIds, buffer)));
    inner.releaseStorageBuffer(buffer);
  }

  @override
  ComputePipelineHandle createComputePipeline(ShaderHandle shader) {
    final pipeline = inner.createComputePipeline(shader);
    events.add(
      TraceCreateComputePipeline(
        _name(_computePipelineIds, pipeline),
        shader.name,
      ),
    );
    return pipeline;
  }

  @override
  ComputeEncoder beginComputePass({
    String? label,
    PassTimestampWrites? timestampWrites,
  }) {
    if (timestampWrites != null) {
      _unrecorded('beginComputePass.timestampWrites');
    }
    final encoder = inner.beginComputePass(
      label: label,
      timestampWrites: timestampWrites,
    );
    final pass = _nextPass++;
    events.add(TraceBeginComputePass(pass, label));
    return _RecordingComputeEncoder(this, pass, encoder);
  }

  @override
  Future<ByteData> readBuffer(StorageBuffer buffer) {
    events.add(TraceReadBuffer(_name(_storageIds, buffer)));
    return inner.readBuffer(buffer);
  }

  // ------------------------------------------------------------ since 1.0
  //
  // **Forwarded, and named in [unrecorded] rather than traced.** `TraceEvent`
  // is sealed and versioned with the trace format; giving every 1.0 call a
  // variant and a codec is its own change. Until then a recording that used
  // any of these says so: [unrecorded] lists each call by name, and a replay
  // of such a trace is known to be incomplete rather than silently so.

  /// The 1.0-surface calls this recording forwarded without tracing, in
  /// order. Empty for every frame the engine draws today.
  final List<String> unrecorded = <String>[];

  void _unrecorded(String call) => unrecorded.add(call);

  @override
  DeviceFeatures get features => inner.features;
  @override
  DeviceLimits get limits => inner.limits;
  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) =>
      inner.textureFormatSupport(format);

  @override
  void writeTexture(
    TextureHandle target,
    ByteData data, {
    TextureRegion? region,
    int mipLevel = 0,
    int? bytesPerRow,
  }) {
    _unrecorded('writeTexture');
    inner.writeTexture(
      target,
      data,
      region: region,
      mipLevel: mipLevel,
      bytesPerRow: bytesPerRow,
    );
  }

  @override
  StorageBuffer createBuffer(
    BufferDescriptor descriptor, {
    ByteData? contents,
  }) {
    _unrecorded('createBuffer');
    return inner.createBuffer(descriptor, contents: contents);
  }

  @override
  void writeBuffer(StorageBuffer target, int offsetInBytes, ByteData bytes) {
    _unrecorded('writeBuffer');
    inner.writeBuffer(target, offsetInBytes, bytes);
  }

  @override
  QuerySet createQuerySet(QueryType type, int count) {
    _unrecorded('createQuerySet');
    return inner.createQuerySet(type, count);
  }

  @override
  Future<List<int>> readQueryResults(
    QuerySet querySet, {
    int first = 0,
    int? count,
  }) {
    _unrecorded('readQueryResults');
    return inner.readQueryResults(querySet, first: first, count: count);
  }

  @override
  void releaseQuerySet(QuerySet querySet) {
    _unrecorded('releaseQuerySet');
    inner.releaseQuerySet(querySet);
  }

  @override
  TransferEncoder beginTransferPass({String? label}) {
    _unrecorded('beginTransferPass');
    return inner.beginTransferPass(label: label);
  }

  @override
  Future<MappedBuffer> mapBuffer(
    StorageBuffer buffer,
    MapMode mode, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    _unrecorded('mapBuffer');
    return inner.mapBuffer(
      buffer,
      mode,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
  }

  @override
  ByteData readBufferSync(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    _unrecorded('readBufferSync');
    final inner = this.inner;
    if (inner is! SynchronousBufferReadback) {
      throw refuse(DeviceFeature.synchronousReadback);
    }
    return inner.readBufferSync(
      buffer,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
  }

  @override
  RenderBundleEncoder createRenderBundleEncoder(
    RenderBundleDescriptor descriptor,
  ) {
    _unrecorded('createRenderBundleEncoder');
    return inner.createRenderBundleEncoder(descriptor);
  }
}

final class _RecordingEncoder extends PassEncoder with CommandEncoder {
  _RecordingEncoder(this._device, this._pass, this._inner);

  final RecordingDevice _device;
  final int _pass;
  final CommandEncoder _inner;

  @override
  void pushDebugGroup(String label) {
    _events.add(TracePushDebugGroup(_pass, label));
    _inner.pushDebugGroup(label);
  }

  @override
  void popDebugGroup() {
    _events.add(TracePopDebugGroup(_pass));
    _inner.popDebugGroup();
  }

  @override
  void insertDebugMarker(String label) {
    _events.add(TraceInsertDebugMarker(_pass, label));
    _inner.insertDebugMarker(label);
  }

  List<TraceEvent> get _events => _device.events;

  @override
  void setViewport(ScreenRect rect) {
    _events.add(TraceSetViewport(_pass, rect));
    _inner.setViewport(rect);
  }

  @override
  void setScissor(ScreenRect rect) {
    _events.add(TraceSetScissor(_pass, rect));
    _inner.setScissor(rect);
  }

  @override
  void setPrimitiveType(PrimitiveType type) {
    _events.add(TraceSetPrimitiveType(_pass, type));
    _inner.setPrimitiveType(type);
  }

  @override
  void setPolygonMode(PolygonMode mode) {
    _events.add(TraceSetPolygonMode(_pass, mode));
    _inner.setPolygonMode(mode);
  }

  @override
  void setCullMode(CullMode mode) {
    _events.add(TraceSetCullMode(_pass, mode));
    _inner.setCullMode(mode);
  }

  @override
  void setWindingOrder(WindingOrder order) {
    _events.add(TraceSetWindingOrder(_pass, order));
    _inner.setWindingOrder(order);
  }

  @override
  void setAlphaToCoverage({required bool enabled}) {
    _events.add(TraceSetAlphaToCoverage(_pass, enabled));
    _inner.setAlphaToCoverage(enabled: enabled);
  }

  @override
  void setDepthWrite({required bool enabled}) {
    _events.add(TraceSetDepthWrite(_pass, enabled));
    _inner.setDepthWrite(enabled: enabled);
  }

  @override
  void setDepthCompare(CompareFunction compare) {
    _events.add(TraceSetDepthCompare(_pass, compare));
    _inner.setDepthCompare(compare);
  }

  @override
  void setStencil(StencilState front, {StencilState? back}) {
    _events.add(TraceSetStencil(_pass, front, back));
    _inner.setStencil(front, back: back);
  }

  @override
  void setStencilReference(int value) {
    _events.add(TraceSetStencilReference(_pass, value));
    _inner.setStencilReference(value);
  }

  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    _events.add(TraceSetBlend(_pass, state, attachment));
    _inner.setBlend(state, attachment: attachment);
  }

  @override
  void setBlendColor(Vector4 color) {
    _events.add(TraceSetBlendColor(_pass, color.clone()));
    _inner.setBlendColor(color);
  }

  @override
  void bindPipeline(PipelineHandle pipeline) {
    _events.add(
      TraceBindPipeline(_pass, _device._name(_device._pipelineIds, pipeline)),
    );
    _inner.bindPipeline(pipeline);
  }

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) {
    _events.add(
      TraceBindVertexBuffer(
        pass: _pass,
        buffer: _device._range(buffer),
        vertexCount: vertexCount,
        slot: slot,
      ),
    );
    _inner.bindVertexBuffer(buffer, vertexCount, slot: slot);
  }

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) {
    _events.add(
      TraceBindVertexData(
        pass: _pass,
        bytes: RecordingDevice._copy(bytes),
        vertexCount: vertexCount,
        slot: slot,
      ),
    );
    _inner.bindVertexData(bytes, vertexCount, slot: slot);
  }

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    _events.add(
      TraceBindIndexBuffer(
        pass: _pass,
        buffer: _device._range(buffer),
        type: type,
        indexCount: indexCount,
      ),
    );
    _inner.bindIndexBuffer(buffer, type, indexCount);
  }

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    _events.add(
      TraceBindIndexData(
        pass: _pass,
        bytes: RecordingDevice._copy(bytes),
        type: type,
        indexCount: indexCount,
      ),
    );
    _inner.bindIndexData(bytes, type, indexCount);
  }

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    _events.add(
      TraceBindUniformBlock(
        pass: _pass,
        shader: shader.name,
        block: blockName,
        members: RecordingDevice._copyMembers(members),
      ),
    );
    return _inner.bindUniformBlock(shader, blockName, members);
  }

  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    _events.add(
      TraceBindTexture(
        pass: _pass,
        shader: shader.name,
        slot: slot,
        texture: _device._texture(texture),
        sampler: sampler,
      ),
    );
    return _inner.bindTexture(shader, slot, texture, sampler: sampler);
  }

  @override
  void clearBindings() {
    _events.add(TraceClearBindings(_pass));
    _inner.clearBindings();
  }

  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) {
    _events.add(TraceDraw(_pass, instanceCount, firstIndex, indexCount));
    _inner.draw(
      instanceCount: instanceCount,
      firstIndex: firstIndex,
      indexCount: indexCount,
    );
  }

  @override
  void submit() {
    _events.add(TraceSubmit(_pass));
    _inner.submit();
  }

  // Since 1.0: forwarded, and named in `RecordingDevice.unrecorded`.

  void _unrecorded(String call) => _device._unrecorded(call);

  @override
  void setDepthBias(DepthBias bias) {
    _unrecorded('setDepthBias');
    _inner.setDepthBias(bias);
  }

  @override
  void setColorWriteMask(ColorWriteMask mask, {int attachment = 0}) {
    _unrecorded('setColorWriteMask');
    _inner.setColorWriteMask(mask, attachment: attachment);
  }

  @override
  void setDepthClamp({required bool enabled}) {
    _unrecorded('setDepthClamp');
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
    _unrecorded('bindStorageBuffer');
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
    _unrecorded('bindStorageTexture');
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
    _unrecorded('bindUniformBytes');
    return _inner.bindUniformBytes(shader, blockName, bytes);
  }

  @override
  void drawIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) {
    _unrecorded('drawIndirect');
    _inner.drawIndirect(arguments, offsetInBytes: offsetInBytes);
  }

  @override
  void drawNonIndexed({
    required int vertexCount,
    int firstVertex = 0,
    int instanceCount = 1,
    int firstInstance = 0,
  }) {
    _unrecorded('drawNonIndexed');
    _inner.drawNonIndexed(
      vertexCount: vertexCount,
      firstVertex: firstVertex,
      instanceCount: instanceCount,
      firstInstance: firstInstance,
    );
  }

  /// Traced as the [draw] it is when the base vertex and first instance are
  /// zero, so a frame using it replays.
  @override
  void drawIndexed(IndexedDraw draw) {
    if (draw.usesBaseVertexOrInstance) {
      _unrecorded('drawIndexed');
      _inner.drawIndexed(draw);
      return;
    }
    this.draw(
      instanceCount: draw.instanceCount,
      firstIndex: draw.firstIndex,
      indexCount: draw.indexCount,
    );
  }

  @override
  void multiDraw(List<IndexedDraw> draws) {
    _unrecorded('multiDraw');
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
    _unrecorded('multiDrawIndirect');
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
    _unrecorded('executeBundles');
    _inner.executeBundles(bundles);
  }

  @override
  void beginOcclusionQuery(int queryIndex) {
    _unrecorded('beginOcclusionQuery');
    _inner.beginOcclusionQuery(queryIndex);
  }

  @override
  void endOcclusionQuery() {
    _unrecorded('endOcclusionQuery');
    _inner.endOcclusionQuery();
  }

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) {
    _unrecorded('beginPipelineStatisticsQuery');
    _inner.beginPipelineStatisticsQuery(querySet, queryIndex);
  }

  @override
  void endPipelineStatisticsQuery() {
    _unrecorded('endPipelineStatisticsQuery');
    _inner.endPipelineStatisticsQuery();
  }
}

final class _RecordingComputeEncoder extends ComputeEncoder {
  _RecordingComputeEncoder(this._device, this._pass, this._inner);

  final RecordingDevice _device;
  final int _pass;
  final ComputeEncoder _inner;

  @override
  void pushDebugGroup(String label) => _inner.pushDebugGroup(label);

  @override
  void popDebugGroup() => _inner.popDebugGroup();

  @override
  void insertDebugMarker(String label) => _inner.insertDebugMarker(label);

  @override
  void bindPipeline(ComputePipelineHandle pipeline) {
    _device.events.add(
      TraceComputeBindPipeline(
        _pass,
        _device._name(_device._computePipelineIds, pipeline),
      ),
    );
    _inner.bindPipeline(pipeline);
  }

  @override
  bool bindStorageBuffer(
    ShaderHandle stage,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    // The trace event names the whole buffer; a range is a 1.0 argument it
    // does not carry yet, so the bind is flagged rather than mis-recorded.
    if (offsetInBytes != 0 || sizeInBytes != null) {
      _device._unrecorded('bindStorageBuffer range');
    }
    _device.events.add(
      TraceComputeBindStorageBuffer(
        pass: _pass,
        shader: stage.name,
        name: name,
        buffer: _device._name(_device._storageIds, buffer),
      ),
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
  bool bindUniformBlock(
    ShaderHandle stage,
    String block,
    Map<String, Float32List> members,
  ) {
    _device.events.add(
      TraceComputeBindUniformBlock(
        pass: _pass,
        shader: stage.name,
        block: block,
        members: RecordingDevice._copyMembers(members),
      ),
    );
    return _inner.bindUniformBlock(stage, block, members);
  }

  @override
  void dispatch(int x, [int y = 1, int z = 1]) {
    _device.events.add(TraceDispatch(_pass, x, y, z));
    _inner.dispatch(x, y, z);
  }

  @override
  void submit() {
    _device.events.add(TraceComputeSubmit(_pass));
    _inner.submit();
  }

  // Since 1.0: forwarded, and named in `RecordingDevice.unrecorded`.

  @override
  bool bindTexture(
    ShaderHandle stage,
    String name,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    _device._unrecorded('ComputeEncoder.bindTexture');
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
    _device._unrecorded('ComputeEncoder.bindStorageTexture');
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
    _device._unrecorded('ComputeEncoder.bindUniformBytes');
    return _inner.bindUniformBytes(stage, block, bytes);
  }

  @override
  void dispatchIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) {
    _device._unrecorded('dispatchIndirect');
    _inner.dispatchIndirect(arguments, offsetInBytes: offsetInBytes);
  }

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) {
    _device._unrecorded('ComputeEncoder.beginPipelineStatisticsQuery');
    _inner.beginPipelineStatisticsQuery(querySet, queryIndex);
  }

  @override
  void endPipelineStatisticsQuery() {
    _device._unrecorded('ComputeEncoder.endPipelineStatisticsQuery');
    _inner.endPipelineStatisticsQuery();
  }
}
