import 'blast.dart';
import 'weapon_behaviour.dart';

/// What a weapon spends when it fires.
///
/// Separate counters rather than one pool, which is the decision that makes
/// weapon choice interesting: running dry on shells is a reason to switch, and
/// a shared pool turns every weapon into the same weapon with different
/// numbers.
enum AmmoType {
  /// The starting weapon never runs out, so it is always something to fall back
  /// to. A player stranded with no weapon at all is a player reloading a save.
  none,
  bullets,
  shells,
  rockets,
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
    this.projectileSpeed = 0.0,
    this.splashRadius = 0.0,
    this.splashMinimumFraction = 0.0,
  });

  final String name;

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
  Duration get cooldown => Duration(
        microseconds: (1e6 / shotsPerSecond).round(),
      );

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


/// What the player is carrying, and whether the trigger will do anything.
///
/// Free of the collision world on purpose: this decides *whether* a shot
/// happens and what it costs, and [Hitscan] decides what it hits. Keeping them
/// apart is what lets the firing rules — cooldown, ammo, switching — be tested
/// without a level.
final class Arsenal {
  /// [slots] is every weapon this game has, in the order its keys select them.
  ///
  /// **Separate from what is owned, and that was a defect until now.**
  /// `selectSlot` used to index a global roster of this repository's own four
  /// weapons: a game with its own would ask for slot two, be handed somebody
  /// else's shotgun, and then search its inventory for a weapon of that name.
  /// It found none and quietly did nothing.
  ///
  /// Indexing what is *owned* instead would be worse in a way that is harder to
  /// see: the slot a key selects would move as things were picked up, so slot
  /// three is the rocket launcher until you find the shotgun and then it is
  /// not.
  ///
  /// [owned] defaults to all of [slots], because a game that lists its weapons
  /// and says nothing about ownership means the player has them.
  Arsenal({
    required List<WeaponDef> slots,
    List<WeaponDef>? owned,
    Map<AmmoType, int>? ammo,
    int startingSlot = 0,
  })  : slots = List<WeaponDef>.unmodifiable(slots),
        _owned = owned ?? List<WeaponDef>.of(slots),
        _ammo = ammo ?? <AmmoType, int>{},
        // Zero, then resolved through [selectSlot] below. A *slot* is an index
        // into the game's roster and `_current` is an index into what is
        // owned, and this class has now confused the two three times: once in
        // `selectSlot`, once here, and once in a saved index. An arsenal that
        // owns two of four weapons and starts on slot three used to throw a
        // `RangeError` on its first step.
        _current = 0 {
    selectSlot(startingSlot);
  }

  /// Every weapon this game has, in the order its keys select them.
  final List<WeaponDef> slots;

  /// How much of each type can be carried.
  static const Map<AmmoType, int> capacity = <AmmoType, int>{
    AmmoType.bullets: 200,
    AmmoType.shells: 60,
    AmmoType.rockets: 30,
  };

  final List<WeaponDef> _owned;
  final Map<AmmoType, int> _ammo;
  int _current;

  /// Seconds still to wait before the next shot.
  double _cooldown = 0.0;

  List<WeaponDef> get owned => List<WeaponDef>.unmodifiable(_owned);

  /// Whether anything is being held at all.
  ///
  /// True for a game with no weapons in it, and for a player who has not
  /// picked one up yet. Everything asked once a step — [canFire],
  /// [wantsToFire], [fire], [fallBackIfEmpty] — answers correctly for that
  /// case, so no caller has to test this first.
  bool get isEmpty => _owned.isEmpty;

  /// What is being held.
  ///
  /// Throws when [isEmpty]. A sentinel "empty hands" weapon would be a lie
  /// every caller then has to detect anyway, and a nullable return would put a
  /// check in the HUD, the view model and the crosshair for a case none of
  /// them can do anything about.
  WeaponDef get current {
    if (_owned.isEmpty) {
      throw StateError('nothing is being held: check Arsenal.isEmpty first');
    }
    return _owned[_current];
  }
  int get currentIndex => _current;
  double get cooldownRemaining => _cooldown;

  int ammoOf(AmmoType type) =>
      type == AmmoType.none ? -1 : (_ammo[type] ?? 0);

  int get currentAmmo => isEmpty ? 0 : ammoOf(current.ammo);

  bool owns(WeaponDef weapon) =>
      _owned.any((WeaponDef w) => w.name == weapon.name);

