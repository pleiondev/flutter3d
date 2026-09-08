/// Recording one pass on WebGPU, and the accumulation that makes it possible.
///
/// **The whole of this file is the second divergence `command_encoder.dart`
/// already names.** It says rasteriser state is per draw on Impeller and per
/// pipeline on Vulkan, and that "a Vulkan backend must accumulate these calls
/// and look a pipeline up at `PassEncoder.draw` rather than at
/// `PassEncoder.bindPipeline`". WebGPU is the same API shape as Vulkan here, so
/// that paragraph turned out to describe this backend too — written before there
/// was one to check it against. Nothing in the contract changes; what changes is
/// where the work happens, and how many pipeline objects a frame builds.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' show Vector4;
import 'package:web/web.dart' as web;

import 'webgpu_conventions.dart';
import 'webgpu_interop.dart';
import 'webgpu_spike_device.dart';

/// Where the spike's own vertex attributes sit, because nothing can be asked.
///
/// **This map is the reflection gap, in the smallest form it takes.**
/// `InputAttribute.name` is a name because "the two hardware backends disagree
/// about which is authoritative and both agree about names" — Impeller resolves
/// one through `impellerc`'s reflection, WebGL2 through `getAttribLocation`. A
/// `GPUShaderModule` answers neither: WGSL carries `@location(0)` and the name
/// is gone by the time the browser sees it. So a backend needs the map, and the
/// only place it can come from is the bundle. This spike hard-codes the two its
/// own WGSL declares, which is exactly as far as hard-coding gets anybody.
const Map<String, int> spikeAttributeLocations = <String, int>{
  'position': 0,
  'colour': 1,
};

/// A pass, recorded and submitted.
final class WebGpuSpikeEncoder implements CommandEncoder {
  WebGpuSpikeEncoder(this._device, RenderPassDescriptor descriptor)
    : _colorFormats = <String>[
        for (final target in descriptor.colors)
          gpuTextureFormat(target.texture.format)!,
      ],
      _sampleCount = descriptor.colors.first.texture.sampleCount {
    if (descriptor.depth != null) {
      throw UnimplementedError(
        'ordinary work this spike did not do: a depth-stencil attachment. '
        'WebGPU takes the depth clear value, the two stencil actions and the '
        'stencil clear the contract already carries, so nothing here is a '
        'question for the contract.',
      );
    }
    _encoder = _device.gpuDevice.createCommandEncoder();
    _pass = _encoder.beginRenderPass(
      GPURenderPassDescriptor(
        colorAttachments: <GPURenderPassColorAttachment>[
          for (final target in descriptor.colors)
            GPURenderPassColorAttachment(
              view: (target.texture.backend as WebGpuSpikeTexture).texture
                  .createView(),
              clearValue: _clearOf(target.clearValue),
              loadOp: gpuLoadOp(target.loadAction),
              storeOp: gpuStoreOp(target.storeAction),
            ),
        ].toJS,
      ),
    );
  }

  static GPUColorDict _clearOf(Vector4? colour) => GPUColorDict(
    r: colour?.x ?? 0.0,
    g: colour?.y ?? 0.0,
    b: colour?.z ?? 0.0,
    a: colour?.w ?? 0.0,
  );

  final WebGpuSpikeDevice _device;
  final List<String> _colorFormats;
  final int _sampleCount;

  /// **A pass starts covering the whole of its attachment, and here that is
  /// free.** WebGPU's own default viewport and scissor are the attachment, so
  /// there is nothing to set and nothing to remember the size for — which is why
  /// this encoder carries no width or height while the WebGL2 one carries both
  /// to turn every rectangle over with.

  late final GPUCommandEncoder _encoder;
  late final GPURenderPassEncoder _pass;

  // The accumulated state. Mutable because it is state: every setter below
  // writes one of these and the draw reads all of them.
  WebGpuSpikePipeline? _pipeline;
  PrimitiveType _primitive = PrimitiveType.triangle;
  CullMode _cull = CullMode.none;
  WindingOrder _winding = WindingOrder.counterClockwise;
  CompareFunction _depthCompare = CompareFunction.always;
  bool _depthWrite = true;
  BlendState? _blend;

