/// Recording one pass on WebGPU, and the accumulation that makes it possible.
///
/// **The whole of this file is the second divergence `command_encoder.dart`
/// names.** That file says rasteriser state is per draw on Impeller and per
/// pipeline on Vulkan, and that "a Vulkan backend must accumulate these calls
/// and look a pipeline up at `PassEncoder.draw` rather than at
/// `PassEncoder.bindPipeline`". WebGPU is the same API shape, so the paragraph
/// turned out to describe this backend too — written years before there was one
/// to check it against. Nothing in the contract changes; what changes is where
/// the work happens.
///
/// ## What a draw has to settle that a bind did not
///
/// Six setters go into a private field and are read at the draw:
/// [WebGpuRecorder.setPrimitiveType], [WebGpuRecorder.setCullMode],
/// [WebGpuRecorder.setWindingOrder], [WebGpuRecorder.setDepthWrite],
/// [WebGpuRecorder.setDepthCompare] and [WebGpuRecorder.setBlend]. The stencil
/// is a seventh, and the vertex layout an eighth that never was a setter at
/// all. 1.0 added three more WebGPU also bakes into a pipeline — the depth
/// bias, the colour write masks and unclipped depth. Together with the
/// attachment formats and the sample count — which the pass knew when it was
/// opened — they make [WebGpuPipelineSignature], and the map behind it is what
/// turns a pass of eighty draws into a handful of pipeline objects.
///
/// Three go straight through, because WebGPU keeps them dynamic:
/// [WebGpuEncoder.setViewport], [WebGpuEncoder.setScissor] and
/// [WebGpuEncoder.setStencilReference]. Two are refused, and the refusals are
/// promises the device already made: `setPolygonMode(PolygonMode.line)` because
/// there is no polygon fill mode in this API at all, and
/// [WebGpuEncoder.setBlendColor] because two of the four constant-reading blend
/// factors have no spelling here.
///
/// ## Bindings are accumulated too, and for a different reason
///
/// A `GPUBindGroup` is every binding of one `@group` at once, so a group cannot
/// be assembled until the last thing that goes in it has been bound. The
/// bindings therefore land in maps keyed by group and binding number — read out
/// of the bundle's reflection, because a `GPUShaderModule` answers no question
/// about itself — and the groups are built at the draw and cached.
///
/// **The uniform blocks go in with a dynamic offset**, which is what keeps that
/// cache worth having: without it every draw's block would be a different
/// buffer range and so a different bind group, and a frame of forty materials
/// against one camera block would build forty copies of the camera's group. The
/// bind group names the arena buffer and the block's size; the offset the block
/// actually landed at rides on `setBindGroup`.
///
/// ## A pass and a bundle are one recorder
///
/// Since 1.0 the same accumulation records into a `GPURenderBundleEncoder`
/// as well as a pass: both are `GPURenderCommands`, a draw resolves its
/// pipeline and groups the same way into either, and [WebGpuRecorder] is
/// that shared half. [WebGpuEncoder] adds what only a pass has — the
/// rectangle, the stencil reference, the queries, replaying bundles — and
/// [WebGpuBundleEncoder] refuses those with the [StateError] the contract
/// names.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapability;
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import 'webgpu_bundle_section.dart';
import 'webgpu_compute.dart'
    show
        WebGpuStorage,
        webgpuCheckIndirect,
        webgpuCheckSampler,
        webgpuSamplerForSlot;
import 'webgpu_device.dart';
import 'webgpu_formats.dart';
import 'webgpu_interop.dart';
import 'webgpu_pipeline_cache.dart';
import 'webgpu_resources.dart';
import 'webgpu_shaders.dart';
import 'webgpu_types.dart';

const String _backend = 'WebGPU';

