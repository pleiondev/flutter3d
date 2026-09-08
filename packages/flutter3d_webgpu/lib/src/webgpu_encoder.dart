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
/// [WebGpuEncoder.setPrimitiveType], [WebGpuEncoder.setCullMode],
/// [WebGpuEncoder.setWindingOrder], [WebGpuEncoder.setDepthWrite],
/// [WebGpuEncoder.setDepthCompare] and [WebGpuEncoder.setBlend]. The stencil is
/// a seventh, and the vertex layout an eighth that never was a setter at all.
/// Together with the attachment formats and the sample count — which the pass
/// knew when it was opened — they make [WebGpuPipelineSignature], and the map
/// behind it is what turns a pass of eighty draws into a handful of pipeline
/// objects.
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
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import 'webgpu_bundle_section.dart';
import 'webgpu_device.dart';
import 'webgpu_formats.dart';
import 'webgpu_interop.dart';
import 'webgpu_pipeline_cache.dart';
import 'webgpu_resources.dart';
import 'webgpu_types.dart';

/// One pass, recorded and submitted.
final class WebGpuEncoder implements CommandEncoder {
  WebGpuEncoder(this._device, RenderPassDescriptor descriptor)
    : _colorFormats = <String>[
        for (final target in descriptor.colors)
          gpuTextureFormat(target.texture.format)!,
      ],
      _blends = <BlendState?>[for (final _ in descriptor.colors) null],
      _depthFormat = descriptor.depth == null
          ? null
          : gpuTextureFormat(descriptor.depth!.texture.format),
      _sampleCount = descriptor.colors.isNotEmpty
          ? descriptor.colors.first.texture.sampleCount
          : (descriptor.depth?.texture.sampleCount ?? 1) {
    final colors = <GPURenderPassColorAttachment>[
      for (final target in descriptor.colors) _colorAttachment(target),
    ];
    final depth = descriptor.depth;
    _encoder = _device.gpuDevice.createCommandEncoder();
    _pass = _encoder.beginRenderPass(
      depth == null
          ? GPURenderPassDescriptor(
              colorAttachments: colors.toJS,
              label: 'flutter3d pass',
            )
          : GPURenderPassDescriptor.withDepth(
              colorAttachments: colors.toJS,
              depthStencilAttachment: _depthAttachment(depth),
              label: 'flutter3d pass',
            ),
    );
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
  static GPURenderPassColorAttachment _colorAttachment(ColorTarget target) {
    final texture = target.texture.backend as WebGpuTexture;
    final view = texture.attachmentView(
      face: target.face,
      level: target.mipLevel,
    );
    final clear = _colorOf(target.clearValue);
    final load = gpuLoadOp(target.loadAction);
    final store = gpuStoreOp(target.storeAction);
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
  /// The depth aspect is cleared on entry and stored on exit. The contract says
  /// every pass in this engine clears and discards, and discarding is what a
  /// tiler saves bandwidth by; there is no tile memory here to save, and a
  /// stored depth buffer is one a debugger can look at.
  static GPURenderPassDepthStencilAttachment _depthAttachment(
    DepthTarget target,
  ) {
    final view = (target.texture.backend as WebGpuTexture).attachmentView();
    if (!target.texture.format.hasStencil) {
      return GPURenderPassDepthStencilAttachment.depthOnly(
        view: view,
        depthClearValue: target.clearValue,
        depthLoadOp: 'clear',
        depthStoreOp: 'store',
      );
    }
    return GPURenderPassDepthStencilAttachment(
      view: view,
      depthClearValue: target.clearValue,
      depthLoadOp: 'clear',
      depthStoreOp: 'store',
      stencilClearValue: StencilState.narrowReference(target.stencilClearValue),
      stencilLoadOp: gpuLoadOp(target.stencilLoadAction),
      stencilStoreOp: gpuStoreOp(target.stencilStoreAction),
    );
  }

  static GPUColorDict _colorOf(Vector4? colour) => GPUColorDict(
    r: colour?.x ?? 0.0,
    g: colour?.y ?? 0.0,
    b: colour?.z ?? 0.0,
    a: colour?.w ?? 0.0,
  );

  final WebGpuDevice _device;
  final List<String> _colorFormats;
  final String? _depthFormat;
  final int _sampleCount;

  late final GPUCommandEncoder _encoder;
  late final GPURenderPassEncoder _pass;

  // The accumulated state. Mutable because it is state: every setter writes one
  // of these and the draw reads all of them.
  WebGpuPipelineProgram? _pipeline;
  PrimitiveType _primitive = PrimitiveType.triangle;
  CullMode _cull = CullMode.none;
  WindingOrder _winding = WindingOrder.counterClockwise;
  CompareFunction _depthCompare = CompareFunction.always;
  bool _depthWrite = true;
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

  bool _submitted = false;

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

  /// Refused, and the refusal is the promise `supportsBlendColor` makes.
  ///
  /// WebGPU has `setBlendConstant` and two of the four constant-reading
  /// `BlendFactor` values map straight onto `"constant"` and
  /// `"one-minus-constant"`. The other two are OpenGL's `CONSTANT_ALPHA`, which
  /// this API cannot form in a colour equation at all — so a backend answering
  /// true would promise four factors and honour two. The capability is one
  /// answer for all four, so the honest answer loses the two it could have had.
  @override
  void setBlendColor(Vector4 color) => throw UnsupportedError(
    'this backend answers false to supportsBlendColor: WebGPU has "constant" '
    'and "one-minus-constant" and no equivalent of CONSTANT_ALPHA, so two of '
    'the four factors BlendFactor names cannot be formed',
  );

  // ---------------------------------------------- accumulated for the draw

  @override
  void setPrimitiveType(PrimitiveType type) => _primitive = type;

  @override
  void setCullMode(CullMode mode) => _cull = mode;

  @override
  void setWindingOrder(WindingOrder order) => _winding = order;

  @override
  void setDepthWrite(bool enabled) => _depthWrite = enabled;

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
  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    if (attachment < 0 || attachment >= _blends.length) {
      throw ArgumentError.value(
        attachment,
        'attachment',
        'is not one of this pass\'s ${_blends.length} colour attachments',
      );
    }
    if (state != null && state.usesBlendColor) {
      throw UnsupportedError(
        'this backend answers false to supportsBlendColor, and the state names '
        'one of the four factors that read the constant',
      );
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
    throw UnsupportedError(
      'WebGPU cannot draw PolygonMode.line: there is no polygon fill mode in '
      'the API',
    );
  }

  // --------------------------------------------------------- the bindings

  @override
  void bindPipeline(PipelineHandle pipeline) {
    _pipeline = pipeline.backend as WebGpuPipelineProgram;
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
    final stage = shader.backend as WebGpuStageProgram;
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

    _blocks.putIfAbsent(
      block.group,
      () => <int, WebGpuSlice>{},
    )[block.binding] = _device.uniformArena.write(
      ByteData.sublistView(data),
    );
    return true;
  }

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
  /// A slot the translator dropped is ignored rather than refused, which is
  /// what the WebGL2 backend does for the same reason: the engine gates its
  /// call sites on what a material's lighting model declares, and a stage that
  /// legitimately optimised a sampler away is not a caller mistake.
  ///
  /// A null [sampler] is `SamplerOptions.linearRepeat` — the contract's
  /// default, not the constructor's, which is nearest and clamp and which cost
  /// a third backend two percent of every textured golden before the rule was
  /// written down.
  @override
  void bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerOptions? sampler,
  }) {
    final stage = shader.backend as WebGpuStageProgram;
    final declared = stage.samplerNamed(slot);
    if (declared == null) return;

    final backend = texture.backend as WebGpuTexture;
    assert(
      backend.sampleable,
      'the "$slot" slot was handed a texture that is multisampled or '
      'deviceTransient, which on this backend is allocated without '
      'TEXTURE_BINDING and can only ever be an attachment',
    );
    _views.putIfAbsent(
      declared.group,
      () => <int, GPUTextureView>{},
    )[declared.textureBinding] = backend.sampledView;
    _samplers.putIfAbsent(
      declared.group,
      () => <int, GPUSampler>{},
    )[declared.samplerBinding] = _device.samplerFor(
      sampler ?? SamplerOptions.linearRepeat,
    );
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

  // ------------------------------------------------------------- the draw

  @override
  void draw({int instanceCount = 1}) {
    if (instanceCount == 0) return;
    final pipeline = _pipeline;
    if (pipeline == null) {
      throw StateError('a draw with no pipeline bound');
    }
    final indices = _indexBuffer;
    if (indices == null) {
      throw StateError(
        'a draw with no index buffer bound; every draw in this engine is '
        'indexed',
      );
    }

    final layouts = _device.bindingsFor(pipeline);
    _pass.setPipeline(_realPipeline(pipeline, layouts));
    for (var group = 0; group < layouts.groups.length; group++) {
      final shape = layouts.shapes[group];
      if (shape.isEmpty) continue;
      _pass.setBindGroup(
        group,
        _device.bindGroupFor(
          layouts,
          group,
          _blocks[group],
          _views[group],
          _samplers[group],
        ),
        <JSNumber>[
          for (final block in shape.blocks)
            (_blocks[group]?[block.binding]?.offset ?? 0).toJS,
        ].toJS,
      );
    }
    for (final entry in _vertexBuffers.entries) {
      _pass.setVertexBuffer(
        entry.key,
        entry.value.buffer,
        entry.value.offset,
        entry.value.length,
      );
    }
    _pass
      ..setIndexBuffer(
        indices.buffer,
        gpuIndexFormat(_indexType),
        indices.offset,
        indices.length,
      )
      ..drawIndexed(_indexCount, instanceCount);
  }

  /// The signature this draw's state makes, which is what the cache is
  /// consulted with.
  ///
  /// Public because `webgpu_encoder_test.dart` asserts on it directly: the
  /// question "do these two draws want two pipelines" is answerable without
  /// counting what the browser built, and a test that could only count would
  /// pass on a backend that had stopped honouring the key and happened to build
  /// two anyway.
  WebGpuPipelineSignature signatureFor(WebGpuPipelineProgram pipeline) {
    final strip =
        _primitive == PrimitiveType.triangleStrip ||
        _primitive == PrimitiveType.lineStrip;
    return WebGpuPipelineSignature(
      pipeline: pipeline.name,
      vertexLayout: webgpuVertexLayoutFingerprint(pipeline.layout),
      topology: gpuPrimitiveTopology(_primitive),
      stripIndexFormat: strip ? gpuIndexFormat(_indexType) : null,
      cullMode: gpuCullMode(_cull),
      frontFace: gpuFrontFace(_winding),
      depthCompare: gpuCompareFunction(_depthCompare),
      depthWrite: _depthWrite,
      stencil: webgpuStencilFingerprint(_stencilFront, _stencilBack),
      blends: _blends,
      colorFormats: _colorFormats,
      depthFormat: _depthFormat,
      sampleCount: _sampleCount,
    );
  }

  GPURenderPipeline _realPipeline(
    WebGpuPipelineProgram pipeline,
    WebGpuBindingLayouts layouts,
  ) {
    final signature = signatureFor(pipeline);
    return _device.pipelines.get(
      signature,
      () => _device.guard(
        'the pipeline for $signature',
        () => _buildPipeline(pipeline, layouts, signature),
      ),
    );
  }

  GPURenderPipeline _buildPipeline(
    WebGpuPipelineProgram pipeline,
    WebGpuBindingLayouts layouts,
    WebGpuPipelineSignature signature,
  ) {
    final vertex = GPUVertexState(
      module: pipeline.vertex.module,
      entryPoint: pipeline.vertex.entryPoint,
      buffers: <GPUVertexBufferLayout>[
        for (final buffer in pipeline.layout.buffers)
          GPUVertexBufferLayout(
            arrayStride: buffer.strideInBytes,
            stepMode: gpuVertexStepMode(buffer.stepMode),
            attributes: <GPUVertexAttribute>[
              for (final attribute in buffer.attributes)
                GPUVertexAttribute(
                  format: gpuVertexFormat(attribute.format),
                  offset: attribute.offsetInBytes,
                  shaderLocation: pipeline.locationOf(attribute.name),
                ),
            ].toJS,
          ),
      ].toJS,
    );
    final fragment = GPUFragmentState(
      module: pipeline.fragment.module,
      entryPoint: pipeline.fragment.entryPoint,
      targets: <GPUColorTargetState>[
        for (var i = 0; i < _colorFormats.length; i++)
          if (_blends[i] case final BlendState blend)
            GPUColorTargetState(
              format: _colorFormats[i],
              blend: _blendStateOf(blend),
              writeMask: GpuColorWrite.all,
            )
          else
            GPUColorTargetState.opaque(
              format: _colorFormats[i],
              writeMask: GpuColorWrite.all,
            ),
      ].toJS,
    );
    final primitive = signature.stripIndexFormat == null
        ? GPUPrimitiveState(
            topology: signature.topology,
            cullMode: signature.cullMode,
            frontFace: signature.frontFace,
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
          );
    final multisample = GPUMultisampleState(
      count: _sampleCount,
      mask: 0xFFFFFFFF,
      alphaToCoverageEnabled: false,
    );

    final depthFormat = _depthFormat;
    if (depthFormat == null) {
      return _device.gpuDevice.createRenderPipeline(
        GPURenderPipelineDescriptor.withoutDepth(
          layout: layouts.pipelineLayout,
          vertex: vertex,
          fragment: fragment,
          primitive: primitive,
          multisample: multisample,
          label: pipeline.name,
        ),
      );
    }
    final front = _stencilFront ?? StencilState.disabled;
    final back = _stencilBack ?? front;
    return _device.gpuDevice.createRenderPipeline(
      GPURenderPipelineDescriptor(
        layout: layouts.pipelineLayout,
        vertex: vertex,
        fragment: fragment,
        primitive: primitive,
        multisample: multisample,
        depthStencil: GPUDepthStencilState(
          format: depthFormat,
          depthWriteEnabled: _depthWrite,
          depthCompare: gpuCompareFunction(_depthCompare),
          stencilFront: _faceStateOf(front),
          stencilBack: _faceStateOf(back),
          // Pipeline state here and dynamic in the contract's wording only for
          // the reference value — which is why `setStencilReference` reaches
          // the pass and these two do not.
          stencilReadMask: front.readMask,
          stencilWriteMask: front.writeMask,
          depthBias: 0,
          depthBiasSlopeScale: 0.0,
          depthBiasClamp: 0.0,
        ),
        label: pipeline.name,
      ),
    );
  }

  static GPUStencilFaceState _faceStateOf(StencilState state) =>
      GPUStencilFaceState(
        compare: gpuCompareFunction(state.compare),
        failOp: gpuStencilOperation(state.failOp),
        depthFailOp: gpuStencilOperation(state.depthFailOp),
        passOp: gpuStencilOperation(state.passOp),
      );

  static GPUBlendState _blendStateOf(BlendState state) => GPUBlendState(
    color: GPUBlendComponent(
      operation: gpuBlendOperation(state.colorOperation),
      srcFactor: gpuBlendFactor(state.sourceColorFactor)!,
      dstFactor: gpuBlendFactor(state.destinationColorFactor)!,
    ),
    alpha: GPUBlendComponent(
      operation: gpuBlendOperation(state.alphaOperation),
      srcFactor: gpuBlendFactor(state.sourceAlphaFactor)!,
      dstFactor: gpuBlendFactor(state.destinationAlphaFactor)!,
    ),
  );

  @override
  void submit() {
    if (_submitted) throw StateError('this pass has already been submitted');
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