  final Map<int, GPUBuffer> _vertexBuffers = <int, GPUBuffer>{};
  GPUBuffer? _indexBuffer;
  IndexType _indexType = IndexType.int32;
  int _indexCount = 0;

  /// Buffers made for this pass alone, destroyed when it is submitted.
  final List<GPUBuffer> _transient = <GPUBuffer>[];

  bool _submitted = false;

  // ------------------------------------------------------ dynamic in WebGPU

  /// Straight through: WebGPU states a viewport from the top left, in pixels,
  /// which is where the contract states every rectangle. This is the place the
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
  /// The device answers false because two of the four constant-reading factors
  /// have no WebGPU spelling, and the contract says a backend that answers false
  /// throws from here rather than drawing the term as zero.
  @override
  void setBlendColor(Vector4 color) => throw UnsupportedError(
    'this backend answers false to supportsBlendColor: WebGPU has "constant" '
    'and "one-minus-constant" and no equivalent of CONSTANT_ALPHA, so two of '
    'the four factors BlendFactor names cannot be formed. See '
    'webgpuContractGaps.',
  );

  // -------------------------------------------------- accumulated for later

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

  /// [attachment] is honoured in principle and ignored here.
  ///
  /// WebGPU gives every colour target its own blend equation in the pipeline,
  /// so it is the one of the four backends that could honour the index without
  /// an optional extension — which is worth recording, because
  /// `PassEncoder.setBlend` currently calls the index "a hint until" the WebGL2
  /// extension and a capability arrive. This spike draws into one attachment and
  /// keys on one equation.
  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    if (state != null && state.usesBlendColor) {
      throw UnsupportedError(
        'this backend answers false to supportsBlendColor, and the state names '
        'one of the four factors that read the constant. See '
        'webgpuContractGaps.',
      );
    }
    _blend = state;
  }

  /// Refused. WebGPU has no polygon fill mode, so [PolygonMode.line] is the
  /// answer `supportsWireframe` being false already promised.
  @override
  void setPolygonMode(PolygonMode mode) {
    if (mode == PolygonMode.fill) return;
    throw UnsupportedError(
      'WebGPU cannot draw PolygonMode.line: there is no polygon fill mode in '
      'the API. Wireframe means line primitives and an index buffer to match, '
      'which is a decision for the renderer.',
    );
  }

  @override
  void setStencil(StencilState front, {StencilState? back}) =>
      throw UnimplementedError(
        'ordinary work this spike did not do: the stencil is a field of the '
        'depth-stencil state of a GPURenderPipeline, so it joins the key the '
        'draw looks a pipeline up by. Every operation and compare the contract '
        'names has a WebGPU spelling — see gpuStencilOperation.',
      );

  @override
  void bindPipeline(PipelineHandle pipeline) {
    _pipeline = pipeline.backend as WebGpuSpikePipeline;
    // Bindings do not survive a pipeline change, which the contract states and
    // this honours literally rather than by accident.
    _vertexBuffers.clear();
    _indexBuffer = null;
    _indexCount = 0;
  }

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) => _vertexBuffers[slot] = (buffer.backend as WebGpuSpikeBuffer).buffer;

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      _vertexBuffers[slot] = _upload(bytes, web.$GPUBufferUsage.VERTEX);

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    _indexBuffer = (buffer.backend as WebGpuSpikeBuffer).buffer;
    _indexType = type;
    _indexCount = indexCount;
  }

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    _indexBuffer = _upload(bytes, web.$GPUBufferUsage.INDEX);
    _indexType = type;
    _indexCount = indexCount;
  }

  GPUBuffer _upload(ByteData bytes, int usage) {
    final buffer = _device.gpuDevice.createBuffer(
      GPUBufferDescriptor(
        size: (bytes.lengthInBytes + 3) & ~3,
        usage: usage | web.$GPUBufferUsage.COPY_DST,
      ),
    );
    _device.gpuDevice.queue.writeBuffer(
      buffer,
      0,
      gpuWritableBytes(bytes).toJS,
    );
    _transient.add(buffer);
    return buffer;
  }

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) => throw UnimplementedError(
    'a uniform block needs a bind group, and a bind group needs the @group and '
    '@binding numbers WGSL carries at compile time and drops before run time — '
    'so "the block called $blockName" is a question nothing here can answer. '
    'The member offsets are the easy half: every uniform in the engine is a '
    'float vector, a matrix or an array of either, and WGSL lays those out '
    'exactly as std140 does. See webgpuContractGaps.',
  );

  @override
  void bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerOptions? sampler,
  }) => throw UnimplementedError(
    'a sampler slot is a name, and WGSL keeps none: the same gap as '
    'bindUniformBlock, reached from the other side. A null sampler would mean '
    'SamplerOptions.linearRepeat here as everywhere. See webgpuContractGaps.',
  );

  @override
  void clearBindings() {
    _vertexBuffers.clear();
    _indexBuffer = null;
    _indexCount = 0;
  }

  // ------------------------------------------------------------- the draw

  @override
  void draw({int instanceCount = 1}) {
    if (instanceCount == 0) return;
    final pipeline = _pipeline;
    if (pipeline == null) {
      throw StateError('a draw with no pipeline bound');
    }
    if (_indexBuffer == null) {
      throw StateError(
        'a draw with no index buffer bound; every draw in this engine is '
        'indexed',
      );
    }
    _pass.setPipeline(_realPipeline(pipeline));
    for (final entry in _vertexBuffers.entries) {
      _pass.setVertexBuffer(entry.key, entry.value);
    }
    _pass
      ..setIndexBuffer(_indexBuffer!, gpuIndexFormat(_indexType))
      ..drawIndexed(_indexCount, instanceCount);
  }

  /// The key this draw's state makes, which is also what the pipeline cache is
  /// consulted with.
  WebGpuPipelineKey keyFor(WebGpuSpikePipeline pipeline) => WebGpuPipelineKey(
    pipeline: pipeline.name,
    topology: gpuPrimitiveTopology(_primitive),
    cullMode: gpuCullMode(_cull),
    frontFace: gpuFrontFace(_winding),
    depthCompare: gpuCompareFunction(_depthCompare),
    depthWrite: _depthWrite,
    blend: _blend,
    colorFormats: _colorFormats,
    depthFormat: null,
    sampleCount: _sampleCount,
  );

  GPURenderPipeline _realPipeline(WebGpuSpikePipeline pipeline) {
    final key = keyFor(pipeline);
    final made = _device.pipelines[key];
    if (made != null) return made;

    final blend = _blend;
    final built = _device.gpuDevice.createRenderPipeline(
      GPURenderPipelineDescriptor(
        layout: 'auto'.toJS,
        vertex: GPUVertexState(
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
                      shaderLocation: _locationOf(attribute.name),
                    ),
                ].toJS,
              ),
          ].toJS,
        ),
        fragment: GPUFragmentState(
          module: pipeline.fragment.module,
          entryPoint: pipeline.fragment.entryPoint,
          targets: <GPUColorTargetState>[
            for (final format in _colorFormats)
              if (blend == null)
                GPUColorTargetState.opaque(format: format)
              else
                GPUColorTargetState(
                  format: format,
                  blend: _blendStateOf(blend),
                ),
          ].toJS,
        ),
        primitive: GPUPrimitiveState(
          topology: key.topology,
          cullMode: key.cullMode,
          frontFace: key.frontFace,
        ),
      ),
    );
    _device.pipelines[key] = built;
    return built;
  }

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

  static int _locationOf(String name) {
    final location = spikeAttributeLocations[name];
    if (location == null) {
      throw UnimplementedError(
        'no @location is known for the vertex input "$name". A backend reads '
        'this out of the bundle; this spike knows only what its own WGSL '
        'declares. See webgpuContractGaps.',
      );
    }
    return location;
  }

  @override
  void submit() {
    if (_submitted) throw StateError('this pass has already been submitted');
    _submitted = true;
    _pass.end();
    _device.gpuDevice.queue.submit(<GPUCommandBuffer>[_encoder.finish()].toJS);
    for (final buffer in _transient) {
      buffer.destroy();
    }
    _transient.clear();
  }
}