/// What a pass and a bundle both record: the accumulated state, the
/// bindings, and the draws resolved against them.
abstract base class WebGpuRecorder extends PassEncoder {
  WebGpuRecorder(
    this._device, {
    required List<TextureFormat> colorFormats,
    required TextureFormat? depthFormat,
    required this._sampleCount,
    this._depthReadOnly = false,
    this._stencilReadOnly = false,
  }) : _formats = List<TextureFormat>.unmodifiable(colorFormats),
       _colorFormats = <String>[
         for (final format in colorFormats) gpuTextureFormat(format)!,
       ],
       _blends = <BlendState?>[for (final _ in colorFormats) null],
       _masks = <ColorWriteMask>[
         for (final _ in colorFormats) ColorWriteMask.all,
       ],
       _depthTextureFormat = depthFormat,
       _depthFormat = depthFormat == null
           ? null
           : gpuTextureFormat(depthFormat);

  final WebGpuDevice _device;
  final List<TextureFormat> _formats;
  final List<String> _colorFormats;
  final TextureFormat? _depthTextureFormat;
  final String? _depthFormat;
  final int _sampleCount;
  final bool _depthReadOnly;
  final bool _stencilReadOnly;

  /// Where the draws go: the pass, or the bundle.
  GPURenderCommands get _commands;

  @override
  void pushDebugGroup(String label) => _commands.pushDebugGroup(label);

  @override
  void popDebugGroup() => _commands.popDebugGroup();

  @override
  void insertDebugMarker(String label) => _commands.insertDebugMarker(label);

  // The accumulated state. Mutable because it is state: every setter writes one
  // of these and the draw reads all of them.
  WebGpuPipeline? _pipeline;
  PrimitiveType _primitive = PrimitiveType.triangle;
  CullMode _cull = CullMode.none;
  WindingOrder _winding = WindingOrder.counterClockwise;
  CompareFunction _depthCompare = CompareFunction.always;
  bool _depthWrite = true;
  DepthBias _depthBias = DepthBias.none;
  bool _unclippedDepth = false;

  /// `setAlphaToCoverage`, off at the pass's start — `P7`.
  bool _alphaToCoverage = false;
  StencilState? _stencilFront;
  StencilState? _stencilBack;

  /// One blend equation per colour attachment.
  ///
  /// **A list rather than a single state, and that is the one thing this
  /// backend can do that the other three cannot.** `PassEncoder.setBlend` takes
  /// an attachment index and calls it "a hint until" an optional WebGL2
  /// extension and a capability arrive; here every `GPUColorTargetState` in a
  /// pipeline carries its own equation, so the index is honoured for nothing
  /// and the signature keys on the whole list.
  final List<BlendState?> _blends;

  /// One write mask per colour attachment, all channels at the start.
  final List<ColorWriteMask> _masks;

  final Map<int, WebGpuSlice> _vertexBuffers = <int, WebGpuSlice>{};
  WebGpuSlice? _indexBuffer;
  IndexType _indexType = IndexType.int32;
  int _indexCount = 0;

  /// Where each uniform block landed, by group and then by binding number.
  final Map<int, Map<int, WebGpuSlice>> _blocks =
      <int, Map<int, WebGpuSlice>>{};

  /// What each sampled texture slot holds, by group and then by binding number
  /// — the image view under one number and the sampler object under the other,
  /// which is the shape a `sampler2D` becomes once the image and the filtering
  /// state are separate objects.
  final Map<int, Map<int, GPUTextureView>> _views =
      <int, Map<int, GPUTextureView>>{};
  final Map<int, Map<int, GPUSampler>> _samplers =
      <int, Map<int, GPUSampler>>{};

  // ---------------------------------------------- accumulated for the draw

  @override
  void setPrimitiveType(PrimitiveType type) => _primitive = type;

  @override
  void setCullMode(CullMode mode) => _cull = mode;

  @override
  void setWindingOrder(WindingOrder order) => _winding = order;

  @override
  void setDepthWrite({required bool enabled}) => _depthWrite = enabled;

  /// Into the pipeline's signature: WebGPU sets it when a pipeline is built,
  /// and only for one of more than one sample, where a pipeline of one would
  /// be refused — so a pass of one sample builds the pipeline without it.
  @override
  void setAlphaToCoverage({required bool enabled}) =>
      _alphaToCoverage = enabled;

  @override
  void setDepthCompare(CompareFunction compare) => _depthCompare = compare;

  @override
  void setStencil(StencilState front, {StencilState? back}) {
    _stencilFront = front;
    // Null means "the same on both faces", which is what every caller in this
    // engine wants. WebGPU states the two separately and has no way to say
    // "as the front", so the contract's default is written out here.
    _stencilBack = back ?? front;
  }

  /// Into the signature: `depthBias`, `depthBiasSlopeScale` and
  /// `depthBiasClamp` are pipeline state.
  @override
  void setDepthBias(DepthBias bias) {
    _device.features.require(DeviceFeature.depthBias, backend: _backend);
    _depthBias = bias;
  }

  /// Into the signature: a target's `writeMask` is pipeline state, and the
  /// index is honoured for the reason [setBlend]'s is.
  @override
  void setColorWriteMask(ColorWriteMask mask, {int attachment = 0}) {
    _device.features.require(DeviceFeature.colorWriteMask, backend: _backend);
    _checkAttachment(attachment);
    _masks[attachment] = mask;
  }

  /// Into the signature as `unclippedDepth`, on a device granted
  /// `depth-clip-control`.
  @override
  void setDepthClamp({required bool enabled}) {
    _device.features.require(
      DeviceFeature.depthClamp,
      backend: _backend,
      reason: 'the adapter did not offer depth-clip-control',
    );
    _unclippedDepth = enabled;
  }

  void _checkAttachment(int attachment) {
    if (attachment < 0 || attachment >= _blends.length) {
      throw ArgumentError.value(
        attachment,
        'attachment',
        'is not one of this pass\'s ${_blends.length} colour attachments',
      );
    }
  }

  /// Blending for one colour attachment; null switches it off.
  ///
  /// **[attachment] is honoured, which no other backend here does.** Impeller
  /// passes it to flutter_gpu, WebGL2 would need `EXT_draw_buffers_indexed` and
  /// the software rasteriser keeps one state for the pass — so both of those
  /// write attachment zero whatever index they are handed. WebGPU gives every
  /// target its own equation in the pipeline, so the index reaches the hardware
  /// and two attachments can genuinely blend differently.
  ///
  /// An index outside the pass's attachments is a caller mistake rather than a
  /// hint, and is refused: the other backends' silent substitution is what
  /// makes it worth stopping for here.
  ///
  /// A state naming a constant-reading factor is refused as [setBlendColor]
  /// is; one naming a dual-source factor needs `dual-source-blending`, which
  /// the adapter may not offer; min and max are core.
  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    _checkAttachment(attachment);
    if (state != null) {
      if (state.usesBlendColor) {
        _device.features.require(
          DeviceFeature.blendConstant,
          backend: _backend,
          reason: _noBlendConstant,
        );
      }
      if (state.usesDualSource) {
        _device.features.require(
          DeviceFeature.dualSourceBlending,
          backend: _backend,
          reason: 'the adapter did not offer dual-source-blending',
        );
      }
      if (state.usesMinMax) {
        _device.features.require(DeviceFeature.minMaxBlend, backend: _backend);
      }
    }
    _blends[attachment] = state;
  }

  /// Refused for [PolygonMode.line]. WebGPU has no polygon fill mode, so this
  /// is the answer `supportsWireframe` being false already promised: a
  /// wireframe here means line primitives and an index buffer built for them,
  /// which is the renderer's decision and not a substitution a backend may make.
  @override
  void setPolygonMode(PolygonMode mode) {
    if (mode == PolygonMode.fill) return;
    throw UnsupportedCapability(
      DeviceFeature.wireframe,
      backend: _backend,
      reason: 'there is no polygon fill mode in the API',
    );
  }

  // --------------------------------------------------------- the bindings

  @override
  void bindPipeline(PipelineHandle pipeline) {
    _pipeline = pipeline.backend as WebGpuPipeline;
    // Bindings do not survive a pipeline change — the contract states it, and
    // this honours it literally rather than by accident.
    _forgetBindings();
  }

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) {
    final geometry = buffer.backend as WebGpuGeometry;
    _vertexBuffers[slot] = (
      buffer: geometry.buffer,
      offset: buffer.offsetInBytes,
      length: buffer.lengthInBytes,
    );
  }

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      _vertexBuffers[slot] = _device.vertexArena.write(bytes);

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    final geometry = buffer.backend as WebGpuGeometry;
    _indexBuffer = (
      buffer: geometry.buffer,
      offset: buffer.offsetInBytes,
      length: buffer.lengthInBytes,
    );
    _indexType = type;
    _indexCount = indexCount;
  }

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    _indexBuffer = _device.indexArena.write(bytes);
    _indexType = type;
    _indexCount = indexCount;
  }

  /// Fills the block called [blockName] and binds it. False where [shader]
  /// declares no such block.
  ///
  /// The two halves of the contract's rule, kept apart: a block the translator
  /// dropped because nothing read it is an ordinary `false`, and a block that
  /// exists *without* a member the caller named throws — the two ends disagree
  /// about its shape, and zeros are a plausible value for most of what goes
  /// through here.
  ///
  /// The bytes go into the frame's uniform arena and the offset is remembered
  /// for the draw. Nothing is bound to the pass yet: a `GPUBindGroup` is every
  /// binding of one group at once, and the rest of this group may still be
  /// coming.
  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    // `gfx-92n`: a block the compiled stage dropped is refused here, before
    // anything reaches the driver — binding one is a native crash on Metal.
    if (!shader.mayBindBlock(blockName)) return false;
    final stage = shader.backend as WebGpuShader;
    final block = stage.blockNamed(blockName);
    if (block == null) return false;

    final data = Float32List(block.sizeInBytes ~/ 4);
    for (final entry in members.entries) {
      final member = _memberOf(block, entry.key);
      final at = member.offsetInBytes ~/ 4;
      if (at + entry.value.length > data.length) {
        throw StateError(
          'uniform block "$blockName" member "${entry.key}" wants '
          '${entry.value.length} floats at offset $at, past the block\'s '
          '${data.length}. std140 pads array elements to sixteen bytes; a '
          'tightly packed array of scalars overruns exactly like this',
        );
      }
      data.setRange(at, at + entry.value.length, entry.value);
    }
    _landBlock(block, ByteData.sublistView(data));
    return true;
  }

  /// The block called [blockName] filled from [bytes] as they are — the
  /// reflection's std140 layout is the caller's to follow — zero-padded to
  /// the block's size.
  @override
  bool bindUniformBytes(ShaderHandle shader, String blockName, ByteData bytes) {
    _device.features.require(DeviceFeature.uniformBytes, backend: _backend);
    if (!shader.mayBindBlock(blockName)) return false;
    final block = (shader.backend as WebGpuShader).blockNamed(blockName);
    if (block == null) return false;
    if (bytes.lengthInBytes > block.sizeInBytes) {
      throw ArgumentError.value(
        bytes.lengthInBytes,
        'bytes',
        'is longer than the ${block.sizeInBytes}-byte block "$blockName"',
      );
    }
    final padded = Uint8List(block.sizeInBytes)
      ..setRange(
        0,
        bytes.lengthInBytes,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    _landBlock(block, ByteData.sublistView(padded));
    return true;
  }

  void _landBlock(WebGpuBlock block, ByteData data) => _blocks.putIfAbsent(
    block.group,
    () => <int, WebGpuSlice>{},
  )[block.binding] = _device.uniformArena.write(data);

  static WebGpuBlockMember _memberOf(WebGpuBlock block, String name) {
    for (final member in block.members) {
      if (member.name == name) return member;
    }
    // Loud, because silence here is indistinguishable from working: a member
    // the caller wrote and the block does not have leaves zeros in its place,
    // and a shadow strength of zero is a scene with no shadows and no error.
    throw StateError(
      'uniform block "${block.name}" has no member "$name". It has: '
      '${block.members.map((WebGpuBlockMember m) => m.name).join(', ')}. '
      'The engine and the shader disagree about this block',
    );
  }

  /// Binds [texture] to the sampler called [slot] in [shader].
  ///
  /// **One name becomes two bindings**, which is the shape of the whole
  /// problem this package's GLSL is edited to solve: `sampler2D` is one object
  /// in GLSL and two in WGSL, as it is in Vulkan and Metal, so the reflection
  /// carries the pair and this splits the bind across them.
  ///
  /// False for a slot this stage does not declare, as the contract says, and
  /// never a throw: a stage that optimised a sampler away is not a caller
  /// mistake, and the caller that did make one is told by the return value.
  ///
  /// A null [sampler] is `SamplerDescriptor.linearRepeat` — the contract's
  /// default, not the constructor's, which is nearest and clamp and which cost
  /// a third backend two percent of every textured golden before the rule was
  /// written down. A comparison slot takes a sampler with a compare function
  /// and nothing else; see `webgpuSamplerForSlot`.
  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    // The sampler's state is refused before the slot is looked at.
    webgpuCheckSampler(_device.features, sampler);
    if (!shader.mayBindSampler(slot)) return false;
    final stage = shader.backend as WebGpuShader;
    final declared = stage.samplerNamed(slot);
    if (declared == null) return false;
    final options = webgpuSamplerForSlot(declared, sampler);

    final backend = texture.backend as WebGpuTexture;
    assert(
      backend.sampleable,
      'the "$slot" slot was handed a texture that is multisampled or '
      'deviceTransient, which on this backend is allocated without '
      'TEXTURE_BINDING and can only ever be an attachment',
    );
    final object = _device.samplerFor(options);
    _views.putIfAbsent(
      declared.group,
      () => <int, GPUTextureView>{},
    )[declared.textureBinding] = backend.sampledView;
    _samplers.putIfAbsent(
      declared.group,
      () => <int, GPUSampler>{},
    )[declared.samplerBinding] = object;
    return true;
  }

  // TODO(webgpu): storage in render stages — the WebGPU section's
  // reflection for vertex and fragment stages carries blocks and samplers
  // only, so there is no binding a name could reach. Storage bindings in
  // `WebGpuStage`, written by the packer and laid out by `_groupShapes`,
  // would unblock it; the API itself has them.
  @override
  bool bindStorageBuffer(
    ShaderHandle shader,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    _device.features.require(
      DeviceFeature.renderStageStorage,
      backend: _backend,
      reason: _noRenderStorage,
    );
    return false;
  }

  @override
  bool bindStorageTexture(
    ShaderHandle shader,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  }) {
    _device.features.require(
      DeviceFeature.renderStageStorage,
      backend: _backend,
      reason: _noRenderStorage,
    );
    return false;
  }

  @override
  void clearBindings() => _forgetBindings();

  void _forgetBindings() {
    _vertexBuffers.clear();
    _indexBuffer = null;
    _indexCount = 0;
    _blocks.clear();
    _views.clear();
    _samplers.clear();
  }

  // ------------------------------------------------------------- the draws

  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) =>
      drawIndexed(
        IndexedDraw(
          indexCount: indexCount,
          firstIndex: firstIndex,
          instanceCount: instanceCount,
        ),
      );

  /// [draw] with a base vertex and a first instance, both core in WebGPU.
  @override
  void drawIndexed(IndexedDraw draw) {
    if (draw.usesBaseVertexOrInstance) {
      _device.features.require(
        DeviceFeature.baseVertexBaseInstance,
        backend: _backend,
      );
    }
    final window = indexWindow(
      _indexCount,
      firstIndex: draw.firstIndex,
      indexCount: draw.indexCount,
    );
    // Below one draws nothing, as it does on the other backends. A negative
    // count handed on would reach `drawIndexed` as an unsigned number in the
    // billions.
    if (draw.instanceCount <= 0) return;
    _prepareIndexed();
    _commands.drawIndexed(
      window.count,
      draw.instanceCount,
      window.first,
      draw.baseVertex,
      draw.firstInstance,
    );
  }

  /// One [drawIndexed] per entry: the bindings are resolved per draw anyway,
  /// and the bind group cache makes every one after the first a lookup.
  @override
  void multiDraw(List<IndexedDraw> draws) {
    _device.features.require(DeviceFeature.multiDraw, backend: _backend);
    for (final draw in draws) {
      drawIndexed(draw);
    }
  }

  /// An indexed draw whose five words a buffer holds. A non-zero first
  /// instance among them draws nothing on a device without
  /// `indirect-first-instance` — the specification's answer, and the one
  /// this backend cannot see from here, since the words never reach the CPU.
  @override
  void drawIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) {
    _device.features.require(DeviceFeature.indirectDraw, backend: _backend);
    webgpuCheckIndirect(arguments, offsetInBytes, 20);
    _prepareIndexed();
    _commands.drawIndexedIndirect(
      (arguments.backend as WebGpuStorage).buffer,
      offsetInBytes,
    );
  }

  @override
  void multiDrawIndirect(
    StorageBuffer arguments,
    int drawCount, {
    int offsetInBytes = 0,
    StorageBuffer? countBuffer,
    int countOffsetInBytes = 0,
  }) {
    _device.features.require(
      DeviceFeature.multiDrawIndirect,
      backend: _backend,
      reason: 'the adapter did not offer multi-draw-indirect',
    );
    if (drawCount <= 0) return;
    webgpuCheckIndirect(arguments, offsetInBytes, drawCount * 20);
    if (countBuffer != null) {
      webgpuCheckIndirect(countBuffer, countOffsetInBytes, 4);
    }
    _prepareIndexed();
    _multiDrawIndirect(
      (arguments.backend as WebGpuStorage).buffer,
      offsetInBytes,
      drawCount,
      (countBuffer?.backend as WebGpuStorage?)?.buffer,
      countOffsetInBytes,
    );
  }

  void _multiDrawIndirect(
    GPUBuffer arguments,
    int offset,
    int drawCount,
    GPUBuffer? count,
    int countOffset,
  );

  /// Vertices in order, no index buffer — the bound one, if any, is left
  /// bound for the next indexed draw.
  @override
  void drawNonIndexed({
    required int vertexCount,
    int firstVertex = 0,
    int instanceCount = 1,
    int firstInstance = 0,
  }) {
    _device.features.require(DeviceFeature.nonIndexedDraw, backend: _backend);
    if (vertexCount <= 0 || instanceCount <= 0) return;
    _prepare();
    _commands.draw(vertexCount, instanceCount, firstVertex, firstInstance);
  }

  void _prepareIndexed() {
    final indices = _indexBuffer;
    if (indices == null) {
      throw StateError(
        'an indexed draw with no index buffer bound; drawNonIndexed draws '
        'without one',
      );
    }
    _prepare();
    _commands.setIndexBuffer(
      indices.buffer,
      gpuIndexFormat(_indexType),
      indices.offset,
      indices.length,
    );
  }

  /// The pipeline, the groups and the vertex buffers this draw's state
  /// resolves to, set on [_commands].
  void _prepare() {
    final pipeline = _pipeline;
    if (pipeline == null) {
      throw StateError('a draw with no pipeline bound');
    }
    final layouts = _device.bindingsFor(pipeline);
    _commands.setPipeline(_realPipeline(pipeline, layouts));
    for (var group = 0; group < layouts.groups.length; group++) {
      final shape = layouts.shapes[group];
      if (shape.isEmpty) continue;
      _commands.setBindGroup(
        group,
        _device.bindGroupFor(
          layouts,
          group,
          _blocks[group],
          _views[group],
          _samplers[group],
        ),
        <JSNumber>[
          for (final bound in shape.blocks)
            (_blocks[group]?[bound.block.binding]?.offset ?? 0).toJS,
        ].toJS,
      );
    }
    for (final entry in _vertexBuffers.entries) {
      _commands.setVertexBuffer(
        entry.key,
        entry.value.buffer,
        entry.value.offset,
        entry.value.length,
      );
    }
  }

  /// The signature this draw's state makes, which is what the cache is
  /// consulted with.
  ///
  /// Public because `webgpu_encoder_test.dart` asserts on it directly: the
  /// question "do these two draws want two pipelines" is answerable without
  /// counting what the browser built, and a test that could only count would
  /// pass on a backend that had stopped honouring the key and happened to build
  /// two anyway.
  WebGpuPipelineSignature signatureFor(WebGpuPipeline pipeline) {
    final strip =
        _primitive == PrimitiveType.triangleStrip ||
        _primitive == PrimitiveType.lineStrip;
    return WebGpuPipelineSignature(
      pipeline: pipeline.name,
      // The modules, not only the name: a reload and a layered library both
      // put different code under one `vertex+fragment` string.
      vertexModule: pipeline.vertexModule,
      fragmentModule: pipeline.fragmentModule,
      vertexLayout: webgpuVertexLayoutFingerprint(pipeline.layout),
      topology: gpuPrimitiveTopology(_primitive),
      stripIndexFormat: strip ? gpuIndexFormat(_indexType) : null,
      cullMode: gpuCullMode(_cull),
      frontFace: gpuFrontFace(_winding),
      depthCompare: gpuCompareFunction(_depthCompare),
      // A read-only depth attachment refuses a pipeline that writes it.
      depthWrite: _depthWrite && !_depthReadOnly,
      stencil: webgpuStencilFingerprint(_stencilFront, _stencilBack),
      blends: _blends,
      colorFormats: _colorFormats,
      depthFormat: _depthFormat,
      sampleCount: _sampleCount,
      alphaToCoverage: _alphaToCoverage && _sampleCount > 1,
      depthBias: _depthBias,
      writeMasks: _masks,
      unclippedDepth: _unclippedDepth,
    );
  }

  GPURenderPipeline _realPipeline(
    WebGpuPipeline pipeline,
    WebGpuBindingLayouts layouts,
  ) {
    final signature = signatureFor(pipeline);
    return _device.pipelines.get(signature, () {
      final state = WebGpuDrawState(
        signature: signature,
        stencilFront: _stencilFront,
        stencilBack: _stencilBack,
        stencilReadOnly: _stencilReadOnly,
      );
      // Remembered when a pipeline is built, not at every draw: the states a
      // device has built in are what `createPipelineAsync` warms a new pair
      // with.
      _device.rememberDrawState(state);
      return _device.guard(
        'the pipeline for $signature',
        () => _device.gpuDevice.createRenderPipeline(
          webgpuRenderPipelineDescriptor(pipeline, layouts, state),
        ),
      );
    });
  }

  static GPUStencilFaceState _faceStateOf(StencilState state) =>
      GPUStencilFaceState(
        compare: gpuCompareFunction(state.compare),
        failOp: gpuStencilOperation(state.failOp),
        depthFailOp: gpuStencilOperation(state.depthFailOp),
        passOp: gpuStencilOperation(state.passOp),
      );

  static GPUBlendState _blendStateOf(BlendState state) => GPUBlendState(
    color: _componentOf(
      state.colorOperation,
      state.sourceColorFactor,
      state.destinationColorFactor,
    ),
    alpha: _componentOf(
      state.alphaOperation,
      state.sourceAlphaFactor,
      state.destinationAlphaFactor,
    ),
  );

  /// One blend component. **Min and max take both factors as `"one"`**,
  /// which WebGPU requires of them and the contract's "ignore both factors"
  /// means — the caller's factors are not an error, only irrelevant.
  static GPUBlendComponent _componentOf(
    BlendOperation operation,
    BlendFactor source,
    BlendFactor destination,
  ) {
    final minMax =
        operation == BlendOperation.min || operation == BlendOperation.max;
    return GPUBlendComponent(
      operation: gpuBlendOperation(operation),
      srcFactor: minMax ? 'one' : gpuBlendFactor(source)!,
      dstFactor: minMax ? 'one' : gpuBlendFactor(destination)!,
    );
  }
}

