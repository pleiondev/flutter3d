/// One flutter_gpu command buffer with one open pass.
///
/// The two are fused because Metal allows a single open encoder per buffer and
/// flutter_gpu offers no way to end a pass, so every site in this engine has
/// always been one buffer, one pass, one submit. See the note on
/// `CommandEncoder`.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapability;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' show Vector4;

import 'gpu_device.dart';
import 'gpu_formats.dart';
import 'gpu_frame.dart';
import 'gpu_texture.dart';

/// [CommandEncoder] over one flutter_gpu command buffer with its one open
/// pass — see the library comment on why the two are fused. [submit] is the
/// end of both: it hands the buffer to the queue and moves the frame's
/// accounting from "encoding" to "outstanding".
final class GpuCommandEncoder extends PassEncoder with CommandEncoder {
  GpuCommandEncoder(
    this._buffer,
    this._pass,
    this._backend,
    this._frame, {
    this._depthReadOnly = false,
    this._stencilReadOnly = false,
  }) {
    if (_depthReadOnly) _pass.setDepthWriteEnable(false);
  }

  /// `DepthTarget.depthReadOnly`: the attachment is loaded and stored as it
  /// was (see `GpuRenderBackend._toRenderTarget`) and no draw of this pass
  /// writes it, whatever [setDepthWrite] asks.
  final bool _depthReadOnly;

  /// `DepthTarget.stencilReadOnly`: every stencil state this pass sets has
  /// its write mask cleared.
  final bool _stencilReadOnly;

  final GpuFrame _frame;

  DeviceFeatures get _features => _backend.features;

  final gpu.CommandBuffer _buffer;
  final gpu.RenderPass _pass;

  /// This frame's uniform allocator, captured when the pass opened.
  /// Who owns the frame's transient storage, and the arithmetic that keeps a
  /// write inside a block.
  final GpuRenderBackend _backend;

  gpu.BufferView _emplace(ByteData bytes) => _backend.emplace(bytes);

