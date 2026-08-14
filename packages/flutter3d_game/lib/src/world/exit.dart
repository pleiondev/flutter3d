/// The way out of a level.
///
/// `ExitKind` validated an entity and then spawned nothing at all, which made
/// `exit` the one word in the level vocabulary that a document could contain
/// and the game could not act on — and `Level.next` a field nothing ever read.
/// A level could be authored as finishable and simply was not.
///
/// It is a [Mechanism] rather than something the game watches for, so that the
/// two things a level author expects of it come free: it can be **locked**,
/// the same way a door is and by the same key check; and it can be **switched
/// on by something else**, because every mechanism can — a button, a trigger,
/// the last monster in the room relayed through one. An exit that only reacted
/// to being walked into would need all of that written again.
library;

import 'package:vector_math/vector_math.dart';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'mechanism.dart';

final class Exit extends Mechanism with CollisionListener {
  Exit({
    super.name,
    required this.collider,
    this.next,
    this.message,
    this.key,
  }) {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this
      ..listener = this;
  }

  final Collider collider;

  /// The level that follows this one, overriding `Level.next`.
  ///
  /// Null is the common case and means "whatever the level says". A per-exit
  /// answer is what makes a level with two doors lead to two places, which is
  /// the only reason this is not simply read off the level.
  final String? next;

  /// What to tell the player on the way out.
  final String? message;

  /// A key they must be carrying, or null.
  final String? key;

  bool get isReached => _reached;
  bool _reached = false;

  /// True on the step it was reached, so the game can act once.
  ///
  /// Cleared in [step] rather than in [collect], exactly as `Pickup` clears
  /// `justTaken`: a collector that consumed the flag would mean whichever
  /// caller looked first won, and the rest saw nothing.
  bool justReached = false;

  @override
  Vector3 get origin => collider.position;

  @override
  ActivationOutcome activate(Activation by) {
    // Not a failure and not worth a message: the player is standing in the
    // doorway they already opened, and the level is already over.
    if (_reached) return const NothingToDo();

    final needed = key;
    if (needed != null && !by.keys.contains(needed)) {
      return Refused('You need the $needed key.');
    }

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

  Map<String, Object?> save() => <String, Object?>{'reached': _reached};

  void restore(Map<String, Object?> from) {
    _reached = from['reached'] == true;
    justReached = false;
  }

  @override
  void collect(MechanismEvents into) {
    if (!justReached) return;
    into.reached.add(this);
    final said = message;
    if (said != null) into.messages.add(said);
  }
}
