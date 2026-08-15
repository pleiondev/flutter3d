import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// Something a spring can throw.
///
/// The same shape as [Gatherer] and [KeyTaker]: a collider says who it is, and
/// whether that someone can be launched is a question they answer. A crate
/// could implement this too and would then need no change here.
abstract interface class Launchable {
  /// Throws this upward at [speed] metres a second.
  ///
  /// A speed rather than an impulse, because a spring is a promise about height
  /// — the level author placed it to reach a particular ledge, and a mass they
  /// cannot see must not change the answer.
  void launch(double speed);
}

/// A pad that throws whatever stands on it.
///
/// A trigger rather than a solid: the runner walks over it and is thrown, which
/// is one rule. A solid pad would need a second — what happens when you land on
/// its edge — and every platformer that has tried has produced the bug where a
/// player bounces sideways into a pit.
final class Spring extends Mechanism with CollisionListener {
  Spring({
    super.name,
    required this.collider,
    this.speed = 15.0,
  }) {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this
      ..listener = this;
  }

  final Collider collider;

  /// How fast it throws. 15 m/s clears about 4.7 m against the runner's
  /// gravity, which is two and a half times a jump and reads as a launch.
  final double speed;

  /// True on the step it fired, for a sound and a squash.
  bool firedThisStep = false;

  @override
  Vector3 get origin => collider.position;

  @override
  void step(double dt) => firedThisStep = false;

  @override
  ActivationOutcome activate(Activation by) {
    final who = by.by?.userData;
    if (who is! Launchable) return const NothingToDo();
    who.launch(speed);
    firedThisStep = true;
    return const Activated();
  }

  @override
  void onCollisionStart(Collider self, Collider other) {
    activate(world.activationBy(other));
  }

  /// Still overlapping and still worth firing: a runner who lands on a pad and
  /// is thrown may come back down onto it before the overlap ever ends, and a
  /// spring that only answers on entry would quietly stop working.
  @override
  void onCollision(Collider self, Collider other) {
    if (!firedThisStep) activate(world.activationBy(other));
  }
}
