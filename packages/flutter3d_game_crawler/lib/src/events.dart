/// What a step of a crawl did, for a game that wants to hear about it.
///
/// Drained from `CrawlerSimulation.events` after each step. They say what
/// happened; the sound, the announcer's line and the sparkle are the game's.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'hero.dart';
import 'loot.dart';

/// A hero walked into something and took it.
final class LootTaken extends GameEvent {
  const LootTaken(this.hero, this.loot);

  final Hero hero;
  final Loot loot;

  @override
  String get name => '${hero.kind.name} took ${loot.runtimeType}';
}

/// A hero spent a key on a door.
final class DoorUnlocked extends GameEvent {
  const DoorUnlocked(this.hero, this.door);

  final Hero hero;
  final Door door;

  @override
  String get name => '${hero.kind.name} unlocked ${door.name ?? 'a door'}';
}

/// A hero's health has just fallen low: the announcer's cue.
final class HeroHungry extends GameEvent {
  const HeroHungry(this.hero);

  final Hero hero;

  @override
  String get name => '${hero.kind.name} needs food';
}

/// A hero's health ran out.
final class HeroDied extends GameEvent {
  const HeroDied(this.hero);

  final Hero hero;

  @override
  String get name => '${hero.kind.name} died';
}
