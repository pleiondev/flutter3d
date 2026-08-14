import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'purse.dart';

/// A coin, a star, a scrap of whatever this game counts.
///
/// The same mechanism a shooter's pickup is, and deliberately not the same
/// class: that one grants a [Gift] into an `Inventory` full of ammunition, and
/// arriving at a shared abstraction over "adds ammo" and "adds a coin" would
/// mean inventing a word neither game says. What they genuinely share —
/// [Mechanism], the trigger collider, removal from the world, `taken` on
/// [MechanismEvents] — is in the engine, and both of these are forty lines.
final class Collectible extends Mechanism with CollisionListener {
  Collectible({
    super.name,
    required this.what,
    required this.collider,
    this.howMany = 1,
  }) {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this
      ..listener = this;
  }

  /// What it counts as in a [Purse]: `coin`, `star`, whatever the level says.
  final String what;

  final int howMany;

  final Collider collider;

  bool _taken = false;
  bool get isTaken => _taken;

  /// True on the step it was collected, so a game can say so once.
  bool justTaken = false;

  @override
  Vector3 get origin => collider.position;

  @override
  void collect(MechanismEvents into) {
    if (justTaken) into.taken.add(this);
  }

  @override
  ActivationOutcome activate(Activation by) {
    if (_taken) return const NothingToDo();
    final who = by.by?.userData;
    if (who is! Gatherer) return const NothingToDo();
    if (!who.purse.add(what, howMany)) return const NothingToDo();

    _taken = true;
    justTaken = true;
    // Out of the world rather than merely disabled, and after the step, because
    // this runs from inside the overlap dispatch.
    world.collisions.removeLater(collider);
    return const Activated();
  }

  @override
  void onCollisionStart(Collider self, Collider other) {
    activate(world.activationBy(other));
  }

  @override
  void step(double dt) => justTaken = false;

  Map<String, Object?> save() => <String, Object?>{'taken': _taken};

  void restore(Map<String, Object?> from) {
    _taken = from['taken'] == true;
    justTaken = false;
    if (_taken) world.collisions.removeLater(collider);
  }
}
