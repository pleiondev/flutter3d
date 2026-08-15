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
    this.key,
  }) {
    collider
      ..kind = ColliderKind.trigger
      ..userData = this
      ..listener = this;
  }

  /// What it counts as in a [Purse]: `coin`, `star`, whatever the level says.
  final String what;

  final int howMany;

  /// A key this also grants, or null.
  ///
  /// One class rather than two, because a key *is* a thing on the floor you
  /// walk over — everything about picking it up is identical and only where it
  /// lands differs. What makes that honest rather than lazy is that a taker
  /// answers two questions separately: [Gatherer] for the count, [KeyTaker] for
  /// the key, and a game may implement either alone.
  final String? key;

  final Collider collider;

  bool _taken = false;
  bool get isTaken => _taken;

  /// True on the step it was collected, so a game can say so once.
  bool justTaken = false;

  /// Seconds since it was taken, and infinite while it is still there.
  ///
  /// The simulation has no opinion about how a coin leaves — that is a look —
  /// but only the simulation knows *when* it left, so it counts and the game
  /// decides what to do with the number.
  double sinceTaken = double.infinity;

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
    final unlocks = key;
    final taker = by.by?.userData;
    if (unlocks != null && taker is KeyTaker) taker.keyRing.take(unlocks);

    _taken = true;
    justTaken = true;
    sinceTaken = 0.0;
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
  void step(double dt) {
    justTaken = false;
    if (_taken && sinceTaken.isFinite) sinceTaken += dt;
  }

  Map<String, Object?> save() => <String, Object?>{'taken': _taken};

  void restore(Map<String, Object?> from) {
    _taken = from['taken'] == true;
    justTaken = false;
    // Whatever it was doing when the save happened, a coin taken before it has
    // finished shrinking by the time it is loaded: restoring mid-animation
    // would put a half-sized coin in a room the player has already cleared.
    sinceTaken = double.infinity;
    if (_taken) world.collisions.removeLater(collider);
  }
}