/// What a draw bakes into a `GPURenderPipeline` beside its stage pair: the
/// [signature] the cache keys on, and the stencil faces the signature keeps
/// only as a fingerprint.
///
/// A snapshot rather than the recorder's own fields, so the same state can
/// be built again for another stage pair after the pass has moved on —
/// `WebGpuDevice.createPipelineAsync` warms a new pair in the states the
/// device has already drawn in.
final class WebGpuDrawState {
  const WebGpuDrawState({
    required this.signature,
    this.stencilFront,
    this.stencilBack,
    this.stencilReadOnly = false,
  });

  final WebGpuPipelineSignature signature;
  final StencilState? stencilFront;
  final StencilState? stencilBack;
  final bool stencilReadOnly;

  /// This state with [pipeline]'s stages and vertex layout in it.
  WebGpuDrawState forPipeline(WebGpuPipeline pipeline) => WebGpuDrawState(
    signature: signature.withStages(
      pipeline: pipeline.name,
      vertexModule: pipeline.vertexModule,
      fragmentModule: pipeline.fragmentModule,
      vertexLayout: webgpuVertexLayoutFingerprint(pipeline.layout),
    ),
    stencilFront: stencilFront,
    stencilBack: stencilBack,
    stencilReadOnly: stencilReadOnly,
  );

