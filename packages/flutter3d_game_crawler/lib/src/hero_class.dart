/// What kind of hero somebody chose to be.
///
/// **Data, and an open set.** A `final class` with `static const` instances
/// rather than an enum, for the reason the repository gives about every enum
/// in a published package: a game that wants a fifth class adds one beside
/// these, and nothing anywhere switches over the four exhaustively.
///
/// Four to start with, and the numbers are the choice of the arcade shape:
/// one who takes hits, one who moves fast, and two in between. What they
/// shoot and what their magic does arrive with the shots.
final class HeroClass {
  const HeroClass({
    required this.name,
    required this.speed,
    required this.damageTaken,
  });

  /// What the character-select screen calls it, and what a save writes.
  final String name;

  /// Walking speed, in metres per second.
  final double speed;

  /// The share of every blow that lands, from nought to one. Armour, as a
  /// multiplier rather than a pool: it never wears out, which is what makes
  /// the warrior the one to stand in front.
  ///
  /// Not applied to the drain. Hunger goes through armour.
  final double damageTaken;

  /// Slow, and takes the least from a blow.
  static const HeroClass warrior = HeroClass(
    name: 'warrior',
    speed: 4.2,
    damageTaken: 0.7,
  );

  /// Well armoured and quicker than the warrior.
  static const HeroClass valkyrie = HeroClass(
    name: 'valkyrie',
    speed: 4.8,
    damageTaken: 0.8,
  );

  /// No armour at all.
  static const HeroClass wizard = HeroClass(
    name: 'wizard',
    speed: 4.8,
    damageTaken: 1.0,
  );

  /// The fastest, and lightly armoured.
  static const HeroClass elf = HeroClass(
    name: 'elf',
    speed: 5.8,
    damageTaken: 0.9,
  );

  /// The four, in the order a select screen shows them.
  static const List<HeroClass> all = <HeroClass>[
    warrior,
    valkyrie,
    wizard,
    elf,
  ];
}
