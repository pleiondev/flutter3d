/// What the GPU spent on each labelled pass of a frame — `H2`.
///
/// The CPU side of a frame is measured where it is encoded; the GPU side can
/// only be read back once the GPU is done, which is a frame or two later. So
/// it arrives through `GraphicsDevice.onGpuTimings` rather than in the frame's
/// own result, tagged with the frame it belongs to.
library;

/// One labelled pass and how long the GPU spent in it.
final class GpuPassTiming {
  const GpuPassTiming({required this.label, required this.micros});

  /// `RenderPassDescriptor.label` of the pass, or the compute pass's label.
  final String label;

  /// Between the pass's first and last command on the GPU, in microseconds.
  final int micros;
}

/// Every labelled pass of one frame, in the order they were submitted.
final class GpuFrameTimings {
  const GpuFrameTimings({required this.frame, required this.passes});

  /// Which frame, counted by `GraphicsDevice.beginFrame` from the first.
  final int frame;

  final List<GpuPassTiming> passes;
}
