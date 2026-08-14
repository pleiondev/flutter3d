/// Something a rocket can hurt.
///
/// ## Why this exists
///
/// A collider carries a `userData` saying who it is, and until now every place
/// that dealt damage had to switch over that: `if (userData is Monster) … else
/// if (layer == player) …`. Two of those switches existed, one for hitscan and
/// one for a blast, and neither could be written by a game with a third thing
/// worth shooting — a barrel, a window, a vehicle, another player.
///
/// One interface removes both. A caller asks whether the thing it hit can be
/// hurt and hurts it; who that is, and what being hurt means, belong to the
/// thing rather than to the shooter.
///
/// ## What it must not become
///
/// **The implementation belongs where the state machine is.** A monster that
/// subtracted from its own health would work and would skip everything its
/// system does about it: the corpse would stay solid, the kill would not be
/// counted, the flinch would not be rolled, and nothing would appear in
/// `MonsterSystem.died`. The delegation is the point — see `Monster`, which
/// hands the call back to the system that spawned it.
abstract interface class Damageable {
  /// Takes [amount] of damage and answers whether that killed it.
  ///
  /// Killing is worth reporting because a caller usually has something to do
  /// with the news — a score, a sound, a door that opens when the room is
  /// clear — and asking afterwards means asking a thing that may already have
  /// been cleaned up.
  bool applyDamage(double amount);
}
