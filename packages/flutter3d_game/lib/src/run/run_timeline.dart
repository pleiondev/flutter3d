import 'package:flutter3d_sim/flutter3d_sim.dart';

/// One action taken on a [RunTimeline], kept so a caller can show a history —
/// `rp-02`'s "команды видны в истории", the same log an MCP command stream
/// would replay.
sealed class TimelineCommand {
  const TimelineCommand();
}

/// The run was paused.
final class TimelinePaused extends TimelineCommand {
  const TimelinePaused();
}

/// The run was resumed from a pause.
final class TimelineResumed extends TimelineCommand {
  const TimelineResumed();
}

/// One fixed step was taken while paused.
final class TimelineStepped extends TimelineCommand {
  const TimelineStepped();
}

/// The run was rewound to [step] and released — everything after [step] in
/// the buffer was cut, and the run continues from there.
final class TimelineBranched extends TimelineCommand {
  const TimelineBranched(this.step);
  final int step;
}

/// The level under the run was replaced, taking effect before [step]: the
/// run was replayed from there under the level whose document digests to
/// [levelDigest] (`Level.digestHex`).
///
/// **What makes a run with an edit in it reproducible.** A tape replayed
/// against the old level from the start would part from this run at [step];
/// with this command in hand, a replay swaps the level at the same step and
/// arrives where the run did.
final class TimelineLevelSwapped extends TimelineCommand {
  const TimelineLevelSwapped(this.step, this.levelDigest);
  final int step;
  final String levelDigest;

  @override
  bool operator ==(Object other) =>
      other is TimelineLevelSwapped &&
      other.step == step &&
      other.levelDigest == levelDigest;

  @override
  int get hashCode => Object.hash(step, levelDigest);
}

/// Pause, step, rewind and branch, built on a live [RewindBuffer].
///
/// **What `rp-02`'s editor panel is a face for, not the panel itself.** The
/// scrubber, the checkpoint marks and the buttons above `RunPlaying` are
/// `apps/flutter3d_editor`'s to draw; this is the part underneath that a
/// panel calls into and that a test can drive without one — the same split
/// `WidgetSurfacePipeline` drew for `wg-00`, mechanism proven before the
/// widget that shows it.
///
/// ## The kill camera, generalised
///
/// `apps/flutter3d_demo_dungeon/lib/main.dart`'s `_startKillcam` already does
/// exactly this — restore a keyframe, mute the devices, play the tape forward
/// through the ordinary step, unmute — for one fixed distance (three seconds)
/// and one purpose (a camera that does not take over play). [releaseAt] is
/// that method with the distance and the purpose both handed to the caller:
/// after it returns, the live state *is* the rewound moment and the run goes
/// on from there rather than snapping back, which is what turns a kill camera
/// into a branch.
///
/// ## What this does not do
///
/// It does not write a `.f3drun`. [RewindBuffer.cut] leaves its own recorder
/// holding exactly the frames from the branch point onward, the same
/// `InputTapeRecorder` `_beginDemo`/`_endDemo` already know how to turn into
/// a [Demo] — a second way to do that would be a second thing to keep right.
/// It does not scrub across a *loaded* `.f3drun`'s whole length either — that
/// is a stored [InputTapePlayback] over the file's own tape, replayed from
/// its nearest checkpoint, which has no live devices to mute and does not
/// need this class at all.
final class RunTimeline {
  RunTimeline({
    required this.rewind,
    required this.input,
    required this.stepSim,
    required this.restore,
    this.stepSeconds = 1.0 / 60.0,
  });

  /// Where the recent past is kept, and what [releaseAt] cuts.
  final RewindBuffer rewind;

  /// The live devices — muted during the fast-forward inside [releaseAt], the
  /// same way `_startKillcam` mutes them.
  final InputState input;

  /// Runs one fixed step of the actual simulation.
  final void Function(double dt) stepSim;

  /// Puts a snapshot back into the live objects.
  final void Function(Snapshot snapshot) restore;

  /// The fixed step, in seconds, [stepOnce] and [releaseAt] advance by.
  final double stepSeconds;

  bool _paused = false;

  /// Whether [stepOnce] may be called — the transport is paused rather than
  /// running live.
  bool get isPaused => _paused;

  final List<TimelineCommand> _history = <TimelineCommand>[];

