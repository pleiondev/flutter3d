/// Someone a pickup can give something to.
///
/// ## The regression this exists because of
///
/// `Pickup` used to read the toucher's `userData` and require it to be an
/// `Inventory` outright. That was true right up until `userData` was given one
/// meaning — *who is this collider* — and the player's collider started
/// carrying the `Player` instead of the bag they hold.
///
/// **Every pickup in the game stopped working that day**: health, armour, ammo,
/// keys, power-ups. Three hundred tests did not notice, because the test
/// harness for pickups put an `Inventory` in `userData` itself and so kept
/// testing an arrangement the game no longer had. What found it was the first
/// test the application ever had, on its first run, by walking a player onto a
/// key and watching nothing happen.
///
/// So: the same shape as [Damageable] and [KeyHolder]. A collider says who it
/// is; whether that someone can be given something is a question they answer
/// themselves, and a game whose vehicle collects fuel says so by implementing
/// this.
library;

import 'inventory.dart';

abstract interface class Collector {
  /// What they are carrying, and where a gift goes.
  Inventory get inventory;
}
