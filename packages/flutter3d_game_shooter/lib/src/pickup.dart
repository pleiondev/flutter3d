import 'package:flutter3d_game/flutter3d_game.dart';

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
/// It is also why this one asks to be offered again while it is being stood on:
/// refused at full health, it should be theirs the moment they are hurt, and
/// without that the player has to step off and back on.
///
/// **The machinery moved to [Takeable]**, which the platformer's `Collectible`
/// extends as well — the trigger, the taken-once bookkeeping, the refusal
/// leaving the world untouched, all of it was written twice and is now written
/// once. What stayed is what makes it a pickup: a gift, an amount, and the line
/// it says when it lands.
final class Pickup extends Takeable {
  Pickup({
    super.name,
    required this.gift,
    required this.amount,
    required super.collider,
    this.detail,
  }) : super(retryWhileTouching: true);

  final Gift gift;

  final double amount;

  /// Which one, where a gift has kinds — a key's colour, a weapon's name.
  final String? detail;

  @override
  bool offerTo(Object? taker) {
    if (taker is! Collector) return false;
    if (!gift.grantTo(taker.inventory, amount, detail)) return false;

    message = gift.announce(amount, detail);
    return true;
  }
}
