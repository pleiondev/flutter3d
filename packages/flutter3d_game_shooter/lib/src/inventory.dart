import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'combat/weapon.dart';

/// Everything the player is carrying.
///
/// Composed of the pieces that already existed rather than replacing them: the
/// [Health] the monsters damage, the [Arsenal] the weapons fire from, and the
/// [KeyRing] the doors read. What this adds is the one place that owns all
/// three, so a pickup has somewhere to give something to and the HUD has one
/// thing to read.
///
/// It is a [KeyHolder] so it can be a collider's `userData` directly: a locked
/// door asks the body in front of it what it carries, and the answer should be
/// the player's actual inventory rather than a copy of part of it.
final class Inventory with KeyHolder {
  /// [arsenal] defaults to an empty one — no weapons and no slots.
  ///
  /// It used to default to this repository's own fists and pistol with forty
  /// bullets, which is a whole game's opening loadout arriving from a package
  /// that should not know the game has fists. A game says what its player
  /// starts with; an inventory built without one starts with nothing, which is
  /// the only answer that is true for every game.
  Inventory({
    Health? health,
    Arsenal? arsenal,
    KeyRing? keys,
    this.maxArmour = 100.0,
  }) : health = health ?? Health(100.0),
       arsenal = arsenal ?? Arsenal(slots: const <WeaponDef>[]),
       keyRing = keys ?? KeyRing();

  final Health health;
  final Arsenal arsenal;
  final KeyRing keyRing;

  final double maxArmour;

  @override
  Set<String> get keys => keyRing.keys;

  /// Seconds left on each power-up that is running, by name.
  Map<String, double> get powers =>
      UnmodifiableMapView<String, double>(_powers);
  final Map<String, double> _powers = <String, double>{};

  bool has(String power) => (_powers[power] ?? 0.0) > 0.0;

  double remainingOf(String power) => _powers[power] ?? 0.0;

  bool get isInvulnerable => has('invulnerability');

  /// Whether the damage multiplier is running.
  ///
  /// The simulation reads the power-up by name where it applies it, so this
  /// spelling of it is called nowhere. It is for a game putting the state on
  /// screen — a tinted overlay, a heartbeat on the audio — which wants the
  /// question asked once rather than the string written in three places.
  bool get isBerserk => has('berserk');

  /// Whether the walls show what is behind them.
  ///
  /// The one power-up the renderer reads rather than the simulation: a game
  /// that carries it turns `RenderSettings.xray` on for the actors' layer,
  /// and the monsters behind the walls are drawn as silhouettes. Named here
  /// beside the other two so the string lives in one place.
  bool get hasSensor => has('sensor');

  /// Starts or refreshes a power-up. Never stacks — see [PowerUpGift].
  void empower(String power, double seconds) {
    if (seconds <= 0.0) return;
    _powers[power] = math.max(_powers[power] ?? 0.0, seconds);
  }

  /// Adds armour up to [maxArmour], and says how much stuck.
  double addArmour(double amount) {
    if (amount <= 0.0) return 0.0;
    final taken = math.min(amount, maxArmour - health.armour);
    if (taken <= 0.0) return 0.0;
    health.armour += taken;
    return taken;
  }

  /// Damage that gets through. Invulnerability eats all of it.
  ///
  /// Here rather than at the call site because there is more than one thing
  /// that hurts the player — a monster's claw, a rocket's blast — and a
  /// power-up honoured by one of them and not the other is a bug report that
  /// takes an afternoon to reproduce.
  bool damage(double amount) {
    if (isInvulnerable) return false;
    return health.damage(amount);
  }

  Map<String, Object?> save() => <String, Object?>{
    'health': health.save(),
    'arsenal': arsenal.save(),
    'keys': keyRing.save(),
    'powers': Map<String, double>.of(_powers),
  };

  void restore(Map<String, Object?> from) {
    final health = from['health'];
    if (health is Map) this.health.restore(health.cast<String, Object?>());
    final arsenal = from['arsenal'];
    if (arsenal is Map) this.arsenal.restore(arsenal.cast<String, Object?>());
    keyRing.restore(from['keys']);
    _powers.clear();
    final powers = from['powers'];
    if (powers is Map) {
      for (final entry in powers.entries) {
        final key = entry.key;
        final seconds = entry.value;
        if (key is String && seconds is num) _powers[key] = seconds.toDouble();
      }
    }
    expired.clear();
  }

  void step(double dt) {
    if (_powers.isEmpty) return;
    // Over a copy of the keys: expiring one removes it.
    for (final power in _powers.keys.toList(growable: false)) {
      final left = _powers[power]! - dt;
      if (left <= 0.0) {
        _powers.remove(power);
        expired.add(power);
      } else {
        _powers[power] = left;
      }
    }
  }

  /// Power-ups that ran out this step, for anything that wants to say so.
  /// Cleared by the owner once read.
  final List<String> expired = <String>[];
}
