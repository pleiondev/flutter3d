import 'package:flutter3d/flutter3d.dart' hide Pose;
import 'package:flutter3d_app/flutter3d_app.dart' show SharedMeshes;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'staging.dart';

/// Where the runner of a shared run was, read off the run itself: the level
/// staged here, [demo]'s tape played through it headless, and the runner's
/// feet and facing written down as they went — a pose track to race.
///
/// **Not sent; played again.** The run is a tape and a starting state, and
/// the simulation it was played in is deterministic, so what a viewer needs
/// to draw the runner is already in the bundle: the poses come out of the
/// same steps the sharer took. A run recorded on other physics, or in a
/// level edited since, would come out somewhere else, so both are refused.
///
/// [hz] samples a second, and the track is interpolated between them —
/// see [Playback].
({Tape? ghost, String says}) ghostOf(
  Level level,
  Demo demo, {
  double hz = 30.0,
}) {
  if (demo.levelHash != level.digestHex) {
    return (
      ghost: null,
      says: 'the run was made in another version of this level',
    );
  }
  if (demo.levelSwaps.isNotEmpty) {
    return (ghost: null, says: 'the run had its level edited as it went');
  }
  if (demo.physics case final String physics
      when physics != PhysicsBackend.current.name) {
    return (
      ghost: null,
      says:
          'the run was played on the $physics physics, and this game is on '
          '${PhysicsBackend.current.name}',
    );
  }
  final world = CollisionWorld();
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
    staged.sim.step(dt);
    input.endStep();
    note(++step);
  }
  return (
    ghost: recorder.finish(step * dt),
    says: 'a ghost of ${(step * dt).toStringAsFixed(1)} s',
  );
}

/// The ghost on screen: the runner's own model, translucent and unlit, or a
/// box of the runner's size until that arrives — drawn where the track was
/// at the run's own clock, and hidden before it starts and once it is done.
final class GhostRunner {
  GhostRunner(this.node, {this.modelFloor = 0.0, this.facing = 0.0});

  final SceneNode node;

  /// The model's own lowest point, as `RunnerVisuals.modelFloor`.
  final double modelFloor;

  /// Added to the yaw, as `RunnerVisuals.facing`.
  final double facing;

  final Pose _at = Pose();

  /// Where the ghost is drawn from — `Looks.ghost` in the racing game, the
  /// same reasons: nothing writes depth through it, and nothing lights it.
  static Material look() => Material(
    baseColor: Vector4(0.65, 0.85, 1.0, 0.35),
    alphaMode: MaterialAlphaMode.blend,
    depthWrite: false,
    lighting: LightingModel.unlit,
  );

  /// Puts the ghost where [track] was [seconds] into the run, or hides it.
  void showAt(double seconds, Tape track) {
    if (!Playback(track).sampleAt(seconds, _at)) {
      node.visible = false;
      return;
    }
    node
      ..visible = true
      ..setPosition(_at.position.x, _at.position.y - modelFloor, _at.position.z)
      ..setRotation(
        Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), _at.yaw + facing),
      );
  }

  /// A second of the runner's [model] in [scene], haunted; a box of
  /// [halfExtents] when there is no model.
  static GhostRunner build(
    GraphicsDevice device,
    Scene scene, {
    required Vector3 halfExtents,
    ModelAsset? model,
    double modelFloor = 0.0,
    double facing = 0.0,
  }) {
    final SceneNode node;
    if (model == null) {
      node = MeshNode(
        SharedMeshes(device).box(halfExtents * 2.0),
        look(),
        name: 'ghost',
      );
      scene.add(node);
      // The box is about its middle; the track is the feet.
      return GhostRunner(node, modelFloor: -halfExtents.y)
        ..node.visible = false;
    }
    final instance = model.instantiate(scene, name: 'ghost');
    final ghost = look();
    for (final mesh in instance.meshes) {
      mesh.material = ghost;
    }
    node = instance.root..visible = false;
    return GhostRunner(node, modelFloor: modelFloor, facing: facing);
  }
}
