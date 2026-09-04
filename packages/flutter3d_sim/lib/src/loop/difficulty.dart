/// How hard a game is being, as numbers a genre applies where it decides.
///
/// **Four axes, and they are deliberately not a list of settings.** A
/// difficulty that named `monsterHealth` would belong to one genre; these are
/// the questions every genre in this repository turned out to be asking of the
/// same idea — how much the player is punished, how much they achieve, how
/// sharp the opposition is, and how much the game helps. A racing game reads
/// the third and the fourth and ignores the first two; a platformer reads the
/// first and the fourth. Nothing here decides which.
///
/// **A value class rather than an enum, so a game can make its own.** Four
/// named settings ship, and a game that wants "nightmare" or a slider a player
/// drags writes `const Difficulty('nightmare', damageTaken: 2.5)` — or builds
/// one at run time from whatever the player chose. As an enum it could not, and
/// adding a value would have broken every `switch` a published game had.
///
/// **Multipliers rather than absolutes, and one is not.** Three of the four
/// scale a number the genre already had, so a genre that has no such number
/// simply never reads that axis and nothing has to be nullable. [assistance] is
/// the exception: it is a fraction from nothing to everything, because "how
/// much help" has no base value to multiply.
///
/// The numbers below are a starting point rather than a claim: they are round,
/// they were not tuned against a player, and the doc on each says what it would
/// take to settle it. A game that ships should tune its own and say so.
final class Difficulty {
  const Difficulty(
    this.name, {
    this.damageTaken = 1.0,
    this.damageDealt = 1.0,
    this.opponentReaction = 1.0,
    this.assistance = 0.0,
  }) : assert(damageTaken >= 0.0, 'a negative multiplier heals'),
       assert(damageDealt >= 0.0, 'a negative multiplier heals'),
       assert(opponentReaction > 0.0, 'an opponent that never reacts is not'),
       assert(
         assistance >= 0.0 && assistance <= 1.0,
         'assistance is a fraction of the help available, from none to all',
       );

  /// What it is called, on a menu and in a save. Identity: two difficulties
  /// with the same name are the same difficulty.
  final String name;

  /// What the player is hurt by, multiplied.
  ///
  /// The axis every action game turns first, and the one a player feels
  /// immediately: half damage is twice as many mistakes before dying.
  final double damageTaken;

  /// What the player's own attacks are worth, multiplied.
  ///
  /// Separate from [damageTaken] because they are not the same experience.
  /// Taking less damage makes a fight longer and more forgiving; dealing more
  /// makes it shorter. A setting that moved both together could offer neither
  /// on its own.
  final double damageDealt;

  /// How quickly the opposition reacts, multiplied — **and it is a duration,
  /// so smaller is harder.**
  ///
  /// Named for what it scales rather than for what it means, because the sign
  /// is the thing people get wrong: a monster's alert duration and a driver's
  /// reaction time are both waits, and a harder game makes them shorter. The
  /// four below have this below one on the hard settings, which reads oddly
  /// until you know that.
  final double opponentReaction;

  /// How much of whatever help the genre offers is switched on, from none to
  /// all.
  ///
  /// A fraction rather than a multiplier, and the one axis that is not scaling
  /// something that exists: a braking line, a wider coyote window, an aim that
  /// nudges. A genre with no help ignores it, which is not the same as a genre
  /// with the help turned off.
  final double assistance;

  /// Everything half as sharp and all the help on. For a player who wants the
  /// level rather than the fight.
  static const Difficulty gentle = Difficulty(
    'gentle',
    damageTaken: 0.5,
    damageDealt: 1.5,
    opponentReaction: 1.5,
    assistance: 1.0,
  );

  /// What every number in this repository was tuned at. The default, and the
  /// one the other three are described against.
  static const Difficulty normal = Difficulty('normal');

  /// Sharper opposition, half again the damage taken, and no help. What the
  /// player deals is left alone on purpose: the first step up should be about
  /// surviving the fight rather than about it taking longer.
  static const Difficulty hard = Difficulty(
    'hard',
    damageTaken: 1.5,
    opponentReaction: 0.7,
  );

  /// Everything at once. Not a tuned setting — a stated extreme, so a game has
  /// somewhere to put a fourth entry without inventing the numbers.
  static const Difficulty punishing = Difficulty(
    'punishing',
    damageTaken: 2.5,
    damageDealt: 0.75,
    opponentReaction: 0.5,
  );

  /// The four that ship, for a menu that wants to list them.
  ///
  /// A game adds its own; there is no registry, for the reason
  /// [GameAction.common] gives — a list nobody has to keep up to date cannot
  /// fall behind.
  static const List<Difficulty> offered = <Difficulty>[
    gentle,
    normal,
    hard,
    punishing,
  ];

  @override
  bool operator ==(Object other) => other is Difficulty && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'Difficulty($name)';
}
