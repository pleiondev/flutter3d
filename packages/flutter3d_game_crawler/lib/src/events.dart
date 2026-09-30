/// What a step of a crawl did, for a game that wants to hear about it.
///
/// Drained from `CrawlerSimulation.events` after each step. They say what
/// happened; the sound, the announcer's line and the sparkle are the game's.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'generator.dart';
import 'hero.dart';
import 'loot.dart';
import 'monster_kind.dart';

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

/// A hero killed a monster, by shot, by hand or by potion.
final class MonsterSlain extends GameEvent {
  const MonsterSlain(this.hero, this.kind, this.at);

  final Hero hero;
  final MonsterKind kind;

  /// Where it fell, copied: the body is gone by the time anybody reads this.
  final Vector3 at;

  @override
  String get name => '${hero.kind.name} slew a ${kind.name}';
}

/// A hero broke a generator.
final class GeneratorDestroyed extends GameEvent {
  const GeneratorDestroyed(this.hero, this.generator);

  final Hero hero;
  final Generator generator;

  @override
  String get name =>
      '${hero.kind.name} broke ${generator.name ?? 'a generator'}';
}

/// A hero drank a potion, and this is how many things it reached.
final class PotionDrunk extends GameEvent {
  const PotionDrunk(this.hero, this.struck);

  final Hero hero;
  final int struck;

  @override
  String get name => '${hero.kind.name} drank a potion';
}

/// A hero's health ran out.
final class HeroDied extends GameEvent {
  const HeroDied(this.hero);

  final Hero hero;

  @override
  String get name => '${hero.kind.name} died';
}
