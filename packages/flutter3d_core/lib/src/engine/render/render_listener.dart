/// What a renderer tells whoever is listening after each frame.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show BusEvent, EventDigestSink, EventRegistry;

import 'frame_graph.dart' show SkippedPass;
import 'frame_pacing.dart';
import 'frame_result.dart';

export 'frame_pacing.dart' show FramePipelineStall, PipelineStall;

/// Callbacks a `Renderer` calls after each frame it draws — set on
/// `Renderer.listener`.
///
/// **For drawing only.** Every callback runs after the frame is finished and
/// submitted, with the frame's own [FrameResult]. A listener may log, count,
/// show a HUD or lower a quality setting for the *next* frame's
/// `RenderSettings`. It must not change the simulation: a replay is the same
/// inputs stepped the same way, and if a callback fed what the renderer saw
/// back into the world, the replay would depend on a device's timing and on
/// which passes it could run, and stop holding. The renderer does not
/// enforce this and cannot; it is the contract.
///
/// Every field is optional, and a field left null costs nothing.
///
/// **A thin adapter over the bus, when the game has one.** The engine's way
/// to hear the renderer is its event bus: [RenderListener.toBus] makes the
/// listener that publishes each callback as its typed event — [FrameDrawn],
/// [FramePassSkipped], [FrameOverTime] — on the frame channel, since a
/// frame is drawn outside any step. `Renderer.listener` stays the one field
/// it is set on, and a listener written with callbacks still works.
final class RenderListener {
  /// Publishes every frame's news onto [bus]: each skipped pass, the frame
  /// over [frameBudget] when one is given, then the frame drawn.
  factory RenderListener.toBus(EventRegistry bus, {Duration? frameBudget}) =>
      RenderListener(
        drawn: (result) => bus.publish(FrameDrawn(result)),
        skipped: (pass) => bus.publish(FramePassSkipped(pass)),
        overTime: (result, budget) =>
            bus.publish(FrameOverTime(result, budget)),
        stalled: (stall) => bus.publish(FramePipelineStall(stall)),
        held: (result) => bus.publish(FrameHeld(result)),
        frameBudget: frameBudget,
      );

  const RenderListener({
    this.drawn,
    this.skipped,
    this.overTime,
    this.stalled,
    this.held,
    this.frameBudget,
  });

  /// Called once for each entry of [FrameResult.pipelineStalls], before
  /// [skipped]: a pipeline build over `FramePacing.stallThreshold`, with the
  /// material and geometry that asked for it — `A1.7`.
  final void Function(PipelineStall stall)? stalled;

  /// Called instead of everything else for a frame the renderer held because
  /// the GPU was behind — [FrameResult.held] — `A1.4`. [drawn] is not
  /// called for it: nothing was drawn.
  final void Function(FrameResult result)? held;

  /// Called once per frame with the frame's result, after [skipped] and
  /// [overTime] have been told about it.
  final void Function(FrameResult result)? drawn;

  /// Called once for each entry of [FrameResult.skipped], in its order: a
  /// pass that did not run, a step switched off through
  /// `RenderSettings.without`, or a request the frame declined — each with
  /// its `PassSkip` reason, which tells them apart.
  final void Function(SkippedPass pass)? skipped;

  /// Called when the frame took longer than [frameBudget] on the CPU, with
  /// the frame and the budget it went over.
  ///
  /// Measured by [FrameResult.cpuMicros], the wall-clock time inside
  /// `Renderer.render`, which already includes [FrameResult.submitMicros];
  /// adding the two would count the submit twice. Not the GPU's time: the
  /// frame is still executing when this number is taken.
  final void Function(FrameResult result, Duration budget)? overTime;

  /// The CPU time a frame may take before [overTime] is called. Null, the
  /// default, never calls it.
  final Duration? frameBudget;

  /// Tells this listener about [result]: [skipped] per entry, [overTime] if
  /// it went over, then [drawn].
  void notify(FrameResult result) {
    if (result.held) {
      held?.call(result);
      return;
    }
    final onStalled = stalled;
    if (onStalled != null) {
      for (final stall in result.pipelineStalls) {
        onStalled(stall);
      }
    }
    final onSkipped = skipped;
    if (onSkipped != null) {
      for (final pass in result.skipped) {
        onSkipped(pass);
      }
    }
    final budget = frameBudget;
    final onOverTime = overTime;
    if (budget != null &&
        onOverTime != null &&
        result.cpuMicros > budget.inMicroseconds) {
      onOverTime(result, budget);
    }
    drawn?.call(result);
  }
}

/// A frame was drawn: [RenderListener.drawn], on the bus. About the picture,
/// never the run.
final class FrameDrawn extends BusEvent {
  const FrameDrawn(this.result);

  final FrameResult result;

  @override
  String get name => 'render.drawn';
}

/// A frame was held rather than drawn, the GPU being behind:
/// [RenderListener.held], on the bus. Nothing in the digest, since whether
/// the GPU fell behind is the machine's, not the run's.
final class FrameHeld extends BusEvent {
  const FrameHeld(this.result);

  final FrameResult result;

  @override
  String get name => 'render.held';
}

/// A pass did not run, with why: [RenderListener.skipped], on the bus.
final class FramePassSkipped extends BusEvent {
  const FramePassSkipped(this.pass);

  final SkippedPass pass;

  @override
  String get name => 'render.skipped';

  @override
  void digestInto(EventDigestSink sink) => sink
    ..add(pass.name)
    ..add(pass.reason.name);
}

/// A frame took longer than its budget on the CPU:
/// [RenderListener.overTime], on the bus.
final class FrameOverTime extends BusEvent {
  const FrameOverTime(this.result, this.budget);

  final FrameResult result;
  final Duration budget;

  @override
  String get name => 'render.overTime';

  @override
  void digestInto(EventDigestSink sink) => sink.add(budget.inMicroseconds);
}
