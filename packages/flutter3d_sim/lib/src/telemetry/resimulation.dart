/// A recorded run played again, through the same simulation, to read numbers
/// off it the player never sent.
library;

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart'
    show CollisionWorld, DartPhysics, PhysicsBackend;

import '../input/input_state.dart';
import '../input/input_tape.dart';
import '../level/level.dart';
import '../level/level_collision.dart';
import '../loop/headless_run.dart';
import '../loop/run_outcome.dart';
import '../save/demo.dart';
import '../save/state_digest.dart';
import 'heatmap.dart';

/// What [resimulate] found.
abstract final class Resimulation {
  const Resimulation();
}

/// The level handed in is not the one the run was recorded in.
final class ResimulationLevelChanged extends Resimulation {
  /// The level's hash [found] differs from the [recorded] one.
  const ResimulationLevelChanged({required this.found, required this.recorded});

  /// [Level.digestHex] of the level handed in.
  final String found;

  /// The hash the run names its level by, [Demo.levelHash].
  final String recorded;
}

/// The run was recorded on other physics than this process runs: the two
/// backends are not promised to agree, so playing it here proves nothing.
/// The host chooses the recorded one first — `choosePhysics` in the native
/// package — and is told this only where that one cannot be had.
final class ResimulationOnOtherPhysics extends Resimulation {
  /// The run was [recorded] on one backend and this process is [running]
  /// another.
  const ResimulationOnOtherPhysics({
    required this.recorded,
    required this.running,
  });

  /// `Demo.physics`.
  final String recorded;

  /// The name of the physics backend the replay runs on.
  final String running;
}

/// The run was recorded on another simulation than the game names
/// ([HeadlessGame.simulation]): the same input plays out differently here, so
/// it is not played at all.
final class ResimulationOnOtherSimulation extends Resimulation {
  /// A refusal for [reason].
  const ResimulationOnOtherSimulation(this.reason);

  /// Why, in the words of `Demo.refusalOn`.
  final String reason;
}

/// A fresh run of the level does not start where the recording started: the
/// demo began mid-run, or the game's spawning has changed since.
final class ResimulationStartDiffers extends Resimulation {
  /// The one answer of its kind; it carries nothing.
  const ResimulationStartDiffers();
}

/// The replay parted from the checkpoints the run was recorded with.
final class ResimulationDiverged extends Resimulation {
  /// A replay that parted at [divergence], with checkpoints [every] steps.
  const ResimulationDiverged(this.divergence, {required this.every});

  /// The first checkpoint whose digest differed from the recorded one.
  final Divergence divergence;

  /// How far apart checkpoints were, so the answer can bracket the defect.
  final int every;

  /// The last step at which the two runs are known to have agreed.
  int get agreedUntil => math.max(0, divergence.step - every);
}

/// The replay retraced every checkpoint, and here is what it saw on the way.
final class ResimulationRetraced extends Resimulation {
  /// A replay that agreed with every checkpoint, with what it saw.
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

  /// Count of fixed steps played, the demo's whole length.
  final int steps;

  /// Count of checkpoints compared on the way, all of which agreed.
  final int checkpoints;

  /// Where [HeadlessRun.position] was in plan every so many steps, and once
  /// more at the last step, so a run's end is where its trail ends.
  final List<TrailPoint> trail;

  /// [StateDigest] of the run's save after the last step.
  final int finalDigest;

  /// How the run ended, [HeadlessRun.outcome] of [run].
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
/// A run recorded on another simulation than [HeadlessGame.simulation] is
/// [ResimulationOnOtherSimulation] before a step is played.
///
/// A run that diverges answers no metrics at all: a trail that parted from the
/// player's at step 400 is a trail of somebody who never played.
Resimulation resimulate({
  required HeadlessGame game,
  required Level level,
  required Demo demo,
  int sampleEvery = 10,

  /// The fixed step, in seconds.
  double dt = 1.0 / 60.0,
  PhysicsBackend physics = const DartPhysics(),
}) {
  assert(sampleEvery > 0, 'a sample every no steps is no trail');
  final found = level.digestHex;
  if (found != demo.levelHash) {
    return ResimulationLevelChanged(found: found, recorded: demo.levelHash);
  }
  final running = physics.name;
  if (demo.physics case final String recorded when recorded != running) {
    return ResimulationOnOtherPhysics(recorded: recorded, running: running);
  }
  // The whole simulation, plugins and subsystems included, as the game names
  // it; a game that names none plays the tape and lets the checkpoints speak.
  final simulation = game.simulation;
  if (simulation != null) {
    if (demo.refusalOn(simulation) case final String reason) {
      return ResimulationOnOtherSimulation(reason);
    }
  }

  final world = CollisionWorld(backend: physics);
  level.addTo(world);
  // On the physics it was recorded on, [physics]; a game that stages
  // dynamics of its own takes the world over.
  physics.attach(world);
  final input = InputState();
  final run = game.start(
    HeadlessStart(level: level, world: world, input: input),
  );
  world.update();
  if (StateDigest.of(run.save().toJson()) !=
      StateDigest.of(demo.start.toJson())) {
    return const ResimulationStartDiffers();
  }

  final playback = simulation == null
      ? InputTapePlayback.tape(demo.tape)
      : InputTapePlayback(demo, simulation: simulation);
  final trace = DigestTrace(every: demo.checkpoints.every);
  final trail = <TrailPoint>[];
  for (var step = 1; step <= demo.steps; step++) {
    playback.applyTo(input);
    input.beginStep();
    run.step(dt);
    if (step % trace.every == 0) trace.observe(step, run.save().toJson());
    input.endStep();
    if (step % sampleEvery == 0 || step == demo.steps) {
      final at = run.position;
      trail.add(TrailPoint(x: at.x, z: at.z));
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
