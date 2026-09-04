import 'combat/weapon.dart';

/// What this game's monsters may be, as words in a level document.
///
/// `EntityTypes` holds the format's own vocabulary — spawn, door, trigger,
/// exit. `monster` is not the format's; it is a shooter's, the same way `torch`
/// is furniture. It lives beside the kind that implements it.
abstract final class ShooterEntities {
  static const String monster = 'monster';

  /// Two that used to be `EntityTypes`'. A pickup that gives health, armour or
  /// ammunition, and a note left on a wall to be read, are furniture of this
  /// genre rather than of the format — the same argument that moved `torch`,
  /// `lamp` and `window` out before them.
  ///
  /// `key` is not here, and the difference is worth the sentence: the *pickup*
  /// that grants a key is this genre's, but the word belongs to the format,
  /// because `LevelScope` gathers keys to check that a locked door names one
  /// that exists.
  static const String pickup = 'pickup';
  static const String note = 'note';

  /// A volume that counts as found when somebody walks into it.
  ///
  /// A word this genre owns for the same reason `monster` is: a racing game has
  /// no secrets and a platformer's are collectibles, which it already has.
  static const String secret = 'secret';
}

/// What a monster is doing.
///
/// An enum with a switch, deliberately, and **only because it is in here**. Six
/// states that share every transition — anything can be hurt, anything hurt
/// enough dies, anything that sees the player chases them — would be six
/// classes repeating one another's rules. That trade is fine for one brain in
/// one game's own library; it was not fine in an engine, where it meant every
/// other kind of enemy anybody wrote had to pretend to have an `alert` state.
/// What a monster is doing.
///
/// **A value class rather than an enum, so a game can add to it.** The six
/// below are what [ChaseBrain] decides between; a game that wants a monster
/// that flees, or summons, or guards a spot, names its own state and writes a
/// [Brain] that means it. That is the extension point for behaviour — this is
/// the label, and it is open so a game's brain and a game's animation table
/// can share the vocabulary rather than inventing a parallel one.
///
/// **Adding a state does not teach [ChaseBrain] anything.** That brain knows
/// these six and says, in its own `think` and `act`, what it does with a state
/// it does not recognise. Opening a vocabulary without opening its interpreter
/// is the trap this repository has hit twice; the interpreter here is `Brain`,
/// and it was already open.
///
/// **There is no `values`.** A list of every state that exists cannot be kept
/// once anybody can add one; the six are named individually and a save is
/// restored from the name it holds.
final class MonsterState {
  const MonsterState(this.name);

  /// What it is called, in a save and in an animation table. Identity: two
  /// states with the same name are the same state.
  final String name;

  static const MonsterState idle = MonsterState('idle');
  static const MonsterState alert = MonsterState('alert');
  static const MonsterState chase = MonsterState('chase');
  static const MonsterState attack = MonsterState('attack');
  static const MonsterState hurt = MonsterState('hurt');
  static const MonsterState dead = MonsterState('dead');

  /// The six [ChaseBrain] decides between, for a table that wants to list
  /// them. A game adds its own; there is no registry, for the reason
  /// [GameAction.common] gives — a list nobody has to keep up to date cannot
  /// fall behind.
  static const List<MonsterState> chased = <MonsterState>[
    idle,
    alert,
    chase,
    attack,
    hurt,
    dead,
  ];

  @override
  bool operator ==(Object other) => other is MonsterState && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'MonsterState($name)';
}

/// Everything about a kind of monster that does not change.
///
/// Numbers, plus the weapon it attacks with. Reusing `WeaponDef` rather than
/// inventing a parallel notion of a monster attack: an attack has damage, a
/// rate, a range and a way of arriving, which is a weapon — and it means a
/// monster that throws fireballs gets the projectile system, the blast falloff
/// and the line-of-sight check without a line of new code.
final class MonsterDef {
  const MonsterDef({
    required this.name,
    required this.health,
    required this.speed,
    required this.attack,
    required this.radius,
    required this.height,
    this.sightRange = 26.0,
    this.hurtDuration = 0.25,
    this.alertDuration = 0.35,
    this.turnRate = 6.0,
    this.painChance = 1.0,
    this.painCooldown = 0.2,
  });

  final String name;
  final double health;
  final double speed;
  final WeaponDef attack;
  final double radius;
  final double height;

  /// How far it can notice the player.
  final double sightRange;

  /// How long a stagger lasts. Long enough to read as a reaction, short enough
  /// that it cannot be used to stun-lock something to death.
  final double hurtDuration;

  /// How long it hesitates after noticing before it comes. A monster that
  /// snaps to face the player the instant it sees them reads as a turret.
  final double alertDuration;

  final double turnRate;

  /// How often being hit staggers it.
  ///
  /// Not always: something that flinches at every pellet can be held in place
  /// by a shotgun and never reaches the player, which turns the hardest enemy
  /// into the easiest.
  final double painChance;

  /// How long after a stagger before it can be staggered again.
  final double painCooldown;
}
