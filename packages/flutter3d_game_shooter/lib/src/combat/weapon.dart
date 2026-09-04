import 'weapon_def.dart';

export 'weapon_def.dart';

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
  }) : slots = List<WeaponDef>.unmodifiable(slots),
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
  ///
  /// `final` rather than `const`: [AmmoType] carries its own `==` now that a
  /// game can add one, and Dart will not build a constant map on a key that
  /// does. A type this table does not name is carried without a ceiling, which
  /// is the answer a game adding its own ammunition wants by default.
  static final Map<AmmoType, int> capacity = <AmmoType, int>{
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

  /// Which of the owned weapons is in hand, as an index into that list.
  ///
  /// The simulation asks for [current] and gets the weapon itself. The index is
  /// for a game drawing the row of slots along the bottom of the screen, which
  /// has to know which one to light up and cannot get that from the weapon.
  int get currentIndex => _current;

  /// Seconds until the weapon in hand can fire again; zero when it can.
  ///
  /// Firing checks this internally and refuses, so nothing here reads it. It is
  /// for a game that shows the wait — a reload wheel, a barrel that glows down
  /// — where the fraction matters and "can it fire" does not.
  double get cooldownRemaining => _cooldown;

  /// Every kind this arsenal is carrying a counter for, in no order.
  ///
  /// What a HUD asks instead of "every type there is": a game that never
  /// picked up rockets has no rocket counter to draw, and a game that added
  /// its own ammunition gets it here without this package knowing the name.
  Iterable<AmmoType> get carrying => _ammo.keys;

  int ammoOf(AmmoType type) => type == AmmoType.none ? -1 : (_ammo[type] ?? 0);

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
      // **Driven by what the save holds, not by a list of every type there
      // is.** There is no such list once a game can add one — and reading the
      // file's own keys is what lets a game's own ammunition survive a round
      // trip without this package having heard of it.
      _ammo.clear();
      for (final entry in ammo.entries) {
        final name = entry.key;
        final held = entry.value;
        if (name is String && held is num) {
          _ammo[AmmoType(name)] = held.toInt();
        }
      }
    }
  }

  void advanceTime(double dt) {
    if (_cooldown > 0.0) {
      _cooldown = (_cooldown - dt).clamp(0.0, double.infinity);
    }
  }

  /// Whether pulling the trigger right now would fire.
  bool get canFire => _couldFire(isEmpty ? null : current);

  /// The same question of the other trigger. False for a weapon with one.
  ///
  /// A second getter rather than `canFire({bool alternate})`, because turning
  /// a published getter into a method is a change every caller has to make and
  /// this package would rather never ask.
  bool get canFireAlternate => _couldFire(isEmpty ? null : current.alternate);

  /// Whether [weapon] could be fired from this arsenal right now.
  ///
  /// Takes the definition rather than reading [current], so both triggers ask
  /// the same question and the answer cannot drift between them.
  bool _couldFire(WeaponDef? weapon) =>
      weapon != null &&
      _cooldown <= 0.0 &&
      (weapon.ammo == AmmoType.none ||
          ammoOf(weapon.ammo) >= weapon.ammoPerShot);

  /// Whether the trigger being [held] should fire this step.
  ///
  /// An automatic weapon fires while held; the rest need the press edge, which
  /// the caller reports as [pressed].
  bool wantsToFire({required bool held, required bool pressed}) =>
      !isEmpty && (current.automatic ? held : pressed);

  /// The same question of the other trigger.
  ///
  /// False for a weapon with one, so a game may bind the action unconditionally
  /// and a weapon that has no alternate simply never answers it.
  bool wantsToFireAlternate({required bool held, required bool pressed}) {
    final other = isEmpty ? null : current.alternate;
    return other != null && (other.automatic ? held : pressed);
  }

  /// Spends a shot. Returns the definition fired, or null when it could not.
  ///
  /// **What comes back is the alternate's own [WeaponDef] when [alternate] is
  /// asked for**, not the weapon holding it — so everything downstream, from
  /// the shot to the recoil to the sound, reads the numbers of the trigger
  /// that was actually pulled without being told which it was.
  WeaponDef? fire({bool alternate = false}) {
    final weapon = alternate ? (isEmpty ? null : current.alternate) : current;
    if (!_couldFire(weapon) || weapon == null) return null;
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
