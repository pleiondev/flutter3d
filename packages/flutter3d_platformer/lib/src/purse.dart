import 'dart:collection';

import 'package:flutter3d_game/flutter3d_game.dart';

/// What somebody has picked up, counted by name.
///
/// Not an inventory. `Inventory` in `flutter3d_shooter` holds health, armour,
/// ammunition by type and a set of weapons, and every one of those is a
/// shooter's idea; a platformer counts coins and stars and does not care what
/// they are for. The two were the same class once, which is how the engine came
/// to have ammunition in it.
final class Purse {
  final Map<String, int> _counts = <String, int>{};

  /// Everything held, for a HUD that wants to list it.
  UnmodifiableMapView<String, int> get counts =>
      UnmodifiableMapView<String, int>(_counts);

  int operator [](String what) => _counts[what] ?? 0;

  /// Adds [howMany] of [what] and answers whether anything was added.
  ///
  /// The boolean is not decoration: a collectible that cannot be taken must
  /// stay where it is, the same rule a medkit at full health depends on. Here
  /// nothing is ever refused, and the answer is still reported rather than
  /// assumed, so the day a cap arrives the callers already do the right thing.
  bool add(String what, [int howMany = 1]) {
    if (howMany <= 0) return false;
    _counts[what] = this[what] + howMany;
    return true;
  }

  void clear() => _counts.clear();

  Map<String, Object?> save() => <String, Object?>{
        for (final entry in _counts.entries) entry.key: entry.value,
      };

  void restore(Map<String, Object?> from) {
    _counts.clear();
    for (final entry in from.entries) {
      final value = entry.value;
      if (value is num) _counts[entry.key] = value.toInt();
    }
  }
}

/// Someone a collectible can be given to.
///
/// The same shape as `Damageable` and `Collector`: a collider says *who* it is,
/// and whether that someone gathers things is a question they answer.
abstract interface class Gatherer {
  Purse get purse;
}

/// Someone a key can be given to.
///
/// Separate from [Gatherer] because a key is not a count: you hold it or you do
/// not, for ever, and a `Purse` that could answer "how many blue keys" would be
/// answering a question no door asks. `KeyRing` in the engine is that set, and
/// this is how a pickup reaches one without knowing whose it is.
abstract interface class KeyTaker {
  KeyRing get keyRing;
}