  @override
  void setViewport(ScreenRect rect) => _pass.setViewport(
    gpu.Viewport(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
  );

  @override
  void setScissor(ScreenRect rect) => _pass.setScissor(
    gpu.Scissor(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
  );

  @override
  void setPrimitiveType(PrimitiveType type) =>
      _pass.setPrimitiveType(type.toGpu());

  @override
  void setPolygonMode(PolygonMode mode) => _pass.setPolygonMode(mode.toGpu());

  @override
  void setCullMode(CullMode mode) => _pass.setCullMode(mode.toGpu());

  @override
  void setWindingOrder(WindingOrder order) =>
      _pass.setWindingOrder(order.toGpu());

  /// **`false` does not work, and the reason is not here.**
  ///
  /// **Fixed upstream, and this note is kept because what it says was true.**
  /// Until recently `flutter_gpu`'s native setter ignored its argument and
  /// wrote the literal `true`, so the call could only ever switch depth writes
  /// *on*. As of the SDK this repository builds with (3.47.0, pinned in
  /// `mise.toml`) it passes the flag through:
  ///
  /// ```cpp
  /// // bin/cache/pkg/flutter_gpu/render_pass.cc:560
  /// void InternalFlutterGpu_RenderPass_SetDepthWriteEnable(
  ///     flutter::gpu::RenderPass* wrapper,
  ///     bool enable) {
  ///   auto& depth = wrapper->GetDepthAttachmentDescriptor();
  ///   depth.depth_write_enabled = enable;
  /// }
  /// ```
  ///
  /// Worth knowing rather than deleting, for two reasons. It is the whole
  /// argument for `PassState`'s fields being optional — a redundant
  /// `setDepthWrite(false)` flipped behaviour on two backends out of three
  /// while this bug was live — and it is what a backdrop rests on:
  /// `RenderMaterial.depthWrite` is a promise this backend could not keep until now.
  ///
  /// **Settled on a machine with a GPU, and the note it replaces was wrong.**
  /// `particle-stack` used to be recorded deliberately showing the broken
  /// picture — eight additive particles at one point drawing as one, a burst
  /// about three per cent dim — and this docstring said so. Checked directly:
  /// the recorded frame shows the stack as a blown-out core with a warm halo,
  /// which is eight particles accumulating, and the cross-backend budget puts
  /// it 0.431% from the software rasteriser, the same noise floor every other
  /// scene sits at. The rasteriser honours `depthWrite` in its own code, so
  /// agreement to that tolerance is the flag arriving here too. Nothing is
  /// pending.
  @override
  void setDepthWrite({required bool enabled}) =>
      _pass.setDepthWriteEnable(enabled && !_depthReadOnly);

  /// Nothing — `P7`: flutter_gpu has no alpha-to-coverage to set; `supportsAlphaToCoverage` is false.
  @override
  void setAlphaToCoverage({required bool enabled}) {}

  @override
  void setDepthCompare(CompareFunction compare) =>
      _pass.setDepthCompareOperation(compare.toGpu());

  /// One call for both faces when they agree, two when they do not.
  ///
  /// flutter_gpu's own default for `targetFace` is `both`, and a fresh
  /// `RenderPass` starts with the test off on both — so a pass that never
  /// reaches here is exactly the pass this backend drew before the stencil
  /// existed, byte for byte.
  @override
  void setStencil(StencilState front, {StencilState? back}) {
    if (back == null) {
      _pass.setStencilConfig(_stencilOf(front));
      return;
    }
    _pass.setStencilConfig(
      _stencilOf(front),
      targetFace: StencilFace.front.toGpu(),
    );
    _pass.setStencilConfig(
      _stencilOf(back),
      targetFace: StencilFace.back.toGpu(),
    );
  }

  /// A fresh config per call (see `StencilStateToGpu`), so clearing its
  /// write mask for a read-only stencil touches nothing shared.
  gpu.StencilConfig _stencilOf(StencilState state) {
    final config = state.toGpu();
    if (_stencilReadOnly) config.writeMask = 0;
    return config;
  }

  @override
  void setStencilReference(int value) =>
      _pass.setStencilReference(StencilState.narrowReference(value));

  /// **A state naming the blend constant is refused here rather than drawn.**
  ///
  /// flutter_gpu's `RenderPass` has no blend-constant setter — there is no
  /// native behind `SetBlendColor` to bind — so this backend answers false to
  /// `GraphicsDevice.supportsBlendColor`, and the promise that false carries is
  /// this throw. Handing the four factors on to `ColorBlendEquation` is what
  /// this used to do, and Impeller multiplies them by its own untouched
  /// default, transparent black: the term evaluates to zero and the frame is a
  /// plausible picture with a term missing from it, on the one backend a phone
  /// actually runs.
  ///
  /// The two 1.0 refusals sit beside it for the same reason: a factor or an
  /// operation flutter_gpu has no value for is refused by the feature it
  /// needs, rather than reaching `toGpu` mid-draw.
  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    if (state != null) {
      if (state.usesBlendColor) {
        // TODO(impeller): no blend-constant setter on flutter_gpu's
        // RenderPass — unblocked by an upstream RenderPass.setBlendConstant.
        throw UnsupportedCapability(
          DeviceFeature.blendConstant,
          backend: impellerBackendName,
          reason:
              'this blend state names a BlendFactor that reads a blend '
              'constant, and flutter_gpu has no way to set one. Drawing it '
              'anyway would multiply by transparent black and lose the term '
              'with no error',
        );
      }
      if (state.usesDualSource) {
        // TODO(impeller): no second-source BlendFactor in flutter_gpu —
        // unblocked by upstream dual-source blending.
        throw UnsupportedCapability(
          DeviceFeature.dualSourceBlending,
          backend: impellerBackendName,
          reason: 'flutter_gpu has no second-source blend factors',
        );
      }
      if (state.usesMinMax) {
        // TODO(impeller): flutter_gpu's BlendOperation has no min or max —
        // unblocked by upstream adding them.
        throw UnsupportedCapability(
          DeviceFeature.minMaxBlend,
          backend: impellerBackendName,
          reason: 'flutter_gpu has no min or max blend operation',
        );
      }
    }
    _pass.setColorBlendEnable(state != null, colorAttachmentIndex: attachment);
    if (state == null) return;
    _pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: state.colorOperation.toGpu(),
        sourceColorBlendFactor: state.sourceColorFactor.toGpu(),
        destinationColorBlendFactor: state.destinationColorFactor.toGpu(),
        alphaBlendOperation: state.alphaOperation.toGpu(),
        sourceAlphaBlendFactor: state.sourceAlphaFactor.toGpu(),
        destinationAlphaBlendFactor: state.destinationAlphaFactor.toGpu(),
      ),
      colorAttachmentIndex: attachment,
    );
  }

  /// Refused, because there is nothing to call.
  ///
  /// Every other setter here is one `RenderPass` method away; this one has no
  /// method, and no native symbol behind one — `InternalFlutterGpu_RenderPass_*`
  /// has no `SetBlendColor` at SDK 3.47. A silent no-op would leave the
  /// constant at Impeller's own transparent black and the caller believing it
  /// had been set, which is the whole reason
  /// `GraphicsDevice.supportsBlendColor` exists to be asked first.
  // TODO(impeller): no blend-constant setter on flutter_gpu's RenderPass —
  // unblocked by an upstream RenderPass.setBlendConstant.
  @override
  Never setBlendColor(Vector4 color) => throw UnsupportedCapability(
    DeviceFeature.blendConstant,
    backend: impellerBackendName,
    reason:
        'flutter_gpu has no blend-constant setter; ask before naming '
        'BlendFactor.blendColor and the three beside it',
  );

  @override
  void bindPipeline(PipelineHandle pipeline) {
    // Every binding this pass has been handed dies here, and it is not
    // housekeeping — it is the fix for a monster drawn as a splinter.
    //
    // flutter_gpu's RenderPass accumulates uniform and texture bindings in a
    // map keyed by the *shader* that bound them, and replays the whole map at
    // every draw. Nothing removes an entry when the pipeline changes, so after
    // a skinned mesh has drawn, a static mesh's draw replays the skinned
    // stage's FrameInfo and SkinInfo as well as its own — two buffers claiming
    // one slot, and which of them wins is the iteration order of an
    // unordered_map. The corruption is deterministic within a run and moves
    // when the scene does: a crypt's frog collapsing to a sliver, a box drawn
    // somewhere its transform never was — but only ever in scenes that mix
    // skinned and static pipelines, which is why a monster alone in a test
    // scene was always innocent.
    //
    // Dropping the bindings on a pipeline switch is safe because of the
    // contract written on [CommandEncoder.bindPipeline]: every site binds what
    // its draw needs after binding the pipeline, never before.
    _pass.clearBindings();
    _indexCount = 0;
    _indexView = null;
    _pass.bindPipeline(pipeline.backend as gpu.RenderPipeline);
  }

  /// How many indices the last index bind described.
  ///
  /// flutter_gpu 3.47 moved the counts off the binds and onto the draw. The HAL
  /// keeps them on the binds — that is where the other two backends put them,
  /// and where the count is actually known — so this remembers the one the draw
  /// will need. Zero means nothing has been bound, which [draw] treats as
  /// nothing to do rather than as an error: the same thing `flutter_gpu` did
  /// when the count travelled with the binding.
  int _indexCount = 0;

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) => _pass.bindVertexBuffer(_view(buffer), slot: slot);

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      _pass.bindVertexBuffer(_emplace(bytes), slot: slot);

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) =>
      _bindIndices(_view(buffer), type, indexCount);

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) =>
      _bindIndices(_emplace(bytes), type, indexCount);

  void _bindIndices(gpu.BufferView view, IndexType type, int indexCount) {
    _pass.bindIndexBuffer(view, type.toGpu());
    _indexView = view;
    _indexType = type;
    _indexCount = indexCount;
    _boundFirstIndex = 0;
  }

  /// The view the last index bind named, kept so a draw of a window can bind
  /// a narrower one — `P7`. flutter_gpu's `drawIndexed` takes a count and no
  /// first index, so where the window starts is said with the view's offset.
  gpu.BufferView? _indexView;
  IndexType _indexType = IndexType.int32;

  /// Where the view bound on the pass right now starts, in indices from the
  /// start of [_indexView]. A window draw moves it, and the next draw that
  /// wants a different start binds again rather than reading from wherever
  /// the last window left it.
  int _boundFirstIndex = 0;

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    // `gfx-92n`: a block the compiled stage dropped is refused here, before
    // anything reaches the driver — binding one is a native crash on Metal.
    if (!shader.mayBindBlock(blockName)) return false;
    final slot = (shader.backend as gpu.Shader).getUniformSlot(blockName);
    final size = slot.sizeInBytes;
    if (size == null || size == 0) return false;

    final data = ByteData(size);
    members.forEach((name, values) {
      final offset = slot.getMemberOffsetInBytes(name);
      // Loud, because silence here is indistinguishable from working: the
      // member the caller wrote leaves zeros in its place, and zero is a
      // plausible value for most of them — a shadow strength of zero is a
      // scene with no shadows and no error anywhere.
      //
      // Not the same as a missing *block*, which is above and is false: a
      // compiler drops a whole block nothing reads, and that is ordinary.
      // Having the block and not the member means the two ends disagree about
      // its shape, which is worth stopping for. The web backend has always
      // stopped for it; this one used to `return`, so the same bundle was a
      // named exception in a browser and a wrong picture on a phone.
      if (offset == null) {
        throw StateError(
          'uniform block "$blockName" has no member "$name". The engine and '
          'the shader disagree about this block. Impeller reflects a block\'s '
          'members from the compiled binary, so a member renamed in the GLSL '
          'and not in the caller, or a bundle built from other sources, '
          'arrives here.',
        );
      }
      // Refused by name, as WebGL and WebGPU refuse it. It used to write on:
      // an overrun short of the end landed on the next member's offset, a wrong
      // picture with no error, and one past the end was an anonymous
      // RangeError from `setFloat32` naming neither block nor member.
      if (offset + values.length * 4 > size) {
        throw StateError(
          'uniform block "$blockName" member "$name" wants ${values.length} '
          'floats at byte $offset, past the block\'s $size bytes. std140 pads '
          'array elements to sixteen bytes; a tightly packed array of scalars '
          'overruns exactly like this.',
        );
      }
      // Whole arrays written from their reflected base offset. Impeller
      // reflects the array, not its elements — `lights[0]` comes back null —
      // but the std140 stride for a vec4 array is a flat 16 bytes, so a
      // contiguous write lands each element correctly.
      for (var i = 0; i < values.length; i++) {
        data.setFloat32(offset + i * 4, values[i], Endian.host);
      }
    });

    _pass.bindUniform(slot, _emplace(data));
    return true;
  }

  /// False when the stage declares no sampler [slot], which flutter_gpu
  /// reports by throwing "Failed to bind texture" after its native bind
  /// returned false. Caught here and answered as the contract says, so the
  /// same mistake is the same bool on every backend; it was the one uncaught
  /// throw of 0.7.0 to 0.7.2, at the first draw of every polyline.
  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    // Gated first, before the slot is looked at: a sampler flutter_gpu
    // cannot describe is refused whatever it was going to be bound to.
    // `depthAddressMode` needs no gate — it addresses a 3D texture's depth,
    // and there are no 3D textures here to sample.
    if (sampler != null && sampler.usesExtendedState) _refuseSampler(sampler);
    if (!shader.mayBindSampler(slot)) return false;
    // Tile memory cannot be sampled, and the backend's own assertion for this
    // fires from inside `bindTexture` with no idea which slot or which pass.
    // The handle carries the storage mode, so this can be said here, where the
    // slot name is in scope and the message names the mistake.
    assert(
      texture.storageMode != StorageMode.deviceTransient,
      'the "$slot" slot was handed a deviceTransient texture, which lives in '
      'tile memory and can only ever be an attachment',
    );
    try {
      _pass.bindTexture(
        (shader.backend as gpu.Shader).getUniformSlot(slot),
        texture.gpuTexture,
        sampler: (sampler ?? SamplerDescriptor.linearRepeat).toGpu(),
      );
      return true;
    } on Exception catch (error) {
      if ('$error'.contains('Failed to bind texture')) return false;
      rethrow;
    }
  }

  @override
  void clearBindings() {
    _pass.clearBindings();
    // The count is a binding like any other. Leaving it behind would let a
    // draw after a `clearBindings` inherit the previous mesh's index count,
    // which is the kind of state leak that draws a plausible wrong picture.
    _indexCount = 0;
    _indexView = null;
  }

  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) {
    final window = indexWindow(
      _indexCount,
      firstIndex: firstIndex,
      indexCount: indexCount,
    );
    final view = _indexView;
    if (window.count == 0 || instanceCount <= 0 || view == null) return;
    if (window.first != _boundFirstIndex) {
      final skip = window.first * (_indexType == IndexType.int16 ? 2 : 4);
      _pass.bindIndexBuffer(
        gpu.BufferView(
          view.buffer,
          offsetInBytes: view.offsetInBytes + skip,
          lengthInBytes: view.lengthInBytes - skip,
        ),
        _indexType.toGpu(),
      );
      _boundFirstIndex = window.first;
    }
    _pass.drawIndexed(window.count, instanceCount: instanceCount);
  }

  /// The refusal for a sampler [SamplerDescriptor.usesExtendedState] says
  /// flutter_gpu cannot describe, by the first feature it needs.
  // TODO(impeller): flutter_gpu's SamplerDescriptor has filters, address modes
  // and anisotropy only — comparison, LOD clamps and border colours are
  // unblocked by upstream fields for them (Impeller's own SamplerDescriptor
  // has the first two).
  Never _refuseSampler(SamplerDescriptor sampler) {
    final (feature, what) = switch (sampler) {
      SamplerDescriptor(compare: final CompareFunction _) => (
        DeviceFeature.samplerCompare,
        'a comparison sampler',
      ),
      SamplerDescriptor(borderColor: final SamplerBorderColor _) => (
        DeviceFeature.samplerBorderColor,
        'a border colour',
      ),
      _ => (DeviceFeature.samplerLodClamp, 'a level-of-detail clamp'),
    };
    throw UnsupportedCapability(
      feature,
      backend: impellerBackendName,
      reason: "flutter_gpu's SamplerOptions has no $what",
    );
  }

  // ------------------------------------------------- the 1.0 surface

  /// [draw], when the base vertex and first instance are zero — which is
  /// all flutter_gpu's `drawIndexed` takes.
  @override
  void drawIndexed(IndexedDraw draw) {
    if (draw.usesBaseVertexOrInstance) _refuseBaseVertexOrInstance();
    this.draw(
      instanceCount: draw.instanceCount,
      firstIndex: draw.firstIndex,
      indexCount: draw.indexCount,
    );
  }

  // TODO(impeller): flutter_gpu's draw and drawIndexed take a count and an
  // instance count only — unblocked by upstream base vertex / first
  // instance (first vertex) arguments on them.
  Never _refuseBaseVertexOrInstance() => throw UnsupportedCapability(
    DeviceFeature.baseVertexBaseInstance,
    backend: impellerBackendName,
    reason:
        'flutter_gpu draws take no base vertex, first vertex or first '
        'instance',
  );

  /// A loop of [drawIndexed], which the contract allows: one call per entry,
  /// with every entry checked before the first is drawn so a refusal leaves
  /// nothing half-recorded.
  @override
  void multiDraw(List<IndexedDraw> draws) {
    _features.require(DeviceFeature.multiDraw, backend: impellerBackendName);
    if (draws.any((IndexedDraw d) => d.usesBaseVertexOrInstance)) {
      _refuseBaseVertexOrInstance();
    }
    for (final entry in draws) {
      drawIndexed(entry);
    }
  }

  // TODO(impeller): flutter_gpu has no indirect draw — unblocked by an
  // upstream RenderPass.drawIndexedIndirect (and a compute pass to write
  // the arguments, flutter/flutter#188480).
  Never _noIndirect(DeviceFeature feature) => throw UnsupportedCapability(
    feature,
    backend: impellerBackendName,
    reason: 'flutter_gpu has no indirect draw',
  );

  @override
  void multiDrawIndirect(
    StorageBuffer arguments,
    int drawCount, {
    int offsetInBytes = 0,
    StorageBuffer? countBuffer,
    int countOffsetInBytes = 0,
  }) => _noIndirect(DeviceFeature.multiDrawIndirect);

  @override
  void drawIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) =>
      _noIndirect(DeviceFeature.indirectDraw);

  // TODO(impeller): no render bundles in flutter_gpu — see
  // `GpuRenderBackend.createRenderBundleEncoder`.
  @override
  void executeBundles(List<RenderBundle> bundles) => _features.require(
    DeviceFeature.renderBundles,
    backend: impellerBackendName,
    reason: 'flutter_gpu has no render bundles',
  );

  // TODO(impeller): flutter_gpu has no query objects — unblocked by an
  // upstream query-set API.
  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) =>
      _features.require(
        DeviceFeature.pipelineStatisticsQuery,
        backend: impellerBackendName,
        reason: 'flutter_gpu has no pipeline-statistics queries',
      );

  @override
  void endPipelineStatisticsQuery() => _features.require(
    DeviceFeature.pipelineStatisticsQuery,
    backend: impellerBackendName,
    reason: 'flutter_gpu has no pipeline-statistics queries',
  );

  @override
  void beginOcclusionQuery(int queryIndex) => _features.require(
    DeviceFeature.occlusionQuery,
    backend: impellerBackendName,
    reason: 'flutter_gpu has no occlusion queries',
  );

  @override
  void endOcclusionQuery() => _features.require(
    DeviceFeature.occlusionQuery,
    backend: impellerBackendName,
    reason: 'flutter_gpu has no occlusion queries',
  );

  // TODO(impeller): flutter_gpu's RenderPass has no depth-bias setter —
  // unblocked by an upstream RenderPass.setDepthBias (Impeller's own
  // pipeline descriptor has one).
  @override
  void setDepthBias(DepthBias bias) => _features.require(
    DeviceFeature.depthBias,
    backend: impellerBackendName,
    reason: "flutter_gpu's RenderPass has no depth-bias setter",
  );

  // TODO(impeller): flutter_gpu's ColorBlendEquation carries no write mask —
  // unblocked by an upstream colour write mask on it (Impeller's
  // ColorAttachmentDescriptor has one).
  @override
  void setColorWriteMask(ColorWriteMask mask, {int attachment = 0}) =>
      _features.require(
        DeviceFeature.colorWriteMask,
        backend: impellerBackendName,
        reason: 'flutter_gpu has no colour write mask',
      );

  // TODO(impeller): flutter_gpu exposes no depth clip mode — unblocked by an
  // upstream RenderPass.setDepthClamp / depth-clip control.
  @override
  void setDepthClamp({required bool enabled}) => _features.require(
    DeviceFeature.depthClamp,
    backend: impellerBackendName,
    reason: 'flutter_gpu has no depth clamp',
  );

  // TODO(impeller): flutter_gpu binds uniforms and samplers only — storage
  // buffers and textures in a render stage are unblocked by an upstream
  // storage binding on RenderPass.
  Never _noRenderStorage() => throw UnsupportedCapability(
    DeviceFeature.renderStageStorage,
    backend: impellerBackendName,
    reason: 'flutter_gpu binds no storage to a render stage',
  );

  @override
  bool bindStorageBuffer(
    ShaderHandle shader,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) => _noRenderStorage();

  @override
  bool bindStorageTexture(
    ShaderHandle shader,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  }) => _noRenderStorage();

  /// [bytes] as the block, as laid out by impellerc: flutter_gpu's
  /// `bindUniform` takes a view of bytes and nothing else, so this is
  /// [bindUniformBlock] without the member arithmetic. Shorter than the
  /// block is zero-padded, the way the member path leaves what it does not
  /// write; longer is refused by name.
  @override
  bool bindUniformBytes(ShaderHandle shader, String blockName, ByteData bytes) {
    _features.require(DeviceFeature.uniformBytes, backend: impellerBackendName);
    if (!shader.mayBindBlock(blockName)) return false;
    final slot = (shader.backend as gpu.Shader).getUniformSlot(blockName);
    final size = slot.sizeInBytes;
    if (size == null || size == 0) return false;
    if (bytes.lengthInBytes > size) {
      throw StateError(
        'uniform block "$blockName" is $size bytes and was handed '
        '${bytes.lengthInBytes}',
      );
    }
    final block = ByteData(size);
    for (var i = 0; i < bytes.lengthInBytes; i++) {
      block.setUint8(i, bytes.getUint8(i));
    }
    _pass.bindUniform(slot, _emplace(block));
    return true;
  }

  /// flutter_gpu's `draw`: [vertexCount] vertices in order, the bound index
  /// buffer left where it is. A first vertex or first instance is refused —
  /// flutter_gpu's draw takes neither, and moving the vertex buffers would
  /// leave `gl_VertexIndex` counting from zero.
  @override
  void drawNonIndexed({
    required int vertexCount,
    int firstVertex = 0,
    int instanceCount = 1,
    int firstInstance = 0,
  }) {
    _features.require(
      DeviceFeature.nonIndexedDraw,
      backend: impellerBackendName,
    );
    if (firstVertex != 0 || firstInstance != 0) _refuseBaseVertexOrInstance();
    if (vertexCount < 0 || instanceCount < 0) {
      throw RangeError(
        'drawNonIndexed: $vertexCount vertices, $instanceCount instances',
      );
    }
    if (vertexCount == 0 || instanceCount == 0) return;
    _pass.draw(vertexCount, instanceCount: instanceCount);
  }

  @override
  void submit() {
    // From "being encoded" to "in the queue". Two counters rather than one,
    // because a frame that threw between these two states must not be waited
    // for — see `GpuFrame.encoding`.
    _frame.encoding--;
    _frame.outstanding++;
    _buffer.submit(
      completionCallback: (bool ok) {
        // **`ok` used to be bound and never read**, which meant a command
        // buffer the driver refused produced exactly the same accounting, the
        // same `FrameResult` and the same draw count as one that ran. In a
        // codebase whose whole argument is that failures here arrive as a
        // plausible frame with correct counters, throwing away the one boolean
        // the API offers about it was the wrong trade. Counted always, said
        // out loud in debug.
        if (!ok) {
          _backend.noteRejectedSubmission();
          assert(() {
            debugPrint(
              'flutter3d: the GPU refused a command buffer. The frame it '
              'belonged to is missing whatever that pass drew, and nothing '
              'above the driver reports it — see '
              'GpuRenderBackend.rejectedSubmissions.',
            );
            return true;
          }());
        }
        _frame.outstanding--;
        _frame.settleIfDone();
      },
    );
  }

  static gpu.BufferView _view(GeometryBuffer buffer) => gpu.BufferView(
    buffer.backend as gpu.DeviceBuffer,
    offsetInBytes: buffer.offsetInBytes,
    lengthInBytes: buffer.lengthInBytes,
  );
}
