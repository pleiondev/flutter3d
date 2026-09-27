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

import '../command_encoder.dart';
import '../compute.dart';
import '../formats.dart';
import '../geometry_buffer.dart';
import '../gpu_timings.dart';
import '../graphics_device.dart';
import '../render_target_pool.dart';
import '../sampler.dart';
import '../shader.dart';
import '../texture.dart';
import '../vertex_layout_spec.dart';
import 'trace_event.dart';

final class RecordingDevice implements GraphicsDevice {
  RecordingDevice(this.inner);

  /// The device every call goes through to.
  final GraphicsDevice inner;

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
  bool get supportsOffscreenMsaa => inner.supportsOffscreenMsaa;
  @override
  bool get supportsBlendColor => inner.supportsBlendColor;
  @override
  bool get supportsMipmaps => inner.supportsMipmaps;
  @override
  bool get supportsCubeTextures => inner.supportsCubeTextures;
  @override
  bool get supportsRenderToMip => inner.supportsRenderToMip;
  @override
  bool get supportsWireframe => inner.supportsWireframe;
  @override
  bool get supportsStencil => inner.supportsStencil;
  @override
  bool supportsTextureFormat(TextureFormat format) =>
      inner.supportsTextureFormat(format);
  @override
  int get maxAnisotropy => inner.maxAnisotropy;
  @override
  int get maxColorAttachments => inner.maxColorAttachments;
  @override
  ShaderLibrary get shaders => inner.shaders;
  @override
  bool get supportsGpuTimestamps => inner.supportsGpuTimestamps;
  @override
  bool get supportsCompute => inner.supportsCompute;
  @override
  bool get supportsFloat32Filtering => inner.supportsFloat32Filtering;
  @override
  bool get supportsIndependentBlend => inner.supportsIndependentBlend;
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
    VertexLayoutSpec? layout,
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

  @override
  TextureHandle createTexture(RenderTargetSpec spec) {
    final texture = inner.createTexture(spec);
    events.add(TraceCreateTexture(id: _texture(texture), spec: spec));
    return texture;
  }

  @override
  TextureHandle? createTextureFromPixels({
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
    if (texture != null) {
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
    }
    return texture;
  }

  @override
  TextureHandle? createCubeTextureFromPixels({
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
    if (texture != null) {
      events.add(
        TraceCreateCubeTextureFromPixels(
          id: _texture(texture),
          size: size,
          format: format,
          faces: faces.map(_copy).toList(),
          mipLevels: mipLevels
              ?.map((face) => face.map(_copy).toList())
              .toList(),
        ),
      );
    }
    return texture;
  }

  @override
  TextureHandle? createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) {
    final texture = inner.createCubeRenderTarget(
      size: size,
      format: format,
      mipLevels: mipLevels,
    );
    if (texture != null) {
      events.add(
        TraceCreateCubeRenderTarget(
          id: _texture(texture),
          size: size,
          format: format,
          mipLevels: mipLevels,
        ),
      );
    }
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
  Future<ByteData?> readPixels(TextureHandle texture) {
    events.add(TraceReadPixels(_texture(texture)));
    return inner.readPixels(texture);
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
  }) {
    final buffer = inner.createStorageBuffer(bytes, hostReadable: hostReadable);
    events.add(
      TraceCreateStorageBuffer(
        id: _name(_storageIds, buffer),
        bytes: _copy(bytes),
        hostReadable: hostReadable,
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
  ComputeEncoder beginComputePass({String? label}) {
    final encoder = inner.beginComputePass(label: label);
    final pass = _nextPass++;
    events.add(TraceBeginComputePass(pass, label));
    return _RecordingComputeEncoder(this, pass, encoder);
  }

  @override
  Future<ByteData> readBuffer(StorageBuffer buffer) {
    events.add(TraceReadBuffer(_name(_storageIds, buffer)));
    return inner.readBuffer(buffer);
  }
}

final class _RecordingEncoder implements CommandEncoder {
  _RecordingEncoder(this._device, this._pass, this._inner);

  final RecordingDevice _device;
  final int _pass;
  final CommandEncoder _inner;

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
  void setDepthWrite(bool enabled) {
    _events.add(TraceSetDepthWrite(_pass, enabled));
    _inner.setDepthWrite(enabled);
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
    SamplerOptions? sampler,
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
  void draw({int instanceCount = 1}) {
    _events.add(TraceDraw(_pass, instanceCount));
    _inner.draw(instanceCount: instanceCount);
  }

  @override
  void submit() {
    _events.add(TraceSubmit(_pass));
    _inner.submit();
  }
}

final class _RecordingComputeEncoder implements ComputeEncoder {
  _RecordingComputeEncoder(this._device, this._pass, this._inner);

  final RecordingDevice _device;
  final int _pass;
  final ComputeEncoder _inner;

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
    StorageBuffer buffer,
  ) {
    _device.events.add(
      TraceComputeBindStorageBuffer(
        pass: _pass,
        shader: stage.name,
        name: name,
        buffer: _device._name(_device._storageIds, buffer),
      ),
    );
    return _inner.bindStorageBuffer(stage, name, buffer);
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
}
