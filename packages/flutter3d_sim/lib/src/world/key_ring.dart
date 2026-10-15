import 'dart:collection';

/// Something that might be carrying keys.
///
/// A mixin on whatever a collider's `userData` happens to be, so a door can ask
/// the body in front of it what it holds without the physics knowing that keys
/// exist and without a lookup table from colliders to inventories.
///
/// **Mixed in, never implemented**: a base mixin class, so a member a minor
/// adds arrives with a body.
abstract base mixin class KeyHolder {
  /// The keys held, by colour; none by default.
  Set<String> get keys => const <String>{};
}

/// The keys one body is carrying, by colour.
///
/// A set of strings rather than an enum: the colours are level data, a level
/// pack should be able to invent a fourth one, and the validator already
/// refuses a door demanding a key no entity in the level provides.
///
/// This is the smallest thing that makes locked doors work, and the inventory
/// of stage 9 will take it over rather than replace it — keys behave unlike
/// everything else in an inventory, being permanent, weightless and countless.
///
/// A game keeps one per body, made with `KeyRing()`.
final class KeyRing with KeyHolder {
  final Set<String> _held = <String>{};

  @override
  Set<String> get keys => UnmodifiableSetView<String>(_held);

  /// Adds one, and says whether it was new.
  bool add(String key) => _held.add(key);

  bool has(String key) => _held.contains(key);

  void clear() => _held.clear();

  List<String> save() => _held.toList()..sort();

  void restore(Object? from) {
    _held.clear();
    if (from is! List) return;
    for (final key in from) {
      if (key is String) _held.add(key);
    }
  }
}
