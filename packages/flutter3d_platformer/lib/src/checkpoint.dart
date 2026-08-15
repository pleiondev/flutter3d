import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

/// A place the level puts you back at.
///
/// Ordered rather than "the last one touched", because a player who walks back
/// through an earlier checkpoint has not undone their progress — and "last
/// touched" is the implementation everybody writes first and nobody notices is
/// wrong until somebody backtracks for a coin they missed.
final class Checkpoint extends Mechanism with CollisionListener {
  Checkpoint({
    super.name,
    required this.collider,
    required this.order,
    Vector3? at,
  }) : at = at ?? collider.position.clone() {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this
      ..listener = this;
  }

  final Collider collider;

  /// Where along the level this one is. Bigger is further on.
  final int order;

  /// Where the runner reappears. Its own vector rather than the collider's,
  /// because a checkpoint may be a wide volume whose centre is inside a wall.
  final Vector3 at;

  bool _reached = false;
  bool get isReached => _reached;

  /// True on the step it was first reached, for a sound or a flag going up.
  bool justReached = false;

  @override
  Vector3 get origin => collider.position;

  @override
  ActivationOutcome activate(Activation by) {
    if (_reached) return const NothingToDo();
    // Anything that can be put back is worth remembering a spot for; the
    // simulation decides whose spot it keeps.
    if (by.by == null) return const NothingToDo();
    _reached = true;
    justReached = true;
    return const Activated();
  }

  @override
  void onCollisionStart(Collider self, Collider other) {
    activate(world.activationBy(other));
  }

  @override
  void step(double dt) => justReached = false;

  @override
  Map<String, Object?> save() => <String, Object?>{'reached': _reached};

  @override
  void restore(Map<String, Object?> from) {
    _reached = from['reached'] == true;
    justReached = false;
  }
}
