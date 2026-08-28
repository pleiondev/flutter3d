import 'dart:collection';

/// Things counted by name, and kept.
///
/// **Extracted on the second consumer, which is the rule and took a while.**
/// This was the platformer's `Purse` — coins and stars — and an audit left it
/// there on the grounds that the shooter's `Inventory` is a different idea
/// entirely, which it is: health, armour, ammunition by type and a set of
/// weapons. What arrived second was not an inventory but a *tally*: how many
/// monsters a level had and how many are dead, how many secrets and how many
/// found. Same machinery, different word.
///
/// Deliberately thin. It counts, it says what it holds, and it survives a save;
/// anything about what the names mean belongs to whoever chose them.
base class Tally {
  Tally();

  final Map<String, int> _counts = <String, int>{};

  /// Everything held, for a readout that wants to list it.
  UnmodifiableMapView<String, int> get counts =>
      UnmodifiableMapView<String, int>(_counts);

  int operator [](String what) => _counts[what] ?? 0;

  bool get isEmpty => _counts.isEmpty;

  /// Adds [howMany] of [what] and answers whether anything was added.
  ///
  /// The boolean is not decoration: a collectible that cannot be taken must
  /// stay where it is, the same rule a medkit at full health depends on.
  /// Nothing is refused here, and the answer is still reported rather than
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