  /// The state alone, whatever was drawn in it: two draws of different
  /// pairs in one state answer the same key.
  Object get stateKey => (
    signature.withStages(
      pipeline: '',
      vertexModule: null,
      fragmentModule: null,
      vertexLayout: '',
    ),
    stencilFront,
    stencilBack,
    stencilReadOnly,
  );
}

/// The descriptor that builds [pipeline] in [state], against [layouts]:
/// what a draw hands `createRenderPipeline`, and what a warm hands
/// `createRenderPipelineAsync`.
GPURenderPipelineDescriptor webgpuRenderPipelineDescriptor(
  WebGpuPipeline pipeline,
  WebGpuBindingLayouts layouts,
  WebGpuDrawState state,
) {
  final signature = state.signature;
  final vertex = GPUVertexState(
    // The cast is where a module stops being the `Object` a shader library
    // hands out and becomes this browser's own. That library compiles through
    // `WgslModuleCompiler` so its arithmetic can be asserted on the VM, and
    // this is the one line that pays for it — on a handle the device itself
    // compiled, which is what `createWebGpuPipeline` already refused to take
    // on trust.
    module: pipeline.vertexModule as GPUShaderModule,
    entryPoint: webgpuEntryPoint,
    buffers: <GPUVertexBufferLayout>[
      for (final buffer in pipeline.buffers)
        GPUVertexBufferLayout(
          arrayStride: buffer.strideInBytes,
          stepMode: gpuVertexStepMode(buffer.stepMode),
          attributes: <GPUVertexAttribute>[
            for (final attribute in buffer.attributes)
              GPUVertexAttribute(
                format: gpuVertexFormat(attribute.format),
                offset: attribute.offsetInBytes,
                // Already resolved against the vertex stage's own table when
                // the pipeline was made: a layout names attributes and WGSL
                // kept only locations, and the bundle's reflection is what
                // matches the two.
                shaderLocation: attribute.shaderLocation,
              ),
          ].toJS,
        ),
    ].toJS,
  );
  final fragment = GPUFragmentState(
    module: pipeline.fragmentModule as GPUShaderModule,
    entryPoint: webgpuEntryPoint,
    targets: <GPUColorTargetState>[
      for (var i = 0; i < signature.colorFormats.length; i++)
        // A target the stage writes nothing to is left as it was, which is
        // what the other backends do with it and the only thing WebGPU
        // accepts: a non-zero mask over a missing output invalidates the
        // pipeline, and the command buffer that draws with it. Blending is
        // left off there too, since there is nothing to blend.
        if (!(pipeline.fragmentOutputs?.contains(i) ?? true))
          GPUColorTargetState.opaque(
            format: signature.colorFormats[i],
            writeMask: GpuColorWrite.none,
          )
        else if (signature.blends.elementAtOrNull(i)
            case final BlendState blend)
          GPUColorTargetState(
            format: signature.colorFormats[i],
            blend: WebGpuRecorder._blendStateOf(blend),
            // `ColorWriteMask`'s bits are `GPUColorWrite`'s, red to alpha.
            writeMask: signature.writeMaskOf(i).bits,
          )
        else
          GPUColorTargetState.opaque(
            format: signature.colorFormats[i],
            writeMask: signature.writeMaskOf(i).bits,
          ),
    ].toJS,
  );
  final primitive = signature.stripIndexFormat == null
      ? GPUPrimitiveState(
          topology: signature.topology,
          cullMode: signature.cullMode,
          frontFace: signature.frontFace,
          unclippedDepth: signature.unclippedDepth,
        )
      // A strip pipeline that leaves `stripIndexFormat` out cannot be used
      // for an indexed draw at all: the restart value depends on the index
      // width, and WebGPU settles it when the pipeline is built rather than
      // when the buffer is bound.
      : GPUPrimitiveState.strip(
          topology: signature.topology,
          cullMode: signature.cullMode,
          frontFace: signature.frontFace,
          stripIndexFormat: signature.stripIndexFormat!,
          unclippedDepth: signature.unclippedDepth,
        );
  final multisample = GPUMultisampleState(
    count: signature.sampleCount,
    mask: 0xFFFFFFFF,
    alphaToCoverageEnabled: signature.alphaToCoverage,
  );

  final depthFormat = signature.depthFormat;
  if (depthFormat == null) {
    return GPURenderPipelineDescriptor.withoutDepth(
      layout: layouts.pipelineLayout,
      vertex: vertex,
      fragment: fragment,
      primitive: primitive,
      multisample: multisample,
      label: pipeline.name,
    );
  }
  final front = state.stencilFront ?? StencilState.disabled;
  final back = state.stencilBack ?? front;
  final bias = signature.depthBias;
  return GPURenderPipelineDescriptor(
    layout: layouts.pipelineLayout,
    vertex: vertex,
    fragment: fragment,
    primitive: primitive,
    multisample: multisample,
    depthStencil: GPUDepthStencilState(
      format: depthFormat,
      depthWriteEnabled: signature.depthWrite,
      depthCompare: signature.depthCompare,
      stencilFront: WebGpuRecorder._faceStateOf(front),
      stencilBack: WebGpuRecorder._faceStateOf(back),
      // Pipeline state here and dynamic in the contract's wording only for
      // the reference value — which is why `setStencilReference` reaches
      // the pass and these two do not. A read-only stencil refuses a
      // pipeline that could write it, so its mask is zero there.
      stencilReadMask: front.readMask,
      stencilWriteMask: state.stencilReadOnly ? 0 : front.writeMask,
      depthBias: bias.constant,
      depthBiasSlopeScale: bias.slopeScale,
      depthBiasClamp: bias.clamp,
    ),
    label: pipeline.name,
  );
}

