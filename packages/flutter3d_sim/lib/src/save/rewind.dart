import '../input/input_tape.dart';
import 'snapshot.dart';

/// The last few seconds of a run, kept so they can be lived again.
///
/// **A demo with its middle kept, not its start.** A [Demo] is where a run
/// began and everything since; this is where the run was a few seconds ago,
/// every step of the way, and it forgets the rest as it goes. What the two
/// share is the arithmetic: a state and the intents after it reproduce the
/// states between, exactly, so the buffer stores one snapshot a second and a
/// few bytes a step where storing a snapshot every step would cost sixty times
/// the memory for nothing anyone can see.
///
/// What it buys, in the order the games want it:
///
/// * **a kill camera** — restore the state three seconds before the death,
///   play the tape forward with the camera somewhere else, then put the
///   present back;
/// * **rewinding time** as a mechanic — restore, cut the tape there, and hand
///   the controls back;
/// * a replay of the last thing that happened, for a bug that was seen rather
///   than reported.
///
/// ## What is kept and what is dropped
///
/// The buffer holds [history] seconds and a little more: a rewind lands on a
/// keyframe and plays forward, so the oldest keyframe has to be at least
/// [history] behind the present, and everything between it and the next one
/// stays until that next one is old enough on its own. So the memory is a
/// keyframe per [keyframeEvery] steps for [history] seconds plus one, and a
/// tape entry per step for the same. On the crypt a snapshot is about three
/// kilobytes as JSON — measured, after five seconds of play, by
/// `apps/flutter3d_demo_dungeon/test/rewind_test.dart`: 1.6 of the run and
/// the rest the automap's runs of seen cells — and rather less as the map it
/// is kept as; ten seconds with a keyframe a second is eleven of those and
/// six hundred entries, which is small enough that no game needs to think
/// about it.
///
/// ## What the caller does
///
/// Two things, both once per step and both at the same moment:
///
/// 1. the loop records the step's input through [recorder] — add it to
///    `GameLoop.recorders` and it happens at the right moment on its own;
/// 2. the step, before it simulates, asks [keyframeDue] and hands over a
///    snapshot when the answer is yes. Before rather than after, because the
///    snapshot has to be the state the recorded entry is about to act on.
///
/// Neither the loop nor this class can take the snapshot, since neither knows
/// what a simulation is, and that boundary is the reason both of them can be
/// tested with a toy.
final class RewindBuffer {
  RewindBuffer({
    required this.stepsPerSecond,
    this.history = 10.0,
    int? keyframeEvery,
    int seed = 0,
  }) : assert(stepsPerSecond > 0, 'a simulation runs at some rate'),
       assert(history > 0.0, 'a history of nothing rewinds to nowhere'),
       keyframeEvery = keyframeEvery ?? stepsPerSecond,
       recorder = InputTapeRecorder(seed: seed) {
    assert(
      this.keyframeEvery > 0,
      'a keyframe every nought steps is every step',
    );
  }

  /// How many fixed steps make a second, for turning seconds into steps.
  final int stepsPerSecond;

  /// How many seconds back a rewind may reach.
  ///
  /// **A game's number, not the engine's.** A kill camera wants three; a
  /// rewind mechanic wants whatever the design says; a replay of the last
  /// thing that happened wants more. The memory scales with it linearly and
  /// the doc above says by how much.
  final double history;

  /// How many steps apart the snapshots are.
  ///
  /// Once a second by default. Closer keyframes make a rewind cheaper to land
  /// — fewer steps to play forward — and cost a snapshot each; a game whose
  /// snapshot is large and whose step is cheap wants them further apart.
  final int keyframeEvery;

  /// Where the loop writes each step's input. Add it to `GameLoop.recorders`.
  final InputTapeRecorder recorder;

  /// Keyframes, oldest first. Each is the state before the step at its index.
  final List<_Keyframe> _keyframes = <_Keyframe>[];

  /// How many entries have been dropped off the front of [recorder]'s tape,
  /// so that a step number can still be turned into an index in it.
  int _dropped = 0;

  /// The step about to run: the number of entries recorded so far.
  ///
  /// The loop records an entry *before* each step, so while a step is running
  /// this names it, and between steps it names the next one.
  int get step => _dropped + recorder.tape.frames.length;

  /// Whether the step about to run wants a snapshot taken before it.
  ///
  /// True on the very first step and every [keyframeEvery] after, and only
  /// while the step's entry has been recorded — asked before the loop has
  /// recorded it, this describes the previous step. The loop and this class
  /// agree on the moment: after the input is filled, before the step runs.
  bool get keyframeDue {
    final frames = recorder.tape.frames.length;
    if (frames == 0) return false;
    final current = step - 1;
    return current % keyframeEvery == 0 &&
        (_keyframes.isEmpty || _keyframes.last.step != current);
  }