  /// Adds a weapon, and switches to it the way a shooter should: picking up
  /// something new is a small event, and having to notice it in the corner of
  /// the HUD spoils it.
  bool pickUp(WeaponDef weapon) {
    if (owns(weapon)) return false;
    _owned.add(weapon);
    _current = _owned.length - 1;
    return true;
  }

  /// Returns how much was actually taken, which is less than [amount] when the
  /// pouch is nearly full and zero when it is full.
  int addAmmo(AmmoType type, int amount) {
    if (type == AmmoType.none || amount <= 0) return 0;
    final limit = capacity[type] ?? 0;
    final held = _ammo[type] ?? 0;
    final taken = amount.clamp(0, limit - held);
    if (taken <= 0) return 0;
    _ammo[type] = held + taken;
    return taken;
  }

  /// Switches to the weapon in [slot], if it is owned.
  ///
  /// Switching does not reset the cooldown, so tapping between two weapons is
  /// not a way to fire faster than either of them allows.
  bool selectSlot(int slot) {
    if (slot < 0 || slot >= slots.length) return false;
    final wanted = slots[slot];
    for (var i = 0; i < _owned.length; i++) {
      if (_owned[i].name == wanted.name) {
        _current = i;
        return true;
      }
    }
    return false;
  }

  /// What is owned, held and loaded — by **name**.
  ///
  /// A weapon definition is content: a save that copied its damage and rate of
  /// fire would restore a pistol balanced the way it was on the day the save
  /// was taken, and a patch that changed a number would never reach anybody who
  /// had played before it. The names are looked back up in [slots], which is
  /// the game's own roster.
  Map<String, Object?> save() => <String, Object?>{
        'owned': <String>[for (final weapon in _owned) weapon.name],
        'current': _current,
        'cooldown': _cooldown,
        'ammo': <String, int>{
          for (final entry in _ammo.entries) entry.key.name: entry.value,
        },
      };

  void restore(Map<String, Object?> from) {
    final names = from['owned'];
    if (names is List) {
      _owned.clear();
      for (final name in names) {
        for (final weapon in slots) {
          if (weapon.name == name) {
            _owned.add(weapon);
            break;
          }
        }
      }
    }
    _current = (from['current'] as num?)?.toInt() ?? 0;
    // A saved index into a roster that has since shrunk would throw on the
    // first shot rather than on load, which is the worse of the two places.
    if (_current >= _owned.length) _current = _owned.isEmpty ? 0 : 0;
    _cooldown = (from['cooldown'] as num?)?.toDouble() ?? 0.0;
    final ammo = from['ammo'];
    if (ammo is Map) {
      _ammo.clear();
      for (final type in AmmoType.values) {
        final held = ammo[type.name];
        if (held is num) _ammo[type] = held.toInt();
      }
    }
  }

  void advanceTime(double dt) {
    if (_cooldown > 0.0) _cooldown = (_cooldown - dt).clamp(0.0, double.infinity);
  }

  /// Whether pulling the trigger right now would fire.
  bool get canFire =>
      !isEmpty &&
      _cooldown <= 0.0 &&
      (current.ammo == AmmoType.none ||
          ammoOf(current.ammo) >= current.ammoPerShot);

  /// Whether the trigger being [held] should fire this step.
  ///
  /// An automatic weapon fires while held; the rest need the press edge, which
  /// the caller reports as [pressed].
  bool wantsToFire({required bool held, required bool pressed}) =>
      !isEmpty && (current.automatic ? held : pressed);

  /// Spends a shot. Returns the weapon fired, or null when it could not.
  WeaponDef? fire() {
    if (!canFire) return null;
    final weapon = current;
    if (weapon.ammo != AmmoType.none) {
      _ammo[weapon.ammo] = ammoOf(weapon.ammo) - weapon.ammoPerShot;
    }
    _cooldown = weapon.cooldownSeconds;
    return weapon;
  }

  /// Picks the best weapon that still has ammo.
  ///
  /// Called when the current one runs dry: leaving the player holding an empty
  /// weapon and clicking is worse than choosing for them.
  void fallBackIfEmpty() {
    if (isEmpty || canFire || _cooldown > 0.0) return;
    for (var i = _owned.length - 1; i >= 0; i--) {
      final weapon = _owned[i];
      if (weapon.ammo == AmmoType.none ||
          ammoOf(weapon.ammo) >= weapon.ammoPerShot) {
        _current = i;
        return;
      }
    }
  }
}
