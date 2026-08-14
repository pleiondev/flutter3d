import 'dart:collection';
import 'dart:math' as math;

import '../actors/health.dart';
import '../combat/weapon.dart';
import 'key_ring.dart';

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
  Inventory({
    Health? health,
    Arsenal? arsenal,
    KeyRing? keys,
    this.maxArmour = 100.0,
  })  : health = health ?? Health(100.0),
        arsenal = arsenal ?? Arsenal(),
        keyRing = keys ?? KeyRing();

  final Health health;
  final Arsenal arsenal;
  final KeyRing keyRing;

  final double maxArmour;

  @override
  Set<String> get keys => keyRing.keys;

  /// Seconds left on each power-up that is running, by name.
  Map<String, double> get powers => UnmodifiableMapView<String, double>(_powers);
  final Map<String, double> _powers = <String, double>{};

  bool has(String power) => (_powers[power] ?? 0.0) > 0.0;

  double remainingOf(String power) => _powers[power] ?? 0.0;

  bool get isInvulnerable => has('invulnerability');
  bool get isBerserk => has('berserk');

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
