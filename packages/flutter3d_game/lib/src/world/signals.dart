import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'gift.dart';
import 'inventory.dart';
import 'mechanism.dart';

/// A panel on a wall that fires its target when the player presses use.
///
/// Its collider is a trigger, so walking into it is impossible and the ray from
/// the crosshair still finds it. A button that blocked movement would be a
/// button players get stuck on.
final class Button extends Signal {
  Button({
    super.name,
    required super.target,
    required this.collider,
    super.once = false,
    this.key,
  }) {
    collider.kind = ColliderKind.trigger;
    collider.userData = this;
  }

  final Collider collider;

  /// A key the player must be carrying, or null.
  final String? key;

  @override
  ActivationOutcome activate(Activation by) {
    final needed = key;
    if (needed != null && !by.keys.contains(needed)) {
      return Refused('You need the $needed key.');
    }
    return fire(by);
  }
}

/// A volume that fires its target when something walks into it.
///
/// Listens for the collision rather than polling, so a fast body cannot cross
/// a thin trigger between two steps without being noticed — the world's sweep
/// found the overlap, and this only has to hear about it.
final class TriggerVolume extends Signal with CollisionListener {
  TriggerVolume({
    super.name,
    required super.target,
    required this.collider,
    super.once = false,
  }) {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this
      ..listener = this;
  }

  final Collider collider;

  /// The last thing this told the player, for the frame it happened on.
  ///
  /// A trigger fires from inside the physics step, where there is nobody to
  /// return an outcome to; the game reads this afterwards. Cleared on read so
  /// a message shows once rather than for as long as the player stands there.
  ActivationOutcome? takeOutcome() {
    final outcome = _outcome;
    _outcome = null;
    return outcome;
  }

  ActivationOutcome? _outcome;

  @override
  void onCollisionStart(Collider self, Collider other) {
    _outcome = fire(world.activationBy(other));
  }

  /// Stepping into a trigger is the activation; asking it directly does the
  /// same thing, which is what lets one trigger be chained from another.
  @override
  ActivationOutcome activate(Activation by) => fire(by);
}

/// Something on the floor, waiting to be walked over.
///
/// Not a [Signal] — it switches nothing on, it changes what the player is
/// carrying. What it gives is a [Gift], so adding a new kind of pickup is a
/// gift class rather than a branch in here.
///
/// A pickup that cannot be used is refused and stays put. That is the rule a
/// medkit at full health depends on, and getting it wrong is the difference
/// between a level that rewards coming back and one that quietly eats things.
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

  /// What to tell the player about it, valid on the step it was taken.
  String? message;

  @override
  ActivationOutcome activate(Activation by) {
    if (_taken) return const NothingToDo();
    final holder = by.by?.userData;
    if (holder is! Inventory) return const NothingToDo();
    if (!gift.grantTo(holder, amount, detail)) return const NothingToDo();

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
}
