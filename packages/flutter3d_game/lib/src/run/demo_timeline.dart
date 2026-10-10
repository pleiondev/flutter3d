import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'run_part.dart';

/// Rebuilds a [RewindBuffer] that reaches every step of [demo], not only the
/// last few seconds a live [RunTimeline] keeps — `rp-02`'s "скраббер по всему
/// прогону из `.f3drun`", built by replaying the whole tape once rather than
/// by teaching [RewindBuffer] a second way to acquire keyframes.
///
/// **Played through [loop], the one path.** [demo]'s start, the run's own
/// snapshot, is restored as the loop's part [part] (a genre's plugin id) at
/// step nought, and the tape plays through the loop's own steps with the
/// returned buffer attached ([RewindBuffer.attach]) — so its keyframes are
/// the loop's captures, exactly as a live-played window's are, and a
/// [RunTimeline] over the loop and this buffer answers `preview`,
/// `releaseAtStep` and `scrubTo` for any step of the whole run. The buffer is
/// detached again before it is returned. The loop's input is muted for the
/// whole replay: the tape is the one device let through a mute, so a live
/// device cannot leak a key into a reconstruction happening while a game is
/// paused to load one. Any other recorder on the loop records the replay
/// too; a game detaches its live recording first.
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
/// know which level each keyframe belongs to; until it does,
/// `replayDemoOnLoop` plays such a run and this does not pretend to scrub it.
///
/// So is a run recorded on a simulation other than this build's — [simulation]
/// when given, the loop's `EngineLoop.simulationBase` otherwise; the check is
/// never skipped. [ReplayException] carries the run's pose record, which
/// scrubs on any build because nothing in it is simulated.
RewindBuffer rewindBufferFromDemo({
  required Demo demo,
  required EngineLoop loop,
  required String part,
  int? keyframeEvery,
  double? history,
  SimulationVersion? simulation,
}) {
  demo.checkSimulation(simulation ?? loop.simulationBase);
  if (demo.levelSwaps.isNotEmpty) {
    throw ArgumentError.value(
      demo,
      'demo',
      'replaces its level at step ${demo.levelSwaps.first.step}; a scrub '
          'across a swap would restore one level\'s state under the other',
    );
  }
  final stepsPerSecond = (1.0 / loop.stepSeconds).round();
  loop.rewindTo(0, state: loopStateWith(loop, part, demo.start));
  final wholeRun = demo.tape.frames.length / stepsPerSecond;
  final buffer = RewindBuffer(
    stepsPerSecond: stepsPerSecond,
    history: history ?? (wholeRun + 1.0),
    keyframeEvery: keyframeEvery,
    seed: demo.tape.seed,
  );
  final playback = InputTapePlayback(demo.tape);
  final previous = loop.playback;
  final wasMuted = loop.input.muted;
  final attached = buffer.attach(loop);
  loop.playback = playback;
  loop.input.muted = true;
  try {
    while (!playback.isFinished) {
      loop.runSteps(1);
    }
  } finally {
    attached.cancel();
    loop.playback = previous;
    loop.input.muted = wasMuted;
  }
  return buffer;
}
