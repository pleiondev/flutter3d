import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'collector.dart';
import 'gift.dart';

/// Something on the floor, waiting to be walked over.
///
/// Not a [Signal] — it switches nothing on, it changes what the player is
/// carrying. What it gives is a [Gift], so adding a new kind of pickup is a
/// gift class rather than a branch in here.
///
/// A pickup that cannot be used is refused and stays put. That is the rule a
/// medkit at full health depends on, and getting it wrong is the difference
/// between a level that rewards coming back and one that quietly eats things.
///
/// It lives beside the gifts rather than beside [Button] and [TriggerVolume],
/// which it once did, because a bag with health, armour, ammunition and
/// weapons in it is a shooter's idea of what may be picked up. The mechanism a
/// pickup is built from — [Mechanism], [MechanismEvents.taken], removal from
/// the world — stays in the engine, and `taken` is a list of mechanisms rather
/// than a list of these, which is what let this move without touching it.
final class Pickup extends Mechanism with CollisionListener {
  Pickup({
    super.name,
    required this.gift,
    required this.amount,
    required this.collider,
    this.detail,
  }) {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this
      ..listener = this;
  }

  final Gift gift;

  /// How much, in whatever unit the gift counts in — points, rounds, seconds.
  final double amount;

  /// The one extra word some gifts need: a key's colour.
  final String? detail;

  final Collider collider;

  bool _taken = false;
  bool get isTaken => _taken;

  /// True on the step it was collected, so the game can say so once.
  bool justTaken = false;

  @override
  Vector3 get origin => collider.position;

  @override
  void collect(MechanismEvents into) {
    if (!justTaken) return;
    into.taken.add(this);
    final said = message;
    if (said != null) into.messages.add(said);
  }

  /// What to tell the player about it, valid on the step it was taken.
  String? message;

  @override
  ActivationOutcome activate(Activation by) {
    if (_taken) return const NothingToDo();
    final holder = by.by?.userData;
    // Not `is Inventory`: a collider says *who* it is, and what they carry is
    // a question they answer. See [Collector], which is there because getting
    // this wrong silently broke every pickup in the game.
    if (holder is! Collector) return const NothingToDo();
    if (!gift.grantTo(holder.inventory, amount, detail)) {
      return const NothingToDo();
    }

    _taken = true;
    justTaken = true;
    message = gift.announce(amount, detail);
    // Out of the world entirely rather than merely disabled: a collected
    // pickup that still reports overlaps keeps announcing itself. After the
    // step, because this runs from inside the overlap dispatch.
    world.collisions.removeLater(collider);
    return const Activated();
  }

  @override
  void onCollisionStart(Collider self, Collider other) {
    activate(world.activationBy(other));
  }

  /// Still overlapping, and still worth trying: a medkit refused at full health
  /// should be collected the moment the player is hurt while standing on it.
  @override
  void onCollision(Collider self, Collider other) {
    if (!_taken) activate(world.activationBy(other));
  }

  @override
  void step(double dt) => justTaken = false;

  @override
  Map<String, Object?> save() => <String, Object?>{'taken': _taken};

  @override
  void restore(Map<String, Object?> from) {
    _taken = from['taken'] == true;
    justTaken = false;
    // A pickup taken before the save must not be standing there again. It was
    // removed from the world when it was collected, so putting it back is the
    // caller's problem only if the caller reloaded the level — and then this
    // has to take it away again.
    if (_taken) world.collisions.removeLater(collider);
  }
}
