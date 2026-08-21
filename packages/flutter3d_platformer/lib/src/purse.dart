import 'package:flutter3d_game/flutter3d_game.dart';

/// What somebody has picked up, counted by name.
///
/// The counting itself is [Tally] in the engine, which the shooter's
/// end-of-level count uses too; what is this game's is the word — a purse is
/// something a runner carries, and a run's total is the thing the ending adds
/// up.
///
/// Not an inventory. `Inventory` in `flutter3d_game_shooter` holds health, armour,
/// ammunition by type and a set of weapons, and every one of those is a
/// shooter's idea; a platformer counts coins and stars and does not care what
/// they are for. The two were the same class once, which is how the engine came
/// to have ammunition in it.
final class Purse extends Tally {}

/// Someone a collectible can be given to.
///
/// The same shape as `Damageable` and `Collector`: a collider says *who* it is,
/// and whether that someone gathers things is a question they answer.
abstract interface class Gatherer {
  Purse get purse;
}

/// Someone a key can be given to.
///
/// Separate from [Gatherer] because a key is not a count: you hold it or you do
/// not, for ever, and a `Purse` that could answer "how many blue keys" would be
/// answering a question no door asks. `KeyRing` in the engine is that set, and
/// this is how a pickup reaches one without knowing whose it is.
abstract interface class KeyTaker {
  KeyRing get keyRing;
}
