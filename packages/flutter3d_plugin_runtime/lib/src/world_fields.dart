import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// One of the world's fields, as a plugin loaded at run time sees it: heat
/// per cell, water depth per column, wind per tile.
///
/// **A fixed set, named by the application.** A Wasm module or a script
/// reaches the world only through the fields the application put in its
/// [WorldFields], each a row of numbers it may read, and write when its
/// declaration says so. Nothing else of the world is reachable from inside
/// the sandbox, which is what lets an application load a module it did not
/// compile.
///
/// `base`, so a member added later arrives with a default: an application
/// extends it over whatever its world keeps the numbers in.
abstract base class WorldField {
  const WorldField();

  /// The name a plugin's declaration uses: `heat`, `water`, `wind.x`.
  String get name;

  /// How many values the field holds.
  int get length;

  /// The value at [index], `0 <= index < length`.
  double operator [](int index);

  /// Writes the value at [index].
  void operator []=(int index, double value);
}

/// A [WorldField] over a list the application owns.
final class ListWorldField extends WorldField {
  ListWorldField(this.name, this.values);

  @override
  final String name;

  /// The numbers themselves, shared with whoever made the field.
  final Float64List values;

  @override
  int get length => values.length;

  @override
  double operator [](int index) => values[index];

  @override
  void operator []=(int index, double value) => values[index] = value;
}

/// The fields a run-time plugin may reach, by name.
///
/// **A registry the application hands the engine**, like `EntityKinds`: the
/// application adds its world's fields, and a plugin that owns a field of
/// its own — an element that keeps a heat grid — adds that one through its
/// host, so it goes when the plugin is switched off. A module or a script
/// then names fields, and is refused at install when it names one that is
/// not here.
///
/// ```dart
/// final fields = WorldFields([ListWorldField('heat', heat)]);
/// EngineLoop(input: input, registries: [fields], plugins: [dataPlugin]);
/// ```
final class WorldFields extends PluginRegistry {
  /// A registry holding [fields], added by the application.
  WorldFields([Iterable<WorldField> fields = const <WorldField>[]])
    : _store = _FieldStore(),
      _scope = null {
    fields.forEach(add);
  }

  WorldFields._scoped(this._store, this._scope);

  final _FieldStore _store;
  final PluginScope? _scope;

  /// Adds [field]. Throws an [ArgumentError] naming both owners when a field
  /// of that name is already here.
  Registration add(WorldField field) {
    final scope = _scope;
    final owner = scope == null
        ? 'the application'
        : 'plugin "${scope.manifest.id}"';
    final existing = _store.fields[field.name];
    if (existing != null) {
      throw ArgumentError.value(
        field.name,
        'field',
        'a world field of this name was added by ${existing.$2}, and again '
            'by $owner; a field name is unique in one engine',
      );
    }
    _store.fields[field.name] = (field, owner);
    final registration = Registration(() {
      if (identical(_store.fields[field.name]?.$1, field)) {
        _store.fields.remove(field.name);
      }
    });
    _scope?.track(registration);
    return registration;
  }

  /// The field named [name], or null.
  WorldField? operator [](String name) => _store.fields[name]?.$1;

  /// Every field's name, in the order they were added.
  List<String> get names => List<String>.unmodifiable(_store.fields.keys);

  @override
  WorldFields forPlugin(PluginScope scope) =>
      WorldFields._scoped(_store, scope);
}

// One table shared by the root and every plugin's view of it. A map in
// insertion order: names are listed in the order they arrived, never by hash.
final class _FieldStore {
  final Map<String, (WorldField, String)> fields =
      <String, (WorldField, String)>{};
}

/// The numbers a sandboxed plugin trades with the world, at a precision the
/// field declares: `round(value × 2^fractionBits)` in a 32-bit integer.
///
/// [Fixed16] is the 16-bit case every field used before fields declared
/// their own. Fewer fraction bits widen the range — 8 bits hold ±8 388 608
/// with a step of 1/256, enough for a world position — at the same
/// exactness: a multiply by a power of two and a `round`.
abstract final class FixedPoint {
  static const int _max = 0x7FFFFFFF;
  static const int _min = -0x80000000;

  /// [value] with [fractionBits] fraction bits, rounded to the nearest step
  /// and clamped to the 32-bit range. Not-a-number reads as nought.
  static int fromDouble(double value, {required int fractionBits}) {
    if (value.isNaN) return 0;
    final scaled = value * (1 << fractionBits);
    if (scaled >= _max) return _max;
    if (scaled <= _min) return _min;
    return scaled.round();
  }

  /// [fixed], with [fractionBits] fraction bits, as a double. Exact.
  static double toDouble(int fixed, {required int fractionBits}) =>
      fixed / (1 << fractionBits);
}

/// The numbers a sandboxed plugin trades with the world: Q16.16 fixed point
/// in a 32-bit integer.
///
/// **Integers, so every platform gives one answer.** A Wasm module under ABI
/// 1 computes in 32-bit integers only, and the world's doubles cross into it
/// here. Multiplying by a power of two is exact and `round` is exact, so a
/// value converts to the same integer on the VM, in a browser and on a
/// server; what the module does with it is integer arithmetic, which the
/// interpreter carries out the same way on all three. The range is ±32768
/// with a step of 1/65536 — a temperature, a depth, a speed.
abstract final class Fixed16 {
  /// The integer that stands for 1.0.
  static const int one = 65536;

  static const int _max = 0x7FFFFFFF;
  static const int _min = -0x80000000;

  /// [value] in Q16.16, rounded to the nearest step and clamped to the 32-bit
  /// range. Not-a-number reads as nought.
  static int fromDouble(double value) {
    if (value.isNaN) return 0;
    final scaled = value * one;
    if (scaled >= _max) return _max;
    if (scaled <= _min) return _min;
    return scaled.round();
  }

  /// [fixed], a Q16.16 integer, as a double. Exact: every 32-bit integer
  /// divided by a power of two is a double.
  static double toDouble(int fixed) => fixed / one;
}
