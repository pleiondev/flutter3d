import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart'
    show referenceBodyMass;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SnapshotPart;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'skeleton_ragdoll.dart';

/// Actors that fall as bodies when they die, in place of a death clip.
///
/// Handed to `ActorVisuals` as its `corpses`: an actor that dies hands its
/// skeleton to a ragdoll in the physics core, which falls against the level
/// as the core sees it — the level's walls and floors and every actor still
/// standing, all mirrored from the collision world by a [NativeDynamics] of
/// this one's own. The dead are triggers by then, so a body does not fall
/// against the capsule it died in.
///
/// **Display, not simulation.** A game's step never asks where a body lies —
/// the dead block nothing — so this steps on the frame, in fixed steps of its
/// own, and its core is not in a save or a replay: a body is a pose, as a
/// particle is a point. Which actors lie dead is, though ([snapshotPart]): a
/// rewind to before a death takes the body away.
///
/// A rig the ragdoll profile does not name is left to its death clip:
/// [begin] answers false.
final class RagdollCorpses with ActorCorpses {
  /// Bodies falling against [world].
  ///
  /// [pushedFrom] says where the blow that killed an actor came from, asked
  /// when it dies, and the body is pushed away from there with [push]; null,
  /// or a null answer, pushes nobody. [chest] is the ragdoll body the push
  /// lands on, and [mass] what a whole body weighs, kg: the reference man's
  /// ([referenceBodyMass]) unless given.
  ///
  /// **The bodies fall by [world]'s gravity** (`CollisionWorld.properties`),
  /// the one the game's characters and crates fall by: a dungeon set on the
  /// Moon drops its dead as slowly as its living jump.
  RagdollCorpses(
    CollisionWorld world, {
    this.pushedFrom,
    this.push = defaultPush,
    this.chest = 'Torso',
    this.mass = referenceBodyMass,
  }) : _dynamics = NativeDynamics(world: world)..native.substeps = 8;

  final NativeDynamics _dynamics;

  /// Where the blow that killed an actor came from, asked when it dies.
  final Vector3? Function()? pushedFrom;

  /// How hard the killing blow pushes the [chest]: an impulse, in
  /// newton-seconds.
  final double push;

  /// The ragdoll body [push] lands on, by its profile name.
  final String chest;

  /// What a whole body weighs, kg.
  final double mass;

  /// The push a body gets unless a game says otherwise, N·s: the reference
  /// man ([referenceBodyMass]) thrown back at two metres a second, as a body
  /// and not a statue.
  static const double defaultPush = referenceBodyMass * 2.0;

  final Map<Actor, SkeletonRagdoll> _ragdolls = <Actor, SkeletonRagdoll>{};
  double _owed = 0.0;

  /// The core's steps, a sixtieth of a second each.
  static const double stepSeconds = 1.0 / 60.0;

  /// How many steps a frame may take before the rest is forgiven: a frame
  /// that stalled for a second does not owe the bodies sixty.
  static const int mostStepsAFrame = 4;

  /// How many bodies are falling or lying.
  int get count => _ragdolls.length;

  /// The ragdoll [actor] became, if it became one.
  SkeletonRagdoll? ragdollOf(Actor actor) => _ragdolls[actor];

  @override
  bool begin(
    Actor actor,
    ModelInstance model, {
    List<Matrix4>? previous,
    double dt = stepSeconds,
  }) {
    if (model.skeletons.isEmpty) return false;
    final skeleton = model.skeletons.first;
    final mesh = model.meshes.where((m) => m.skeleton == skeleton).firstOrNull;
    if (mesh == null) return false;
    try {
      _ragdolls[actor] = SkeletonRagdoll(
        skeleton: skeleton,
        meshWorld: mesh.worldMatrix,
        world: _dynamics.native,
        dynamics: _dynamics,
        mass: mass,
        previous: previous,
        dt: dt,
      );
    } on ArgumentError {
      // A rig the profile does not know: it plays its death clip instead.
      return false;
    }
    _pushAway(_ragdolls[actor]!);
    return true;
  }

  /// The killing blow into [ragdoll]'s chest: away from where it came from,
  /// level, and a little up, so the body leaves the floor it stood on.
  void _pushAway(SkeletonRagdoll ragdoll) {
    final from = pushedFrom?.call();
    final body = ragdoll.bodyNamed(chest);
    if (from == null || body == null) return;
    // At the top of the chest, not its root: a bone's pose is its head, which
    // for the chest is the small of the back, below the body's centre of
    // mass, and a blow there knocks the hips out and sits the body down.
    // Above it, the same blow turns the body back over its feet.
    final pose = ragdoll.ragdoll.poseOf(body);
    final bone = ragdoll.ragdoll.bones[body];
    final at =
        pose.position +
        turnBy(
          pose.orientation,
          turnBy(bone.orientation.conjugated(), bone.tail - bone.head),
        ).scaled(_blowAlong);
    final away = Vector3(at.x - from.x, 0.0, at.z - from.z);
    if (away.length2 < 1e-6) return;
    away
      ..normalize()
      ..y = 0.25
      ..scale(push);
    _dynamics.native.applyImpulse(ragdoll.ragdoll.bodyOf(body), away, at: at);
  }

  @override
  void step(double dt) {
    if (_ragdolls.isEmpty) return;
    _owed += dt;
    var steps = 0;
    while (_owed >= stepSeconds && steps < mostStepsAFrame) {
      _dynamics.step(stepSeconds);
      _owed -= stepSeconds;
      steps++;
    }
    if (steps == mostStepsAFrame) _owed = 0.0;
    for (final ragdoll in _ragdolls.values) {
      ragdoll.apply();
    }
  }

  @override
  void end(Actor actor) => _ragdolls.remove(actor)?.dispose();

  /// Which actors lie dead, as a [SnapshotPart] under [id]: their entities,
  /// generation and all, so a rewind, a rollback or the double-step check
  /// that goes back to before an actor died lets its body go rather than
  /// leaving it lying beside the actor standing again.
  ///
  /// **Only which, not where.** Where a body lies is a pose on the frame,
  /// and its core is this class's own: a body that lay at the snapshot and
  /// still lies keeps falling as it was. One that lay at the snapshot and
  /// has gone since is not made again — the model it was drawn from is the
  /// visuals' — and its actor falls again if it dies again.
  SnapshotPart snapshotPart({String id = 'flutter3d.game_physics.corpses'}) =>
      SnapshotPart.of(
        id: id,
        capture: () =>
            <int>[for (final actor in _ragdolls.keys) actor.entity.packed]
              ..sort(),
        restore: (data, _) {
          final lying = <int>{
            if (data is List<Object?>)
              for (final entity in data)
                if (entity is int) entity,
          };
          for (final actor in _ragdolls.keys.toList()) {
            if (!lying.contains(actor.entity.packed)) end(actor);
          }
        },
      );

  @override
  void dispose() {
    for (final ragdoll in _ragdolls.values) {
      ragdoll.dispose();
    }
    _ragdolls.clear();
    _dynamics.dispose();
  }
}

/// How far up the chest bone the killing blow lands, as a fraction of its
/// length: the upper chest, where a shot hits, and above the centre of mass
/// at every height a rig puts it, so the blow turns the body back.
const double _blowAlong = 0.75;
