/// What a `PipelineHandle` holds on this backend: the pair it links, and the
/// linked pipeline while it is.
///
/// **flutter_gpu may refuse a pipeline twice over.** `createRenderPipeline`
/// throws when it cannot make the descriptor, and on OpenGL ES — the
/// fallback an Adreno phone without Vulkan lands on — the link is lazy, so a
/// pair the driver will not link is accepted there and refused at the first
/// draw, as `Exception: Failed to append drawIndexed`. Both used to escape:
/// the first from `createPipeline`, the second from `PassEncoder.draw`, and
/// either one failed every frame.
///
/// Each is now a report to `GraphicsDevice.pipelineRefusals`. The linked
/// object is dropped after a refusal and built again at the next bind, until
/// the record says the pipeline is left refused; then nothing is built and
/// the encoder skips its draws.
///
/// Generic over the linked object, and free of flutter_gpu, so the decisions
/// are tested without a GPU: the backend makes one over
/// `gpu.RenderPipeline`, `gpu_pipeline_test.dart` one over `String`.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'gpu_capabilities.dart' show impellerBackendName;

/// One pipeline `createPipeline` handed out, linked on demand.
final class GpuPipeline<T extends Object> {
  GpuPipeline(this.name, this._build);

  /// `vertex+fragment`, as the handle names it.
  final String name;

  final T Function() _build;
  T? _linked;

  /// The linked pipeline, linking it first when it is not: at creation, and
  /// at the bind after a refusal dropped it.
  ///
  /// Null when the pipeline cannot be had now — left refused by [refusals],
  /// even one linked before, or refused by this link, which is reported
  /// there — and the draws that follow its bind are skipped.
  T? linked(
    PipelineHandle handle,
    PipelineRefusals refusals, {
    required bool deviceLost,
  }) {
    // The record first, whatever was linked: a pipeline it leaves refused is
    // skipped on every backend, built or not.
    if (refusals.isRefused(handle)) return null;
    final linked = _linked;
    if (linked != null) return linked;
    try {
      return _linked = _build();
    } on Exception catch (error) {
      refusals.report(handle, _refusal(error, deviceLost: deviceLost));
      return null;
    }
  }

  /// The driver refused a draw with this pipeline: [error] is what
  /// flutter_gpu threw. Reported, and the linked object dropped, so the next
  /// bind builds it again.
  void refusedAtDraw(
    PipelineHandle handle,
    PipelineRefusals refusals,
    Object error, {
    required bool deviceLost,
  }) {
    _linked = null;
    refusals.report(handle, _refusal(error, deviceLost: deviceLost));
  }

  PipelineRefused _refusal(Object error, {required bool deviceLost}) =>
      PipelineRefused(
        pipeline: name,
        backend: impellerBackendName,
        // flutter_gpu says only that it failed, never why: a compile and a
        // link refusal read the same, and a link is the one the field met.
        reason: deviceLost
            ? PipelineRefusalReason.deviceLost
            : PipelineRefusalReason.link,
        detail: '$error',
        cause: error,
      );
}

/// Whether [error], thrown by flutter_gpu's `draw` or `drawIndexed`, is the
/// driver refusing the bound pipeline rather than a mistake in the bindings.
///
/// flutter_gpu has one sentence for a draw its native side would not append,
/// and the reason it would not is the pipeline: everything else the call
/// checks (a sparse vertex slot, a negative count) is thrown before it, as a
/// `StateError` or a `RangeError`.
bool isRefusedDraw(Object error) =>
    error is Exception && '$error'.contains('Failed to append draw');
