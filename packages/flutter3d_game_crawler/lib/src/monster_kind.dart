/// What comes out of a generator.
///
/// Data in the same open shape as `HeroClass`: a game adds a kind beside these
/// and hands the list to its `Horde`, which is what a save names them by.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'horde.dart';
import 'thief.dart';

final class MonsterKind {
  const MonsterKind({
    required this.name,
    required this.health,
    required this.speed,
    this.radius = 0.35,
    this.height = 1.6,
    this.bite = 0.0,
    this.touch = 0.0,
    this.appetite = double.infinity,
    this.shotproof = false,
    this.score = 10,
    this.mind = Chaser.new,
  }) : assert(
         bite <= 0.0 || touch <= 0.0,
         'a monster either bites while it is close or strikes once and is '
         'gone, not both',
       );

  /// What a save calls it. Unique within a horde's list.
  final String name;

  final double health;

  /// Walking speed, in metres per second.
  final double speed;

  /// Half its width, and its height, in metres.
  final double radius;
  final double height;

  /// Damage a second to the hero it is pressed against.
  final double bite;

  /// Damage dealt once, on reaching a hero, after which it is gone. The
  /// ghost's way: it is a thing to shoot before it arrives rather than a thing
  /// to fight.
  final double touch;

  /// How much it deals, in all, before it has had enough and is gone. Endless
  /// for most; Death leaves once it has drained its fill.
  final double appetite;

  /// Whether shots and blows pass through it harmlessly, so that only a potion
  /// reaches it.
  final bool shotproof;

  /// What killing one is worth.
  final int score;

  /// The mind a monster of this kind is born with.
  final Brain Function(MonsterKind kind) mind;

  /// Walks up and keeps biting.
  static const MonsterKind grunt = MonsterKind(
    name: 'grunt',
    health: 30.0,
    speed: 3.2,
    bite: 12.0,
  );

  /// Faster and frailer, and spends itself on the first hero it reaches.
  static const MonsterKind ghost = MonsterKind(
    name: 'ghost',
    health: 10.0,
    speed: 3.8,
    radius: 0.3,
    touch: 25.0,
  );

  /// Drains health fast, cannot be shot or fought, and leaves once it has
  /// taken two hundred. A potion is the only answer, and a weak one may not be
  /// enough.
  static const MonsterKind death = MonsterKind(
    name: 'death',
    health: 40.0,
    speed: 3.6,
    bite: 100.0,
    appetite: 200.0,
    shotproof: true,
    score: 100,
  );

  /// Harms nobody. Takes a potion or a key from the hero it reaches and runs;
  /// killed before it gets away, it gives the thing back.
  static const MonsterKind thief = MonsterKind(
    name: 'thief',
    health: 20.0,
    speed: 5.0,
    radius: 0.3,
    score: 50,
    mind: Thief.new,
  );

  /// The kinds this package ships, and the list a `Horde` reads by default.
  static const List<MonsterKind> all = <MonsterKind>[
    grunt,
    ghost,
    death,
    thief,
  ];
}
