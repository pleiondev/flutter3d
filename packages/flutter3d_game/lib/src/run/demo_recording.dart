import 'package:flutter3d_sim/flutter3d_sim.dart';

/// A [Demo] being written while the run is played: the tape, the
/// checkpoints, and `HR3`'s levels swapped in under it.
///
/// **What used to be five fields in every game's widget.** Each game kept a
/// start, a level, a hash, a trace and a recorder beside each other and
/// assembled the [Demo] at the end; a level swapped in mid-run had nowhere to
/// go, so the platformer threw its demo away at every edit and began another.
/// The swap has to touch the trace and the list of swaps together, at a step
/// counted in this tape rather than the timeline's, and that is one object's
/// job.
final class DemoRecording {
  DemoRecording({
    required this.level,
    required this.levelHash,
    required this.start,
    required int seed,
    int checkpointEvery = 25,
  }) : recorder = InputTapeRecorder(seed: seed),
       checkpoints = DigestTrace(every: checkpointEvery);

  /// The asset path of the level the run started in.
  final String level;

  /// [Level.digestHex] of that level as it was loaded.
  final String levelHash;

  /// The state the tape starts from.
  final Snapshot start;

  /// Where the loop writes each step's input. Add it to `GameLoop.recorders`.
  final InputTapeRecorder recorder;

  /// A digest every so many steps, taken live.
  final DigestTrace checkpoints;

  final List<DemoLevelSwap> _swaps = <DemoLevelSwap>[];

  /// How many steps have been recorded.
  int get steps => recorder.tape.steps;

  /// Takes a checkpoint if the step just run is one. Call after every step;
  /// [after] is asked for the state the step left only on a checkpoint step,
  /// since a save of every body is what a checkpoint costs.
  void observe(Snapshot Function() after) {
    final step = recorder.tape.steps;
    if (step % checkpoints.every == 0) {
      checkpoints.observe(step, after().toJson());
    }
  }

  /// Writes down that [next] was put under the run [stepsAgo] steps before
  /// the present — `RunTimeline.swapLevel`'s step, counted back from now,
  /// since the timeline and this tape did not start at the same step.
  ///
  /// The swap replaced the run from there on, so a swap already written at
  /// or after that step is dropped with the checkpoints taken after it: both
  /// describe a run that was lived again.
  ///
  /// False, and nothing written, when the swap took effect before this
  /// recording began. The start this recording holds was then made by the
  /// old level and the run since by the new one, and no file can say that;
  /// the caller begins a new recording from the present instead and writes
  /// the swap at its step zero.
  bool levelSwapped(Level next, {required int stepsAgo}) {
    final at = recorder.tape.steps - stepsAgo;
    if (at < 0) return false;
    _swaps
      ..removeWhere((swap) => swap.step >= at)
      ..add(DemoLevelSwap(step: at, level: next));
    checkpoints.forgetAfter(at);
    return true;
  }

  /// Writes down that the run was rewound [stepsAgo] steps and goes on from
  /// there — `RunTimeline.onBranched`'s count, as [levelSwapped] takes its
  /// own.
  ///
  /// The tape is cut at that step ([InputTapeRecorder.truncate]) and the
  /// checkpoints after it forgotten: both describe the future the branch
  /// left. A checkpoint at the step itself stays, since the state after
  /// that many steps is the state the run goes on from. So does a swap at
  /// that step, which took effect before it and is still the level on
  /// screen; a swap after it belonged to the future and goes. (A timeline
  /// cannot branch back past a swap it made, since `RunTimeline.swapLevel`
  /// rebases its buffer there; the rule is for a caller that can.)
  ///
  /// False, and nothing changed, when the branch went back before this
  /// recording began: the start it holds is then a state the run no longer
  /// passes through. The caller begins a new recording from the present, as
  /// for [levelSwapped].
  bool branched({required int stepsAgo}) {
    RangeError.checkNotNegative(stepsAgo, 'stepsAgo');
    final at = recorder.tape.steps - stepsAgo;
    if (at < 0) return false;
    recorder.truncate(at);
    _swaps.removeWhere((swap) => swap.step > at);
    checkpoints.forgetAfter(at);
    return true;
  }

