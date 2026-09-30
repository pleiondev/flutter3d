/// What lies on the floor of the maze for a hero to walk into.
///
/// Each is a [Takeable], so the trigger wiring, the once-only taking and the
/// save come from the engine; what each gives is one method. Only a living
/// hero takes anything: a monster walking over the food leaves it where it
/// is.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'hero.dart';

/// Anything a hero picks up by walking into it.
abstract base class Loot extends Takeable {
  Loot({super.name, required super.collider});

  /// Who took it, on the step they did, for the event that says so.
  Hero? takenBy;

  @override
  bool offerTo(Object? taker) {
    if (taker is! Hero || !taker.isAlive) return false;
    give(taker);
    takenBy = taker;
    return true;
  }

  /// What taking this does to [hero].
  void give(Hero hero);
}

/// Health, and the only way to get it back.
final class Food extends Loot {
  Food({super.name, required super.collider, this.amount = 100.0});

  final double amount;

  @override
  void give(Hero hero) => hero.feed(amount);
}

/// Opens one locked door, any of them, and is used up doing it.
final class DoorKey extends Loot {
  DoorKey({super.name, required super.collider});

  @override
  void give(Hero hero) => hero.keys += 1;
}

/// Carried until it is drunk, and then everything on screen suffers.
final class Potion extends Loot {
  Potion({super.name, required super.collider});

  @override
  void give(Hero hero) => hero.potions += 1;
}

/// Score, and nothing else.
final class Treasure extends Loot {
  Treasure({super.name, required super.collider, this.worth = 100});

  final int worth;

  @override
  void give(Hero hero) => hero.score += worth;
}
