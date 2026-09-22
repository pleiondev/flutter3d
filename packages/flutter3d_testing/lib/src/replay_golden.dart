import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'golden.dart';
import 'render_frame.dart';

/// Replays a `.f3drun` to one step and compares the frame drawn there against
/// a reference image.
///
/// **`rp-05`'s golden, not `rp-00`'s digest.** A [Demo]'s own [DigestTrace]
/// already says whether a replay reached the same numbers; this asks the
/// question numbers cannot answer — whether the picture at step [atStep]
/// still looks like it did, the way every other golden in this repository
/// does. The two are complementary rather than either replacing the other:
/// a step can be numerically identical and still be drawn by a renderer that
/// changed, and a step can look the same by eye while the state underneath
/// it quietly diverged from what a checkpoint would have caught. `--check`,
/// where `rp-05`'s CLI wraps this same replay for a whole run at once, is the
/// digest half; this is the frame half.
///
/// Caller-supplied, because a genre's own step is not this package's to
/// know:
///
/// * [input] is driven from [demo]'s tape by this function — the caller
///   supplies it already wired into whatever reads it (an [InputState] a
///   simulation steps against, or one a genre's own translation layer turns
///   into something else first, the way `_readDriver` does for a car).
/// * [onStep] runs the actual simulation step, once per tape entry, after
///   this function has already applied that entry to [input] — the same
///   order every shipped game's own loop uses.
/// * [frame] builds the scene and camera to draw once the replay has reached
///   [atStep], the same callback [renderFrame] itself takes.
///
/// Throws a [StateError] if the tape ends before [atStep] — a demo that ran
/// out early is a different failure than a frame that looks wrong, and
/// conflating the two would send whoever reads the failure looking at pixels
/// for a problem that is really about the tape's length.
Future<void> replayGolden({
  required Demo demo,
  required int atStep,
  required InputState input,
  required void Function(double dt) onStep,
  required int width,
  required int height,
  required FrameBuilder frame,
  required String goldenPath,
  double dt = 1.0 / 60.0,
  double tolerance = 0.0,
  String? reason,
}) async {
  final playback = InputTapePlayback(demo.tape);
  for (var step = 1; step <= atStep; step++) {
    if (playback.isFinished) {
      throw StateError(
        'the tape ended at step ${step - 1}, before reaching $atStep — '
        'record a longer run or ask for an earlier step',
      );
    }
    playback.applyTo(input);
    onStep(dt);
    input.endStep();
  }

  final rendered = await renderFrame(
    width: width,
    height: height,
    build: frame,
  );
  await expectMatchesGolden(
    rendered,
    goldenPath,
    tolerance: tolerance,
    reason: reason,
  );
}