const String _noBlendConstant =
    'WebGPU has "constant" and "one-minus-constant" and no equivalent of '
    'CONSTANT_ALPHA, so two of the four factors BlendFactor names cannot be '
    'formed';

const String _noRenderStorage =
    'the WebGPU section reflects no storage bindings for vertex and fragment '
    'stages';

/// One pass, recorded and submitted.
final class WebGpuEncoder extends WebGpuRecorder with CommandEncoder {
  WebGpuEncoder(
    WebGpuDevice device,
    RenderPassDescriptor descriptor, {
    GPURenderPassTimestampWrites? timestampWrites,
  }) : _occlusionSet = descriptor.occlusionQuerySet,
       super(
         device,
         colorFormats: <TextureFormat>[
           for (final target in descriptor.colors) target.texture.format,
         ],
         depthFormat: descriptor.depth?.texture.format,
         sampleCount: descriptor.colors.isNotEmpty
             ? descriptor.colors.first.texture.sampleCount
             : (descriptor.depth?.texture.sampleCount ?? 1),
         depthReadOnly: descriptor.depth?.depthReadOnly ?? false,
         stencilReadOnly: descriptor.depth?.stencilReadOnly ?? false,
       ) {
    final colors = <GPURenderPassColorAttachment>[
      for (final target in descriptor.colors) _colorAttachment(target),
    ];
    final depth = descriptor.depth;
    _encoder = device.gpuDevice.createCommandEncoder();
    final gpuDescriptor = depth == null
        ? GPURenderPassDescriptor(
            colorAttachments: colors.toJS,
            label: descriptor.label ?? 'flutter3d pass',
          )
        : GPURenderPassDescriptor.withDepth(
            colorAttachments: colors.toJS,
            depthStencilAttachment: _depthAttachment(depth),
            label: descriptor.label ?? 'flutter3d pass',
          );
    // `H2`, or the caller's own writes: only when there are some; the member
    // left out is "none", and a null would be refused.
    if (timestampWrites != null) {
      gpuDescriptor.timestampWrites = timestampWrites;
    }
    final occlusion = _occlusionSet;
    if (occlusion != null) {
      gpuDescriptor.occlusionQuerySet =
          (occlusion.backend as WebGpuQueries).set;
    }
    _pass = _encoder.beginRenderPass(gpuDescriptor);
  }

