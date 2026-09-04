import 'blast.dart';
import 'weapon_behaviour.dart';

/// What a weapon spends when it fires.
///
/// Separate counters rather than one pool, which is the decision that makes
/// weapon choice interesting: running dry on shells is a reason to switch, and
/// a shared pool turns every weapon into the same weapon with different
/// numbers.
///
/// **A value class rather than an enum, so this list is not closed.** A game
/// written on this template writes its own weapons, and a weapon that fires
/// something has to be able to say what: cells, fuel, arrows, a spell's mana.
/// As an enum it could not, and adding a value to let it broke every
/// `switch` in every game already published — which for a template is the
/// worst shape a type can have, because the whole point is that somebody else
/// extends it.
///
/// The four below are what this template ships. A game adds
/// `const AmmoType('cells')` beside them and nothing here has to know.
///
/// **There is no `values`.** A list of every type that exists cannot be kept
/// once anybody can add one, and it was the wrong question anyway: a HUD wants
/// the counters this arsenal actually holds, not every kind of ammunition the
/// package can name. [Arsenal.ammo] answers that.
final class AmmoType {
  const AmmoType(this.name);

  /// What it is called. Identity: two [AmmoType]s with the same name are the
  /// same ammunition, which is what lets a game name one in a level document
  /// and in code without a registry in between.
  final String name;

  /// The starting weapon never runs out, so it is always something to fall back
  /// to. A player stranded with no weapon at all is a player reloading a save.
  static const AmmoType none = AmmoType('none');
  static const AmmoType bullets = AmmoType('bullets');
  static const AmmoType shells = AmmoType('shells');
  static const AmmoType rockets = AmmoType('rockets');

  @override
  bool operator ==(Object other) => other is AmmoType && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'AmmoType($name)';
}

/// Everything about a weapon that does not change while it is being fired.
///
/// A record of numbers rather than a class per weapon. Every one of these is
/// going to be adjusted dozens of times by feel, and the differences between a
/// pistol and a shotgun are entirely in the numbers — which is exactly the case
/// where a subclass per weapon buys nothing and costs a rebuild per tweak.
final class WeaponDef {
  const WeaponDef({
    required this.name,
    required this.behaviour,
    this.alternate,
    this.magazine,
    this.reloadSeconds = 1.5,
    required this.ammo,
    required this.damage,
    required this.shotsPerSecond,
    this.ammoPerShot = 1,
    this.rayCount = 1,
    this.spread = 0.0,
    this.range = 120.0,
    this.automatic = false,
    this.falloffStart = 0.0,
    this.falloffEnd = 0.0,
    this.minimumDamageFraction = 0.25,
    this.knockback = 0.0,
    this.loudness = 18.0,
    this.recoil = 0.0,
    this.recoilRecovery = 7.0,
    this.projectileSpeed = 0.0,
    this.splashRadius = 0.0,
    this.splashMinimumFraction = 0.0,
  });

  final String name;

  /// The other trigger, or null for a weapon with one.
  ///
  /// **A whole [WeaponDef] rather than a handful of overrides**, so an
  /// alternate fire is described exactly as a weapon is: its own behaviour, its
  /// own ammunition and cost, its own damage, spread, range and falloff. A
  /// shotgun whose second trigger fires both barrels differs from the first in
  /// four numbers and a cooldown, and expressing that as a list of nullable
  /// overrides would have been four ways to get it half-written.
  ///
  /// The alternate's own [alternate] is not read. Two triggers is what a
  /// weapon has; a third is a weapon.
  ///
  /// **One cooldown, shared.** [Arsenal] puts the weapon on cooldown whichever
  /// trigger fired it, because it is one weapon in one pair of hands. A game
  /// that wants a grenade launcher whose barrel reloads independently of its
  /// tube has two weapons and a slot each, which is what the slots are for.
  final WeaponDef? alternate;

  /// How far the sight jumps on each shot, in radians.
  ///
  /// **The sight, not the model.** A weapon whose picture kicks and whose aim
  /// does not is a weapon with no recoil at all wearing an animation: the
  /// second shot of a burst goes exactly where the first did, and a player who
  /// notices that stops looking at the screen and starts holding the trigger.
  /// This moves where the bullets go.
  ///
  /// Zero by default, which keeps every weapon that has not been given a number
  /// behaving as it did. A pistol is a hundredth of a radian or so — about half
  /// a degree — and an automatic climbs because that is applied ten times a
  /// second and only pulled back at [recoilRecovery].
  final double recoil;

