/// A recorded run played again, through the same simulation, to read numbers
/// off it the player never sent.
library;

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart'
    show CollisionWorld, PhysicsBackend;

import '../input/input_state.dart';
import '../input/input_tape.dart';
import '../level/level.dart';
import '../level/level_collision.dart';
import '../loop/headless_run.dart';
import '../loop/run_outcome.dart';
import '../save/demo.dart';
import '../save/state_digest.dart';

/// What [resimulate] found.
sealed class Resimulation {
  const Resimulation();
}

/// The level handed in is not the one the run was recorded in.
final class ResimulationLevelChanged extends Resimulation {
  const ResimulationLevelChanged({required this.found, required this.recorded});

  final String found;
  final String recorded;
}

/// The run was recorded on other physics than this process runs: the two
/// backends are not promised to agree, so playing it here proves nothing.
/// The host chooses the recorded one first — `choosePhysics` in the native
/// package — and is told this only where that one cannot be had.
final class ResimulationOnOtherPhysics extends Resimulation {
  const ResimulationOnOtherPhysics({
    required this.recorded,
    required this.running,
  });

  /// `Demo.physics`.
  final String recorded;

  /// `PhysicsBackend.current.name`.
  final String running;
}

/// A fresh run of the level does not start where the recording started: the
/// demo began mid-run, or the game's spawning has changed since.
final class ResimulationStartDiffers extends Resimulation {
  const ResimulationStartDiffers();
}

/// The replay parted from the checkpoints the run was recorded with.
final class ResimulationDiverged extends Resimulation {
  const ResimulationDiverged(this.divergence, {required this.every});

  final Divergence divergence;

  /// How far apart checkpoints were, so the answer can bracket the defect.
  final int every;

  /// The last step at which the two runs are known to have agreed.
  int get agreedUntil => math.max(0, divergence.step - every);
}

/// The replay retraced every checkpoint, and here is what it saw on the way.
final class ResimulationRetraced extends Resimulation {
  const ResimulationRetraced({
    required this.run,
    required this.steps,
    required this.checkpoints,
    required this.trail,
    required this.finalDigest,
  });

  /// The run as the last step left it — [HeadlessRun.reading] and
  /// [HeadlessRun.outcome] are the metrics a caller asks of it.
  final HeadlessRun run;

  final int steps;
  final int checkpoints;

  /// `(x, z)` of [HeadlessRun.position] every so many steps, and once more at
  /// the last step, so a run's end is where its trail ends.
  final List<(double, double)> trail;

  final int finalDigest;

  RunOutcome get outcome => run.outcome;
}

/// Plays [demo] into a fresh run of [game] in [level], checks it against the
/// checkpoints it was recorded with, and samples where the player went every
/// [sampleEvery] steps.
///
/// **Numbers off a replay rather than numbers off the client**, and that is
/// what makes them telemetry worth keeping. A client that reported its own
/// metrics could report anything; one that sends its input can only send
/// input, and the server works out what that input did with the same
/// simulation the player ran — or finds that it did something else and says
/// at which checkpoint.
///
/// A run that diverges answers no metrics at all: a trail that parted from the
/// player's at step 400 is a trail of somebody who never played.
Resimulation resimulate({
  required HeadlessGame game,
  required Level level,
  required Demo demo,
  int sampleEvery = 10,
  double dt = 1.0 / 60.0,
}) {
  assert(sampleEvery > 0, 'a sample every no steps is no trail');
  final found = level.digestHex;
  if (found != demo.levelHash) {
    return ResimulationLevelChanged(found: found, recorded: demo.levelHash);
  }
  final running = PhysicsBackend.current.name;
  if (demo.physics case final String recorded when recorded != running) {
    return ResimulationOnOtherPhysics(recorded: recorded, running: running);
  }

  final world = CollisionWorld();
  level.addTo(world);
  // On the physics it was recorded on, which is the run's now; a game that
  // stages dynamics of its own takes the world over.
  PhysicsBackend.current.attach(world);
  final input = InputState();
  final run = game.start(level, world, input);
  world.update();
  if (StateDigest.of(run.save().toJson()) !=
      StateDigest.of(demo.start.toJson())) {
    return const ResimulationStartDiffers();
  }

  final playback = InputTapePlayback(demo.tape);
  final trace = DigestTrace(every: demo.checkpoints.every);
  final trail = <(double, double)>[];
  for (var step = 1; step <= demo.steps; step++) {
    playback.applyTo(input);
    input.beginStep();
    run.step(dt);
    if (step % trace.every == 0) trace.observe(step, run.save().toJson());
    input.endStep();
    if (step % sampleEvery == 0 || step == demo.steps) {
      final at = run.position;
      trail.add((at.x, at.z));
    }
  }

  final divergence = trace.divergenceFrom(demo.checkpoints.digests);
  if (divergence != null) {
    return ResimulationDiverged(divergence, every: trace.every);
  }
  return ResimulationRetraced(
    run: run,
    steps: demo.steps,
    checkpoints: trace.steps.length,
    trail: trail,
    finalDigest: StateDigest.of(run.save().toJson()),
  );
}
