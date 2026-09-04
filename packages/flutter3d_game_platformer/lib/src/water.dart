/// Water a runner can be inside, and what being inside it changes.
///
/// **A volume rather than a surface.** Everything else this genre stands on is
/// a floor with numbers hung off it — ice, mud, a conveyor — and the surface
/// table handles all of them. Water is the first thing that is not underfoot:
/// a runner is *in* it, at any height, and what changes is gravity, the top
/// speed, and whether up is a direction they can go. A surface could express
/// none of that.
///
/// **A [Mechanism], because it is a trigger volume and this genre already has
/// those.** A level names one exactly as it names a spring, and the level
/// format needed nothing new.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// How a body behaves in water.
///
/// **Separate from [RunnerTuning] on purpose.** A level with two pools — a
/// shallow one to cross and a tar pit that nearly holds you — says so by
/// giving them different tuning, and a game with one kind of water passes the
/// same object twice. Putting these on the runner would have made every pool
/// in a level identical.
final class SwimTuning {
  const SwimTuning({
    this.buoyancy = 6.0,
    this.sinkSpeed = 2.0,
    this.riseSpeed = 3.0,
    this.drag = 3.0,
    this.speed = 3.4,
  });

  /// Upward acceleration while submerged, in metres per second squared.
  ///
  /// **Below gravity on purpose**, so a runner who does nothing sinks slowly
  /// rather than bobbing to the top: floating up by itself reads as a bug the
  /// first time a player wants to reach something underneath.
  final double buoyancy;

  /// The fastest a runner sinks, in metres a second.
  final double sinkSpeed;

  /// How fast holding jump carries a runner upwards.
  final double riseSpeed;

  /// How hard the water slows horizontal movement, per second.
  final double drag;

  /// Top speed while swimming, in metres a second.
  final double speed;
}

/// A body of water, as a trigger a runner can be inside.
///
/// Holds no state of its own: whether a runner is in it is a question about
/// where the runner is, asked once a step, and a mechanism that remembered the
/// answer would be a mechanism that disagreed with the world after a teleport.
final class Water extends Mechanism {
  Water({
    super.name,
    required this.collider,
    this.tuning = const SwimTuning(),
  }) {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this;
  }

  final Collider collider;
  final SwimTuning tuning;

  @override
  Vector3 get origin => collider.position;

  /// Whether [point] is under the surface.
  ///
  /// **The point rather than the body**, and the caller passes the runner's
  /// chest: a capsule whose toes are wet is walking through a puddle, and one
  /// whose head is under is swimming. Choosing which point decides it is the
  /// game's, and it is the difference between wading and drowning.
  bool holds(Vector3 point) {
    final box = collider.shape;
    if (box is! CollisionBox) return false;
    final at = collider.position;
    final half = box.halfExtents;
    return (point.x - at.x).abs() <= half.x &&
        (point.y - at.y).abs() <= half.y &&
        (point.z - at.z).abs() <= half.z;
  }

  /// Nothing to activate. Water is somewhere you are, not something you press.
  @override
  ActivationOutcome activate(Activation by) => const NothingToDo();

  /// **Nothing to save.** A pool is where the level put it and holds no state
  /// of its own; whether somebody is in it is a question about where they are,
  /// asked fresh every step. A mechanism that saved the answer would disagree
  /// with the world after a teleport.
  @override
  Map<String, Object?> save() => const <String, Object?>{};

  @override
  void restore(Map<String, Object?> from) {}
}
