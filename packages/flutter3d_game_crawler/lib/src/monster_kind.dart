/// What comes out of a generator.
///
/// Data in the same open shape as `HeroClass`: a game adds a kind beside these
/// and hands the list to its `Horde`, which is what a save names them by.
library;

final class MonsterKind {
  const MonsterKind({
    required this.name,
    required this.health,
    required this.speed,
    this.radius = 0.35,
    this.height = 1.6,
    this.bite = 0.0,
    this.touch = 0.0,
    this.score = 10,
  }) : assert(
         (bite > 0.0) != (touch > 0.0),
         'a monster either bites while it is close or strikes once and is '
         'gone, not both and not neither',
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

  /// What killing one is worth.
  final int score;

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

  /// The kinds this package ships, and the list a `Horde` reads by default.
  static const List<MonsterKind> all = <MonsterKind>[grunt, ghost];
}