  /// One colour attachment, with its resolve target where the store action asks
  /// for one.
  ///
  /// **The resolve is the half a translation drops.** `gpuStoreOp` maps
  /// [StoreAction.multisampleResolve] to `"discard"` and
  /// [StoreAction.storeAndMultisampleResolve] to `"store"`, and either of those
  /// alone is a multisampled attachment thrown away or kept and never resolved
  /// — a picture that is stale or black in whatever samples the resolve target
  /// next, with nothing raised anywhere. `gpuResolves` is the other half of the
  /// same answer, and this is its one caller.
  ///
  /// A layer of an array names its view; a slice of a volume is the
  /// attachment's `depthSlice` over the level's `"3d"` view.
  static GPURenderPassColorAttachment _colorAttachment(ColorTarget target) {
    final texture = target.texture.backend as WebGpuTexture;
    final view = texture.attachmentView(
      face: target.face,
      level: target.mipLevel,
      layer: target.layer,
    );
    final clear = _colorOf(target.clearValue);
    // A transient attachment is cleared and discarded whatever the pass
    // asked — `H7`, and see [WebGpuTexture.transient].
    final load = gpuAttachmentLoadOp(
      target.loadAction,
      transient: texture.transient,
    );
    final store = gpuAttachmentStoreOp(
      target.storeAction,
      transient: texture.transient,
    );
    if (texture.isVolume) {
      return GPURenderPassColorAttachment.slice(
        view: view,
        depthSlice: target.layer,
        clearValue: clear,
        loadOp: load,
        storeOp: store,
      );
    }
    final resolve = target.resolveTexture;
    if (!gpuResolves(target.storeAction) || resolve == null) {
      return GPURenderPassColorAttachment(
        view: view,
        clearValue: clear,
        loadOp: load,
        storeOp: store,
      );
    }
    return GPURenderPassColorAttachment.resolving(
      view: view,
      resolveTarget: (resolve.backend as WebGpuTexture).attachmentView(),
      clearValue: clear,
      loadOp: load,
      storeOp: store,
    );
  }