  /// How fast the sight comes back down, per second.
  ///
  /// Recovery rather than a spring: the kick is added and eased away, so a
  /// burst climbs while it is held and settles when it stops. Fast enough that
  /// single shots feel like a flinch and slow enough that automatic fire has to
  /// be controlled.
  final double recoilRecovery;

  /// How a shot is delivered. See [WeaponBehaviour] for why this is an object
  /// and the numbers below are not.
  final WeaponBehaviour behaviour;

  final AmmoType ammo;

  /// Damage of a single ray at point-blank range.
  ///
  /// Per ray, not per shot: a shotgun's stopping power is the number of pellets
  /// that connect, which is what makes range matter to it and not to a pistol.
  final double damage;

  final double shotsPerSecond;
  final int ammoPerShot;

  /// How many shots the weapon holds before it has to be reloaded, or null for
  /// one that never does.
  ///
  /// **Null rather than a large number**, so a weapon with no magazine is a
  /// weapon this machinery does not touch: no reload can be asked for, no
  /// timer runs, and `Arsenal` behaves exactly as it did. Every weapon this
  /// template ships is one of those, because a crypt's pace is about switching
  /// weapons rather than about waiting.
  ///
  /// **The wait is the point, and it is not free.** A reload is a few seconds
  /// a player cannot shoot for, so it is the one thing in this file that can
  /// get somebody killed by a number rather than by a decision. A game that
  /// adds one should mean it.
  final int? magazine;

  /// How long a reload takes, in seconds. Ignored without a [magazine].
  final double reloadSeconds;

  /// How many rays one shot fires.
  final int rayCount;

  /// Half-angle of the cone the rays fall in, in radians.
  final double spread;

  final double range;

  /// Whether holding the trigger keeps firing.
  final bool automatic;

  /// Distance at which damage starts dropping. Zero disables falloff.
  final double falloffStart;

  /// Distance at which damage has dropped to [minimumDamageFraction].
  final double falloffEnd;

  final double minimumDamageFraction;

  /// Impulse applied to what is hit, along the ray.
  final double knockback;

  /// How far this is heard, in metres.
  ///
  /// **Here rather than worked out from the damage**, and the roster is why the
  /// first attempt at that was wrong: a shotgun does 11 per pellet across eight
  /// of them and the fists do 20 in one go, so damage says the fists are the
  /// loudest thing in the game. Loudness is not a consequence of anything else
  /// on this record — it is its own number, adjusted by feel like the rest of
  /// them, and that is exactly what this class is for.
  ///
  /// The default is an ordinary gunshot. A melee weapon sets it low; something
  /// silenced would set it to nothing at all, which is a design this leaves
  /// room for without having a word for it.
  final double loudness;

  /// Metres per second, for a weapon that launches something.
  ///
  /// Finite and fairly slow on purpose: a projectile the target can see coming
  /// and step out of is the whole difference between a rocket launcher and a
  /// very loud rifle.
  final double projectileSpeed;

  /// How far the explosion reaches. Zero for anything that does not explode.
  final double splashRadius;

  /// Fraction of the damage still delivered at the edge of the blast.
  final double splashMinimumFraction;

  /// The explosion this weapon produces, or null if it makes none.
  Blast? get blast => splashRadius <= 0.0
      ? null
      : Blast(
          radius: splashRadius,
          damage: damage,
          minimumFraction: splashMinimumFraction,
          knockback: knockback,
        );

  /// Seconds between shots.
  Duration get cooldown =>
      Duration(microseconds: (1e6 / shotsPerSecond).round());

  double get cooldownSeconds => 1.0 / shotsPerSecond;

  /// Damage a single ray does at [distance].
  ///
  /// Linear between the two thresholds. Not an inverse square, and not a hard
  /// cliff: the first is unreadable to a player and the second makes a step
  /// backwards feel like a bug.
  double damageAt(double distance) {
    if (falloffEnd <= falloffStart) return damage;
    if (distance <= falloffStart) return damage;
    if (distance >= falloffEnd) return damage * minimumDamageFraction;

    final t = (distance - falloffStart) / (falloffEnd - falloffStart);
    return damage * (1.0 - t * (1.0 - minimumDamageFraction));
  }
}
