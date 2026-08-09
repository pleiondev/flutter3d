import '../physics/collider.dart';
import 'key_ring.dart';
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

/// A key lying on the floor, waiting to be walked over.
///
/// Not a [Signal] — it switches nothing on, it changes what the player is
/// carrying, which is the one thing a locked door reads. Stage 9 generalises
/// this into pickups; until then a door with a lock needs a key to exist.
final class KeyPickup extends Mechanism with CollisionListener {
  KeyPickup({
    super.name,
    required this.colour,
    required this.collider,
  }) {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this
      ..listener = this;
  }

  /// Which lock it opens.
  final String colour;

  final Collider collider;

  bool _taken = false;
  bool get isTaken => _taken;

  /// True on the step it was picked up, so the game can say so once.
  bool justTaken = false;

  @override
  ActivationOutcome activate(Activation by) {
    if (_taken) return const NothingToDo();
    final holder = by.by?.userData;
    if (holder is! KeyRing) return const NothingToDo();
    if (!holder.take(colour)) return const NothingToDo();

    _taken = true;
    justTaken = true;
    // Out of the world entirely rather than merely disabled: a collected key
    // that still reports overlaps is a key that keeps announcing itself. After
    // the step, because this runs from inside the overlap dispatch.
    world.collisions.removeLater(collider);
    return const Activated();
  }

  @override
  void onCollisionStart(Collider self, Collider other) {
    activate(world.activationBy(other));
  }

  @override
  void step(double dt) => justTaken = false;
}