  /// The depth attachment, with a stencil aspect only where the format has one.
  ///
  /// Naming the stencil operations on a depth-only format is an error rather
  /// than a no-op, which is why the interop layer has two constructors and this
  /// asks `TextureFormatStencil.hasStencil` rather than always filling both.
  ///
  /// The depth aspect is loaded or cleared as the descriptor says, and always
  /// stored. Discarding is what a tiler saves bandwidth by; there is no tile
  /// memory here to save, and a stored depth buffer is one a debugger can look
  /// at — and one a later pass may load, which `R8`'s transparent passes do.
  ///
  /// **A read-only aspect names no operations at all**, which WebGPU
  /// requires: `depthReadOnly` is honoured, the load and store actions are
  /// then ignored as the contract says, and the pipelines drawn in the pass
  /// write neither — see [WebGpuRecorder.signatureFor].
  static GPURenderPassDepthStencilAttachment _depthAttachment(
    DepthTarget target,
  ) {
    final texture = target.texture.backend as WebGpuTexture;
    final view = texture.attachmentView(
      face: target.face,
      level: target.mipLevel,
      layer: target.layer,
    );
    final depthLoadOp = gpuLoadOp(target.loadAction);
    // Stored unless it is a transient attachment, which WebGPU will only
    // discard — `H7`: tile memory is exactly the saving the paragraph above
    // says there is none of on an ordinary texture.
    final depthStore = texture.transient ? 'discard' : 'store';
    final stencil = target.texture.format.hasStencil;
    final depthReadOnly = target.depthReadOnly;
    final stencilReadOnly = stencil && target.stencilReadOnly;
    if (depthReadOnly && (!stencil || stencilReadOnly)) {
      return stencil
          ? GPURenderPassDepthStencilAttachment.readOnly(
              view: view,
              depthReadOnly: true,
              stencilReadOnly: true,
            )
          : GPURenderPassDepthStencilAttachment.readOnly(
              view: view,
              depthReadOnly: true,
            );
    }
    if (!stencil) {
      return GPURenderPassDepthStencilAttachment.depthOnly(
        view: view,
        depthClearValue: target.clearValue,
        depthLoadOp: depthLoadOp,
        depthStoreOp: depthStore,
      );
    }
    final stencilClear = StencilState.narrowReference(target.stencilClearValue);
    final stencilLoad = gpuAttachmentLoadOp(
      target.stencilLoadAction,
      transient: texture.transient,
    );
    final stencilStore = gpuAttachmentStoreOp(
      target.stencilStoreAction,
      transient: texture.transient,
    );
    if (depthReadOnly) {
      return GPURenderPassDepthStencilAttachment.depthReadOnly(
        view: view,
        depthReadOnly: true,
        stencilClearValue: stencilClear,
        stencilLoadOp: stencilLoad,
        stencilStoreOp: stencilStore,
      );
    }
    if (stencilReadOnly) {
      return GPURenderPassDepthStencilAttachment.stencilReadOnly(
        view: view,
        depthClearValue: target.clearValue,
        depthLoadOp: depthLoadOp,
        depthStoreOp: depthStore,
        stencilReadOnly: true,
      );
    }
    return GPURenderPassDepthStencilAttachment(
      view: view,
      depthClearValue: target.clearValue,
      depthLoadOp: depthLoadOp,
      depthStoreOp: depthStore,
      stencilClearValue: stencilClear,
      stencilLoadOp: stencilLoad,
      stencilStoreOp: stencilStore,
    );
  }

  static GPUColorDict _colorOf(Vector4? color) => GPUColorDict(
    r: color?.x ?? 0.0,
    g: color?.y ?? 0.0,
    b: color?.z ?? 0.0,
    a: color?.w ?? 0.0,
  );

  late final GPUCommandEncoder _encoder;
  late final GPURenderPassEncoder _pass;
  final QuerySet? _occlusionSet;
  bool _occlusionOpen = false;
  bool _submitted = false;

  @override
  GPURenderCommands get _commands => _pass;

  // -------------------------------------------------- dynamic in WebGPU

  /// Straight through: WebGPU states a viewport from the top left in pixels,
  /// which is where this contract states every rectangle. It is the place the
  /// WebGL2 backend has to turn a rectangle over, and there is nothing to do
  /// here at all.
  @override
  void setViewport(ScreenRect rect) => _pass.setViewport(
    rect.x.toDouble(),
    rect.y.toDouble(),
    rect.width.toDouble(),
    rect.height.toDouble(),
    0.0,
    1.0,
  );

  @override
  void setScissor(ScreenRect rect) =>
      _pass.setScissorRect(rect.x, rect.y, rect.width, rect.height);

  @override
  void setStencilReference(int value) =>
      _pass.setStencilReference(StencilState.narrowReference(value));

  /// Refused, and the refusal is the promise `blend-constant` being absent
  /// from `features` makes.
  ///
  /// WebGPU has `setBlendConstant` and two of the four constant-reading
  /// `BlendFactor` values map straight onto `"constant"` and
  /// `"one-minus-constant"`. The other two are OpenGL's `CONSTANT_ALPHA`, which
  /// this API cannot form in a colour equation at all — so a backend answering
  /// true would promise four factors and honour two. The capability is one
  /// answer for all four, so the honest answer loses the two it could have had.
  @override
  void setBlendColor(Vector4 color) => _device.features.require(
    DeviceFeature.blendConstant,
    backend: _backend,
    reason: _noBlendConstant,
  );

  // ------------------------------------------------------------- queries

  @override
  void beginOcclusionQuery(int queryIndex) {
    _device.features.require(DeviceFeature.occlusionQuery, backend: _backend);
    final set = _occlusionSet;
    if (set == null) {
      throw StateError(
        'beginOcclusionQuery in a pass opened without an occlusionQuerySet',
      );
    }
    if (_occlusionOpen) {
      throw StateError('an occlusion query is already open in this pass');
    }
    if (queryIndex < 0 || queryIndex >= set.count) {
      throw RangeError.range(queryIndex, 0, set.count - 1, 'queryIndex');
    }
    _occlusionOpen = true;
    _pass.beginOcclusionQuery(queryIndex);
  }

