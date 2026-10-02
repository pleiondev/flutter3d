import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'demo_recording.dart';

/// Rebuilds a [RewindBuffer] that reaches every step of [demo], not only the
/// last few seconds a live [RunTimeline] keeps — `rp-02`'s "скраббер по всему
/// прогону из `.f3drun`", built by replaying the whole tape once rather than
/// by teaching [RewindBuffer] a second way to acquire keyframes.
///
/// Runs [demo]'s tape from [Demo.start] through [stepSim] exactly the way
/// [GameLoop.advance] would have the first time it played — apply the
/// recorded frame, record it, `beginStep`, keyframe before the step if one is
/// due, `stepSim`, `endStep` — so a [RunTimeline] built on the returned
/// buffer answers `preview`/`releaseAtStep` for any step of the whole run,
/// the same way it already answers them for a live-played window. [input] is
/// muted for the whole replay: [InputTapePlayback] is the one device let
/// through a mute, so a live device still reading the same [InputState]
/// cannot leak a key into a reconstruction happening while a game is paused
/// to load one.
///
/// [history] is generous on purpose — the whole run plus a keyframe interval
/// — so [RewindBuffer]'s own forgetting never triggers while every step is
/// still meant to be reachable; a caller wanting to bound memory for a very
/// long recording can pass a smaller one and accept that only its most
/// recent stretch scrubs.
///
/// A demo with `HR3` level swaps in it is refused: a keyframe before a swap
/// is a state of the old level, and a scrub to it would restore that state
/// under whichever level is up. Scrubbing across a swap needs the buffer to
/// know which level each keyframe belongs to; until it does, [replayDemo]
/// plays such a run and this does not pretend to scrub it.
RewindBuffer rewindBufferFromDemo({
  required Demo demo,
  required int stepsPerSecond,
  int? keyframeEvery,
  double? history,
  required InputState input,
  required void Function(Snapshot snapshot) restore,
  required Snapshot Function() save,
  required void Function(double dt) stepSim,
}) {
  if (demo.levelSwaps.isNotEmpty) {
    throw ArgumentError.value(
      demo,
      'demo',
      'replaces its level at step ${demo.levelSwaps.first.step}; a scrub '
          'across a swap would restore one level\'s state under the other',
    );
  }
  restore(demo.start);
  final wholeRun = demo.tape.frames.length / stepsPerSecond;
  final buffer = RewindBuffer(
    stepsPerSecond: stepsPerSecond,
    history: history ?? (wholeRun + 1.0),
    keyframeEvery: keyframeEvery,
    seed: demo.tape.seed,
  );
  final playback = InputTapePlayback(demo.tape);
  final wasMuted = input.muted;
  input.muted = true;
  try {
    final dt = 1.0 / stepsPerSecond;
    while (!playback.isFinished) {
      playback.applyTo(input);
      buffer.recorder.record(input);
      input.beginStep();
      if (buffer.keyframeDue) buffer.keyframe(save());
      stepSim(dt);
      input.endStep();
    }
  } finally {
    input.muted = wasMuted;
  }
  return buffer;
}
