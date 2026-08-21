import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'mechanism.dart';

/// Something lying in the world that one toucher can take, once.
///
/// **Two games had written this class, and they had written the same one.**
/// `flutter3d_game_shooter`'s `Pickup` and `flutter3d_platformer`'s `Collectible`
/// were a hundred lines each with the same base, the same trigger wiring in the
/// constructor, the same `_taken`/`justTaken` bookkeeping, the same `collect`,
/// and the same shape of `activate` — take the toucher's `userData`, ask whether
/// it can accept, refuse with [NothingToDo] if not, and otherwise mark it taken
/// and remove the collider. What differed was one line: **what is offered, and
/// to whom.**
///
/// So that one line is the hook. Everything either of them had in common is
/// here, and [offerTo] is what a genre writes — a health pack into an inventory,
/// a count into a purse. This class has no idea what either of those is, which
/// is the whole reason it can hold both.
///
/// Extended rather than configured with a callback, because a genre wants its
/// own type: both applications ask `mechanism is Pickup` or
/// `is Collectible` to decide how to draw it, and a shared class with a closure
/// in it would have taken that away. Keeping the names cost the games nothing —
/// neither application changed a line when this arrived.
abstract base class Takeable extends Mechanism with CollisionListener {
  Takeable({
    super.name,
    required this.collider,
    this.retryWhileTouching = false,
  }) {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this
      ..listener = this;
  }

  /// The volume that has to be touched. Removed from the world once taken,
  /// rather than left behind as a trigger nothing can fire.
  final Collider collider;

  /// Whether standing on it keeps offering it.
  ///
  /// **False is the ordinary case and true is the interesting one.** A coin is
  /// never refused, so one touch settles it. A health pack offered to somebody
  /// already whole *is* refused — and the moment they are hurt, still standing
  /// on it, it should be theirs. Without this the player has to step off and
  /// back on, which reads as the pack being broken.
  final bool retryWhileTouching;

  bool _taken = false;
  bool get isTaken => _taken;

  /// Taken during this step, for whoever is collecting the step's events.
  ///
  /// Cleared in [step] rather than by the reader, because two readers would
  /// each clear it and the second would see nothing.
  bool justTaken = false;

  /// Seconds since it was taken, or infinity while it has not been.
  ///
  /// For whatever draws it: a taken thing usually shrinks or fades rather than
  /// vanishing between two frames. Infinity rather than a nullable double so
  /// that "has it finished vanishing" is one comparison and is false for a
  /// thing nobody has touched — a distinction that has already been got wrong
  /// once, and drew every coin in a level as already spent.
  double sinceTaken = double.infinity;

  /// What to tell the player, if anything. Set by [offerTo] where a genre wants
  /// one; carried to the events by [collect].
  String? message;

  @override
  Vector3 get origin => collider.position;

  /// Offers this to [taker], and answers whether they took it.
  ///
  /// [taker] is the toucher's `userData`, which is whatever the game put there
  /// — so an implementation begins by asking whether it is the kind of thing
  /// that can accept, and answers false if it is not. False leaves everything
  /// exactly as it was: not taken, still in the world, still offering.
  bool offerTo(Object? taker);

  @override
  void collect(MechanismEvents into) {
    if (!justTaken) return;
    into.taken.add(this);
    final said = message;
    if (said != null) into.messages.add(said);
  }

  @override
  ActivationOutcome activate(Activation by) {
    if (_taken) return const NothingToDo();
    if (!offerTo(by.by?.userData)) return const NothingToDo();

    _taken = true;
    justTaken = true;
    sinceTaken = 0.0;
    world.collisions.removeLater(collider);
    return const Activated();
  }

  @override
  void onCollisionStart(Collider self, Collider other) {
    activate(world.activationBy(other));
  }

  @override
  void onCollision(Collider self, Collider other) {
    if (retryWhileTouching && !_taken) activate(world.activationBy(other));
  }

  @override
  void step(double dt) {
    justTaken = false;
    if (_taken && sinceTaken.isFinite) sinceTaken += dt;
  }

  /// Only whether it is gone.
  ///
  /// What was *in* it is the taker's now and is saved with the taker; saving it
  /// here as well would be two answers to one question, and the one that loaded
  /// second would win.
  @override
  Map<String, Object?> save() => <String, Object?>{'taken': _taken};

  @override
  void restore(Map<String, Object?> from) {
    _taken = from['taken'] == true;
    justTaken = false;
    sinceTaken = double.infinity;
    if (_taken) world.collisions.removeLater(collider);
  }
}