  /// Takes [snapshot] as the state before the step about to run.
  ///
  /// Call when [keyframeDue] says so. A snapshot handed over at another
  /// moment is kept too — the buffer does not check — and a rewind through it
  /// then lands somewhere the tape did not lead, which is the one way to get
  /// a wrong picture out of this class.
  void keyframe(Snapshot snapshot) {
    _keyframes.add(_Keyframe(step: step - 1, snapshot: snapshot));
    _forget();
  }

  /// How many seconds back a rewind can currently reach.
  ///
  /// Less than [history] at the start of a run and until the first keyframe is
  /// far enough behind, and never more than [history] plus one keyframe
  /// interval.
  double get available {
    if (_keyframes.isEmpty) return 0.0;
    return (step - _keyframes.first.step) / stepsPerSecond;
  }

  /// The run as it was [seconds] ago, or null when the buffer does not reach
  /// that far.
  ///
  /// A state and the entries to play forward from it: restoring the one and
  /// playing the other lands on the step [seconds] before the present, and
  /// playing the whole tape lands back on the present. [RewindPoint.frames]
  /// is what a kill camera plays; [RewindPoint.replayed] is what it skips to
  /// get to the moment it wants to show.
  RewindPoint? rewindBy(double seconds) =>
      rewindTo(step - (seconds * stepsPerSecond).round());

  /// The run as it was before step [target], or null when that step is no
  /// longer held.
  RewindPoint? rewindTo(int target) {
    if (target < 0 || target > step) return null;
    _Keyframe? base;
    for (var i = _keyframes.length - 1; i >= 0; i--) {
      if (_keyframes[i].step <= target) {
        base = _keyframes[i];
        break;
      }
    }
    if (base == null) return null;
    final frames = recorder.tape.frames;
    final from = base.step - _dropped;
    return RewindPoint(
      step: target,
      snapshot: base.snapshot,
      replayed: target - base.step,
      frames: List<InputFrame>.unmodifiable(frames.sublist(from)),
      seed: recorder.tape.seed,
    );
  }

  /// Makes [point] the present: what came after it is forgotten.
  ///
  /// For a rewind the player takes over from. The entries after the point
  /// describe a future that is not going to happen, and a keyframe past it
  /// would let a later rewind land in that future.
  void cut(RewindPoint point) {
    final frames = recorder.tape.frames;
    final keep = point.step - _dropped;
    if (keep < frames.length) frames.removeRange(keep, frames.length);
    _keyframes.removeWhere((k) => k.step > point.step);
  }

  /// Forgets everything, for a new level.
  void reset() {
    recorder.tape.frames.clear();
    _keyframes.clear();
    _dropped = 0;
  }

  /// Drops keyframes older than [history] needs, and the entries before the
  /// oldest one kept.
  void _forget() {
    final horizon = step - (history * stepsPerSecond).ceil();
    // The oldest keyframe kept is the newest one at or before the horizon: a
    // rewind to the horizon lands on it and plays forward. Everything older
    // is unreachable.
    while (_keyframes.length > 1 && _keyframes[1].step <= horizon) {
      _keyframes.removeAt(0);
    }
    final oldest = _keyframes.first.step;
    final drop = oldest - _dropped;
    if (drop > 0) {
      recorder.tape.frames.removeRange(0, drop);
      _dropped = oldest;
    }
  }
}

/// A moment in the recent past, and how to get there.
final class RewindPoint {
  const RewindPoint({
    required this.step,
    required this.snapshot,
    required this.replayed,
    required this.frames,
    required this.seed,
  });

  /// The step the point is before.
  final int step;

  /// The state at the keyframe the point is reached from.
  final Snapshot snapshot;

  /// How many of [frames] play from [snapshot] to reach [step].
  final int replayed;

  /// The entries from the keyframe to the present, [replayed] of them before
  /// the point and the rest after it.
  final List<InputFrame> frames;

  final int seed;

  /// The entries from the keyframe to the point, as a tape: restore
  /// [snapshot] and play this to arrive at [step].
  InputTape get tapeToPoint =>
      InputTape(seed: seed, frames: frames.sublist(0, replayed));

  /// The entries from the point to the present, as a tape: what a kill camera
  /// plays after arriving at [step].
  InputTape get tapeFromPoint =>
      InputTape(seed: seed, frames: frames.sublist(replayed));
}

final class _Keyframe {
  const _Keyframe({required this.step, required this.snapshot});
  final int step;
  final Snapshot snapshot;
}
