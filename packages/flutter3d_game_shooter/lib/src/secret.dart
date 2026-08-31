import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// A place the level rewards you for finding.
///
/// **The oldest thing in the genre and this game had none of it.** A shooter
/// with no secrets is a shooter where a wall that looks odd is just a wall, and
/// where nothing is gained by looking at the level rather than through it.
///
/// A trigger and a flag, which is all it is: the reward is whatever the author
/// put behind it, and the count is what the ending reads. Found once and never
/// again — walking back through is not another secret, and a player who does it
/// twice has not found two.
final class Secret extends Mechanism with CollisionListener {
  Secret({super.name, required this.collider}) {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this
      ..listener = this;
  }

  final Collider collider;

  bool get isFound => _found;
  bool _found = false;

  /// True on the step it was first entered, for a message and a sound.
  bool justFound = false;

  @override
  Vector3 get origin => collider.position;

  @override
  ActivationOutcome activate(Activation by) {
    if (_found) return const NothingToDo();
    // Only somebody counts. A rocket flying through a secret has not found it,
    // and neither has a crate pushed into one.
    if (by.by == null) return const NothingToDo();
    _found = true;
    justFound = true;
    return const Activated();
  }

  @override
  void onCollisionStart(Collider self, Collider other) {
    activate(world.activationBy(other));
  }

  @override
  void step(double dt) => justFound = false;

  @override
  Map<String, Object?> save() => <String, Object?>{'found': _found};

  @override
  void restore(Map<String, Object?> from) {
    _found = from['found'] == true;
    justFound = false;
  }
}