  /// Every command this timeline has carried out, oldest first.
  List<TimelineCommand> get history =>
      List<TimelineCommand>.unmodifiable(_history);

  void pause() {
    if (_paused) return;
    _paused = true;
    _history.add(const TimelinePaused());
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _history.add(const TimelineResumed());
  }

  /// Runs one fixed step. Only while [isPaused] — a step taken on a running
  /// timeline would be a second step nobody asked for, on top of whatever is
  /// driving the loop already.
  void stepOnce() {
    if (!_paused) {
      throw StateError('stepOnce is only valid while the timeline is paused');
    }
    input.beginStep();
    stepSim(stepSeconds);
    input.endStep();
    _history.add(const TimelineStepped());
  }

  /// Where a scrub to [secondsAgo] would land, without moving anything —
  /// what a scrubber previews as a person drags it, before they let go.
  RewindPoint? preview(double secondsAgo) => rewind.rewindBy(secondsAgo);

  /// Rewinds the live state to [point] and lets the run continue from there:
  /// what a person asked for by dragging the scrubber to [point] and letting
  /// go.
  ///
  /// Restores [point]'s keyframe, replays the frames from there to [point]
  /// through the ordinary step with the live devices muted — so a key held
  /// during the drag does not leak into the replay — then [RewindBuffer.cut]s
  /// the buffer at [point]. The timeline is left running (not paused): a
  /// release is asking to keep playing from here, not to pause on arrival —
  /// call [pause] afterwards for that.
  void releaseAt(RewindPoint point) {
    restore(point.snapshot);
    final toPoint = InputTapePlayback(point.tapeToPoint);
    final wasMuted = input.muted;
    input.muted = true;
    try {
      while (!toPoint.isFinished) {
        toPoint.applyTo(input);
        input.beginStep();
        stepSim(stepSeconds);
        input.endStep();
      }
    } finally {
      input.muted = wasMuted;
    }
    rewind.cut(point);
    _paused = false;
    _history.add(TimelineBranched(point.step));
  }

  /// Replaces the level under the run without the run jumping: [swap] puts
  /// the new level in place, and the steps since the last keyframe are lived
  /// again under it, so the present is one the new level could have led to.
  ///
  /// **For the half of an edit the simulation reads** — brushes, entities,
  /// the ground (`LevelDiff.simulation`). Swapped in place, a crate moved in
  /// the editor would teleport mid-run, and nothing replaying the tape could
  /// reach that state. Swapped here, the keyframe is restored, [swap] runs,
  /// and the recorded input plays forward with the live devices muted, as
  /// [releaseAt] plays it; at most one keyframe interval is replayed. The
  /// buffer is then rebased on that keyframe (`RewindBuffer.rebaseAt`),
  /// since nothing held on either side of it belongs to the new level.
  ///
  /// [swap] must replace only what the snapshots do not carry — the level,
  /// its colliders, what it spawned at load — and leave what they do carry to
  /// the restore. With no keyframe yet held, [swap] runs at once, as at the
  /// first step of a run.
  ///
  /// Returns the step the new level took effect before, which is what
  /// [TimelineLevelSwapped] records.
  int swapLevel(void Function() swap, {required String levelDigest}) {
    final point = rewind.rewindTo(rewind.step);
    if (point == null) {
      swap();
      _history.add(TimelineLevelSwapped(rewind.step, levelDigest));
      return rewind.step;
    }
    restore(point.snapshot);
    swap();
    final replay = InputTapePlayback(point.tapeToPoint);
    final wasMuted = input.muted;
    input.muted = true;
    try {
      while (!replay.isFinished) {
        replay.applyTo(input);
        input.beginStep();
        stepSim(stepSeconds);
        input.endStep();
      }
    } finally {
      input.muted = wasMuted;
    }
    rewind.rebaseAt(point);
    final at = point.step - point.replayed;
    _history.add(TimelineLevelSwapped(at, levelDigest));
    return at;
  }

  /// [releaseAt], given the step directly rather than a [RewindPoint] —
  /// what a caller across a wire has, since a step number survives being
  /// sent as a string and a [RewindPoint] does not. Returns whether the
  /// buffer still reached that far back; false leaves the timeline
  /// untouched, the same as [preview] returning null.
  bool releaseAtStep(int step) {
    final point = rewind.rewindTo(step);
    if (point == null) return false;
    releaseAt(point);
    return true;
  }
}
