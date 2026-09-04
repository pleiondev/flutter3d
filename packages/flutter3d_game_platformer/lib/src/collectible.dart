import 'package:flutter3d_game/flutter3d_game.dart';

import 'purse.dart';

/// Something the runner walks into and keeps.
///
/// **Almost all of this is [Takeable] now**, which the shooter's `Pickup` is
/// too: the trigger, the "taken once and only once" bookkeeping, the fade after
/// it is gone, and the rule that a refusal leaves the world exactly as it was.
/// What is left here is the two lines that make it this game's — a count into a
/// purse, and the key that some of them carry.
///
/// The class keeps its name because the application asks `mechanism is
/// Collectible` to decide how to draw it. That is why [Takeable] is a base to
/// extend rather than a class to configure.
final class Collectible extends Takeable {
  Collectible({
    super.name,
    required this.what,
    required super.collider,
    this.howMany = 1,
    this.worth = 0.0,
    this.key,
  });

  /// What it counts as in the purse. A name rather than a type, so a level
  /// document can invent one without this file changing.
  final String what;

  final int howMany;

  /// What taking it is worth, before the chain in hand is applied.
  ///
  /// **Separate from [howMany], which is a count and not a value.** Three
  /// coins and one gem are four things taken, and a level that wanted the gem
  /// to be worth more had nowhere to say so: the purse counted and nothing
  /// scored. Zero scores nothing at all, which is what a key is worth.
  final double worth;

  /// Which door it opens, if it opens one.
  final String? key;

  @override
  bool offerTo(Object? taker) {
    // Narrowed through a second name rather than by promoting the parameter,
    // because a `Gatherer` does not narrow again to a `KeyTaker` — the two are
    // unrelated interfaces and the same taker answers to both. The original did
    // exactly this, by reading `userData` twice.
    final gatherer = taker;
    if (gatherer is! Gatherer) return false;
    if (!gatherer.purse.add(what, howMany)) return false;

    // After the purse, not before: a key handed out for a pickup that was then
    // refused is a door that opens for nothing.
    final unlocks = key;
    if (unlocks != null && taker is KeyTaker) taker.keyRing.take(unlocks);
    return true;
  }
}
