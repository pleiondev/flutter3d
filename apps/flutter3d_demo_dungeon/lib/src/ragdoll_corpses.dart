import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// The crypt's monsters fall as bodies — N1.
///
/// A monster that dies hands its skeleton to a ragdoll in the physics core,
/// which falls against the level as the core sees it: the level's walls and
/// floors, the player and every monster still standing, all mirrored from the
/// collision world by a [NativeDynamics] of this one's own. The dead are
/// triggers by then, so a monster does not fall against the capsule it died
/// in.
///
/// **Display, not simulation.** The game's step never asks where a corpse
/// lies — the dead block nothing — so this steps on the frame, in fixed steps
/// of its own, and is not in a save or a replay: a corpse is a pose, as a
/// particle is a point.
final class RagdollCorpses implements ActorCorpses {
  /// [shotFrom] says where the shots come from — the player — and a corpse
  /// is pushed away from there as it falls; null pushes nobody.
  RagdollCorpses(CollisionWorld world, {this.shotFrom})
    : _dynamics = NativeDynamics(
        world: world,
        gravity: Vector3(0.0, -9.81, 0.0),
      )..native.substeps = 8;

  final NativeDynamics _dynamics;

  /// Where the shot that killed a monster came from, asked when it dies.
  final Vector3? Function()? shotFrom;

  /// How hard the killing shot pushes the chest, N s: a 60 kg runner
  /// thrown back at two metres a second, as a body and not a statue.
  static const double shotPush = 120.0;
  final Map<Actor, SkeletonRagdoll> _ragdolls = <Actor, SkeletonRagdoll>{};
  double _owed = 0.0;

  /// The core's steps, a sixtieth of a second each.
  static const double stepSeconds = 1.0 / 60.0;

  /// How many steps a frame may take before the rest is forgiven: a frame
  /// that stalled for a second does not owe the corpses sixty.
  static const int mostStepsAFrame = 4;

  /// How many corpses are falling or lying.
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
        mass: 60.0,
        previous: previous,
        dt: dt,
      );
    } on ArgumentError {
      // A rig the profile does not know: it plays its death clip instead.
      return false;
    }
    _push(_ragdolls[actor]!);
    return true;
  }

  /// The killing shot into [ragdoll]'s chest: away from where it came from,
  /// level, and a little up, so the body leaves the floor it stood on.
  void _push(SkeletonRagdoll ragdoll) {
    final from = shotFrom?.call();
    final chest = ragdoll.bodyNamed('Torso');
    if (from == null || chest == null) return;
    final at = ragdoll.ragdoll.poseOf(chest).position;
    final away = Vector3(at.x - from.x, 0.0, at.z - from.z);
    if (away.length2 < 1e-6) return;
    away
      ..normalize()
      ..y = 0.25
      ..scale(shotPush);
    _dynamics.native.applyImpulse(ragdoll.ragdoll.bodyOf(chest), away, at: at);
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

  @override
  void dispose() {
    for (final ragdoll in _ragdolls.values) {
      ragdoll.dispose();
    }
    _ragdolls.clear();
    _dynamics.dispose();
  }
}
