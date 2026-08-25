/// One flutter_gpu command buffer with one open pass.
///
/// The two are fused because Metal allows a single open encoder per buffer and
/// flutter_gpu offers no way to end a pass, so every site in this engine has
/// always been one buffer, one pass, one submit. See the note on
/// `CommandEncoder`.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'gpu_device.dart';
import 'gpu_formats.dart';
import 'gpu_texture.dart';

final class GpuCommandEncoder implements CommandEncoder {
  GpuCommandEncoder(this._buffer, this._pass, this._backend, this._frame);

  final GpuFrame _frame;

  final gpu.CommandBuffer _buffer;
  final gpu.RenderPass _pass;

  /// This frame's uniform allocator, captured when the pass opened.
  /// Who owns the frame's transient storage, and the arithmetic that keeps a
  /// write inside a block.
  final GpuRenderBackend _backend;

  gpu.BufferView _emplace(ByteData bytes) => _backend.emplace(bytes);

  @override
  void setViewport(ScreenRect rect) => _pass.setViewport(
        gpu.Viewport(
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
        ),
      );

  @override
  void setScissor(ScreenRect rect) => _pass.setScissor(
        gpu.Scissor(
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
        ),
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
  /// `Material.depthWrite` is a promise this backend could not keep until now.
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
  void setDepthWrite(bool enabled) => _pass.setDepthWriteEnable(enabled);

  @override
  void setDepthCompare(CompareFunction compare) =>
      _pass.setDepthCompareOperation(compare.toGpu());

  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
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
  void bindVertexBuffer(GeometryBuffer buffer, int vertexCount,
          {int slot = 0}) =>
      _pass.bindVertexBuffer(_view(buffer), slot: slot);

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      _pass.bindVertexBuffer(_emplace(bytes), slot: slot);

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    _pass.bindIndexBuffer(_view(buffer), type.toGpu());
    _indexCount = indexCount;
  }

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    _pass.bindIndexBuffer(_emplace(bytes), type.toGpu());
    _indexCount = indexCount;
  }

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    final slot =
        (shader.backend as gpu.Shader).getUniformSlot(blockName);
    final size = slot.sizeInBytes;
    if (size == null || size == 0) return false;

    final data = ByteData(size);
    members.forEach((name, values) {
      final offset = slot.getMemberOffsetInBytes(name);
      if (offset == null) return;
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

  @override
  void bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerOptions? sampler,
  }) {
    // Tile memory cannot be sampled, and the backend's own assertion for this
    // fires from inside `bindTexture` with no idea which slot or which pass.
    // The handle carries the storage mode, so this can be said here, where the
    // slot name is in scope and the message names the mistake.
    assert(
      texture.storageMode != StorageMode.deviceTransient,
      'the "$slot" slot was handed a deviceTransient texture, which lives in '
      'tile memory and can only ever be an attachment',
    );
    _pass.bindTexture(
      (shader.backend as gpu.Shader).getUniformSlot(slot),
      texture.gpuTexture,
      sampler: (sampler ?? SamplerOptions.linearRepeat).toGpu(),
    );
  }

  @override
  void clearBindings() {
    _pass.clearBindings();
    // The count is a binding like any other. Leaving it behind would let a
    // draw after a `clearBindings` inherit the previous mesh's index count,
    // which is the kind of state leak that draws a plausible wrong picture.
    _indexCount = 0;
  }

  @override
  void draw({int instanceCount = 1}) {
    if (_indexCount == 0 || instanceCount <= 0) return;
    _pass.drawIndexed(_indexCount, instanceCount: instanceCount);
  }

  @override
  void submit() => _buffer.submit(completionCallback: (bool ok) {
        _frame.outstanding--;
        _frame.settleIfDone();
      });

  static gpu.BufferView _view(GeometryBuffer buffer) => gpu.BufferView(
        buffer.backend as gpu.DeviceBuffer,
        offsetInBytes: buffer.offsetInBytes,
        lengthInBytes: buffer.lengthInBytes,
      );
}