  /// The levels swapped in under the run so far, oldest first.
  List<DemoLevelSwap> get levelSwaps =>
      List<DemoLevelSwap>.unmodifiable(_swaps);

  /// The run so far, as a file.
  Demo demo({
    required String buildStamp,
    String? platform,
    String? recordedBy,
  }) => Demo(
    level: level,
    levelHash: levelHash,
    start: start,
    tape: recorder.tape,
    buildStamp: buildStamp,
    checkpoints: checkpoints,
    platform: platform,
    recordedBy: recordedBy,
    levelSwaps: levelSwaps,
  );
}

/// What [replayDemo] found.
final class DemoReplay {
  const DemoReplay({required this.steps, this.divergence});

  /// How many steps were played.
  final int steps;

  /// The first checkpoint the replay did not match, or null when it matched
  /// every one the file holds.
  final Divergence? divergence;
}

/// Plays [demo] through the simulation from its start, swapping in each of
/// [Demo.levelSwaps] as the tape reaches it, and checks the file's own
/// checkpoints on the way.
///
/// The level [Demo.level] names must be up when this is called; [swapLevel]
/// puts a swapped document in its place and must carry the run over, as the
/// game did live — the state [save] answers before it is what [save] answers
/// after. It is required exactly when the demo has swaps in it: a replay that
/// played through them would part from the run at the first and report that
/// as a divergence of the simulation.
///
/// A swap at step K goes in after the checkpoint at K is compared, which is
/// the order the live run met them in: the checkpoint was taken under the
/// old level, and the timeline swapped at the keyframe that state was.
///
/// Checkpoints are compared by step rather than by position, since a swap
/// leaves a gap in them (`DigestTrace.forgetAfter`).
DemoReplay replayDemo({
  required Demo demo,
  required InputState input,
  required void Function(Snapshot snapshot) restore,
  required Snapshot Function() save,
  required void Function(double dt) stepSim,
  void Function(Level level)? swapLevel,
  double stepSeconds = 1.0 / 60.0,
}) {
  if (demo.levelSwaps.isNotEmpty && swapLevel == null) {
    throw ArgumentError.value(
      demo,
      'demo',
      'replaces its level at step ${demo.levelSwaps.first.step}, and no '
          'swapLevel was given to replace it with',
    );
  }
  final expected = <int, int>{
    for (var i = 0; i < demo.checkpoints.steps.length; i++)
      demo.checkpoints.steps[i]: demo.checkpoints.digests[i],
  };
  final swaps = demo.levelSwaps;
  var nextSwap = 0;
  void swapAt(int step) {
    while (nextSwap < swaps.length && swaps[nextSwap].step == step) {
      swapLevel!(swaps[nextSwap++].level);
    }
  }

  restore(demo.start);
  swapAt(0);
  final playback = InputTapePlayback(demo.tape);
  final wasMuted = input.muted;
  input.muted = true;
  Divergence? divergence;
  var step = 0;
  try {
    while (!playback.isFinished) {
      playback.applyTo(input);
      input.beginStep();
      stepSim(stepSeconds);
      input.endStep();
      step++;
      final digest = expected[step];
      if (digest != null && divergence == null) {
        final found = StateDigest.of(save().toJson());
        if (found != digest) {
          divergence = Divergence(step: step, expected: digest, found: found);
        }
      }
      swapAt(step);
    }
  } finally {
    input.muted = wasMuted;
  }
  final unreached = demo.checkpoints.steps.where((s) => s > step).firstOrNull;
  return DemoReplay(
    steps: step,
    divergence:
        divergence ??
        (unreached == null
            ? null
            : Divergence(
                step: unreached,
                expected: expected[unreached],
                found: null,
              )),
  );
}
