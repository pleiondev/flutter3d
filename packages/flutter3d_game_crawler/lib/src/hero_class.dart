/// What kind of hero somebody chose to be.
///
/// **Data, and an open set.** A `final class` with `static const` instances
/// rather than an enum, for the reason the repository gives about every enum
/// in a published package: a game that wants a fifth class adds one beside
/// these, and nothing anywhere switches over the four exhaustively.
///
/// Four to start with, and the numbers are the choice of the arcade shape:
/// the warrior takes hits and hits hard up close, the elf is fast and shoots
/// often, the wizard has no armour and the strongest magic, and the valkyrie
/// sits in the middle of everything.
final class HeroClass {
  const HeroClass({
    required this.name,
    required this.speed,
    required this.damageTaken,
    required this.shotDamage,
    required this.shotSpeed,
    required this.shotInterval,
    required this.melee,
    required this.magic,
  });

  /// What the character-select screen calls it, and what a save writes.
  final String name;

  /// Walking speed, in metres per second.
  final double speed;

  /// The share of every blow that lands, from nought to one. Armour, as a
  /// multiplier rather than a pool: it never wears out, which is what makes
  /// the warrior the one to stand in front.
  ///
  /// Not applied to the drain: armour does nothing against hunger.
  final double damageTaken;

  /// What one shot does to whatever it reaches.
  final double shotDamage;

  /// How fast a shot flies, in metres per second.
  final double shotSpeed;

  /// Seconds between shots while fire is held.
  final double shotInterval;

  /// Damage a second to everything the hero is pressed against. The arcade's
  /// fighting hand to hand: walking into a monster is attacking it.
  final double melee;

  /// How much a potion does in this hero's hands, as a multiple of
  /// `CrawlerSimulation.potionDamage`.
  final double magic;

  /// Slow, hardest to hurt, and the strongest hand to hand.
  static const HeroClass warrior = HeroClass(
    name: 'warrior',
    speed: 4.2,
    damageTaken: 0.7,
    shotDamage: 30.0,
    shotSpeed: 14.0,
    shotInterval: 0.45,
    melee: 60.0,
    magic: 0.5,
  );

  /// Well armoured and quicker than the warrior.
  static const HeroClass valkyrie = HeroClass(
    name: 'valkyrie',
    speed: 4.8,
    damageTaken: 0.8,
    shotDamage: 20.0,
    shotSpeed: 16.0,
    shotInterval: 0.4,
    melee: 45.0,
    magic: 0.75,
  );

  /// No armour at all, and the strongest magic.
  static const HeroClass wizard = HeroClass(
    name: 'wizard',
    speed: 4.8,
    damageTaken: 1.0,
    shotDamage: 20.0,
    shotSpeed: 16.0,
    shotInterval: 0.35,
    melee: 20.0,
    magic: 1.5,
  );

  /// The fastest, lightly armoured, and the quickest to shoot.
  static const HeroClass elf = HeroClass(
    name: 'elf',
    speed: 5.8,
    damageTaken: 0.9,
    shotDamage: 15.0,
    shotSpeed: 20.0,
    shotInterval: 0.25,
    melee: 20.0,
    magic: 1.0,
  );

  /// The four, in the order a select screen shows them.
  static const List<HeroClass> all = <HeroClass>[
    warrior,
    valkyrie,
    wizard,
    elf,
  ];
}