  @override
  void endOcclusionQuery() {
    if (!_occlusionOpen) {
      throw StateError('endOcclusionQuery with no occlusion query open');
    }
    _occlusionOpen = false;
    _pass.endOcclusionQuery();
  }

  // TODO(webgpu): pipeline statistics queries — absent from the WebGPU
  // specification; a feature exposing a `"pipeline-statistics"` query type
  // would unblock them.
  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) =>
      _device.features.require(
        DeviceFeature.pipelineStatisticsQuery,
        backend: _backend,
        reason: 'WebGPU has no pipeline statistics queries',
      );

  @override
  void endPipelineStatisticsQuery() => _device.features.require(
    DeviceFeature.pipelineStatisticsQuery,
    backend: _backend,
    reason: 'WebGPU has no pipeline statistics queries',
  );

  // ------------------------------------------------------------- bundles

  /// Replays [bundles]; each must have been recorded against this pass's
  /// attachment formats and sample count. WebGPU unsets the pass's pipeline
  /// and bindings afterwards, and the accumulated bindings go with them.
  @override
  void executeBundles(List<RenderBundle> bundles) {
    _device.features.require(DeviceFeature.renderBundles, backend: _backend);
    for (final bundle in bundles) {
      final d = bundle.descriptor;
      final same =
          d.sampleCount == _sampleCount &&
          d.depthStencilFormat == _depthTextureFormat &&
          d.colorFormats.length == _formats.length &&
          Iterable<int>.generate(
            _formats.length,
          ).every((int i) => d.colorFormats[i] == _formats[i]);
      if (!same) {
        throw ArgumentError.value(
          bundle,
          'bundles',
          'was recorded for other attachments than this pass has',
        );
      }
    }
    _pass.executeBundles(
      <GPURenderBundle>[
        for (final bundle in bundles) (bundle.backend as WebGpuBundle).bundle,
      ].toJS,
    );
    _forgetBindings();
  }

  @override
  void _multiDrawIndirect(
    GPUBuffer arguments,
    int offset,
    int drawCount,
    GPUBuffer? count,
    int countOffset,
  ) => count == null
      ? _pass.multiDrawIndexedIndirect(arguments, offset, drawCount)
      : _pass.multiDrawIndexedIndirect(
          arguments,
          offset,
          drawCount,
          count,
          countOffset,
        );

  @override
  void submit() {
    if (_submitted) throw StateError('this pass has already been submitted');
    if (_occlusionOpen) {
      throw StateError('the pass ends with an occlusion query still open');
    }
    _submitted = true;
    _pass.end();
    _device.guard(
      'the submitted pass',
      () => _device.gpuDevice.queue.submit(
        <GPUCommandBuffer>[_encoder.finish()].toJS,
      ),
    );
    // **Nothing to destroy.** The transient vertices, indices and uniform
    // blocks this pass wrote are ranges of the device's frame arenas, which are
    // rewound at `beginFrame` rather than freed here — see
    // `webgpu_resources.dart` for why that is safe under a frame the GPU has
    // not finished with, and for what the WebGL2 backend does instead.
  }
}

/// Draws recorded into a `GPURenderBundle` — `createRenderBundleEncoder`.
///
/// **A bundle reads the frame arenas as a pass does**, so its transient
/// vertices and uniform blocks are the bytes as they stood when the bundle
/// was recorded only until the next `beginFrame` rewinds the arenas. A bundle
/// meant to be replayed across frames binds geometry the device holds and
/// fills its blocks every frame it is recorded in; one recorded and replayed
/// in the same frame is as safe as the pass beside it.
final class WebGpuBundleEncoder extends WebGpuRecorder
    with RenderBundleEncoder {
  WebGpuBundleEncoder(WebGpuDevice device, this._descriptor)
    : super(
        device,
        colorFormats: _descriptor.colorFormats,
        depthFormat: _descriptor.depthStencilFormat,
        sampleCount: _descriptor.sampleCount,
      ) {
    final colors = gpuStrings(_colorFormats);
    final depth = _depthFormat;
    _bundle = device.gpuDevice.createRenderBundleEncoder(
      depth == null
          ? GPURenderBundleEncoderDescriptor(
              colorFormats: colors,
              sampleCount: _sampleCount,
              label: _descriptor.label ?? 'flutter3d bundle',
            )
          : GPURenderBundleEncoderDescriptor.withDepth(
              colorFormats: colors,
              depthStencilFormat: depth,
              sampleCount: _sampleCount,
              label: _descriptor.label ?? 'flutter3d bundle',
            ),
    );
  }

  final RenderBundleDescriptor _descriptor;
  late final GPURenderBundleEncoder _bundle;
  bool _finished = false;

  @override
  GPURenderCommands get _commands {
    if (_finished) throw StateError('this bundle has been finished');
    return _bundle;
  }

  Never _passOnly(String what) => throw StateError(
    '$what belongs to a pass, not to a bundle: WebGPU records none in one',
  );

  @override
  void setViewport(ScreenRect rect) => _passOnly('setViewport');

  @override
  void setScissor(ScreenRect rect) => _passOnly('setScissor');

  @override
  void setStencilReference(int value) => _passOnly('setStencilReference');

  @override
  void setBlendColor(Vector4 color) => _passOnly('setBlendColor');

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

  /// A bundle has no `multiDrawIndexedIndirect`, so the draws are recorded
  /// one by one; a GPU-written count cannot be honoured that way and is
  /// refused rather than read as [drawCount].
  @override
  void _multiDrawIndirect(
    GPUBuffer arguments,
    int offset,
    int drawCount,
    GPUBuffer? count,
    int countOffset,
  ) {
    if (count != null) {
      throw StateError(
        'a bundle cannot record a multi-draw with a count buffer; replay it '
        'in the pass instead',
      );
    }
    for (var i = 0; i < drawCount; i++) {
      _bundle.drawIndexedIndirect(arguments, offset + i * 20);
    }
  }

  @override
  RenderBundle finish({String? label}) {
    if (_finished) throw StateError('this bundle has already been finished');
    _finished = true;
    final bundle = _device.guard(
      'the finished bundle',
      () => _bundle.finish(
        GPURenderBundleDescriptor(
          label: label ?? _descriptor.label ?? 'flutter3d bundle',
        ),
      ),
    );
    return wrapRenderBundle(
      backend: WebGpuBundle(bundle),
      descriptor: _descriptor,
      label: label ?? _descriptor.label,
    );
  }
}
