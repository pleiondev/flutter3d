import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show SharedMeshes;
import 'package:flutter3d_game_kit/ghost.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart'
    show Runner, platformerSimulationVersion;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show usePhysics;
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'staging.dart';

/// Where the runner of a shared run was, read off the run itself: the level
/// staged here, [demo]'s tape played through it headless, and the runner's
/// feet and facing written down as they went — a pose track to race.
///
/// What is decided about the run — another version of the level, other
/// physics, another platformer simulation, a level edited as it went, and
/// the pose record when the tape will not do — is `ghostOfRun`'s, from the
/// ghost addon. What is here is this game's half: how its level is staged
/// and where the runner's feet are.
///
/// [hz] samples a second, and the track is interpolated between them —
/// see [Playback].
({Tape? ghost, GhostNote note}) ghostOf(
  Level level,
  Demo demo, {
  double hz = 30.0,
}) => ghostOfRun(
  level,
  demo,
  body: runnerBody,
  simulation: platformerSimulationVersion,
  physics: usePhysics(),
  replay: () {
    final world = CollisionWorld(backend: usePhysics());
    level.addTo(world);
    final input = InputState()..muted = true;
    final staged = stage(level, world, input: input);
    world.update();
    staged.sim.restore(demo.start);

    const dt = 1.0 / 60.0;
    final recorder = Recorder(hz: hz);
    final feet = Vector3.zero();
    void note(int step) {
      final runner = staged.runner;
      feet
        ..setFrom(runner.position)
        ..y -= runner.body.halfExtents.y;
      recorder.tick(step * dt, position: feet, yaw: runner.yaw);
    }

    final playback = InputTapePlayback(demo.tape);
    var step = 0;
    note(step);
    while (!playback.isFinished) {
      playback.applyTo(input);
      input.beginStep();
      staged.step(dt);
      input.endStep();
      note(++step);
    }
    return recorder.finish(step * dt);
  },
);

/// The name the runner goes by in a pose record.
const String runnerBody = 'runner';

/// The runner as the pose record writes it down: its feet, which is where a
/// ghost stands, and its facing as a turn about the vertical — what
/// [ghostOf] reads back when the tape cannot be replayed.
Iterable<BodyPose> runnerPoses(Runner runner) => <BodyPose>[
  BodyPose(
    runnerBody,
    runner.position.clone()..y -= runner.body.halfExtents.y,
    Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), runner.yaw),
  ),
];

/// The ghost on screen: the runner's own [model], translucent and unlit, or a
/// box of the runner's [halfExtents] until that arrives — drawn where the
/// track was at the run's own clock, and hidden before it starts and once it
/// is done.
///
/// [modelFloor] and [facing] are `RunnerVisuals.modelFloor` and
/// `RunnerVisuals.facing`. The box is about its middle and the track is the
/// feet, so the box stands on its own half height instead.
Ghost runnerGhost(
  GraphicsDevice device,
  Scene scene, {
  required Vector3 halfExtents,
  ModelAsset? model,
  double modelFloor = 0.0,
  double facing = 0.0,
}) {
  final look = Ghost.look();
  return Ghost.build(
    scene,
    look: look,
    model: model,
    floor: model == null ? -halfExtents.y : modelFloor,
    facing: model == null ? 0.0 : facing,
    fallback: () {
      final box = MeshNode(
        SharedMeshes(device).box(halfExtents * 2.0),
        look,
        name: 'ghost',
      );
      scene.add(box);
      return box;
    },
  );
}
