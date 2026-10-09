/// Reading a material's JSON: the exception it throws, and the reader each
/// property group shares.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException;

/// A physical material's document — a `PhysicalMaterial`'s JSON, a data
/// plugin's `physicalMaterials` entry — that cannot be read: a number that is not
/// one, a group with no source, a phase or an id that is not a word.
final class MaterialFormatException extends Flutter3dFormatException {
  const MaterialFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'MaterialFormatException: $message';
}

/// Reads one property group's JSON: its numbers by key, its source, and the
/// keys it did not ask for. Not exported.
final class GroupReader {
  GroupReader(this._json, this._group, this._known);

  final Map<String, Object?> _json;
  final String _group;
  final Set<String> _known;

  /// The number at [key], or null when the key is absent. Throws a
  /// [MaterialFormatException] for anything else that is not a finite
  /// number.
  double? number(String key) => switch (_json[key]) {
    null => null,
    final num value when value.isFinite => value.toDouble(),
    final other => throw MaterialFormatException(
      '"$_group.$key" must be a finite number, not $other',
    ),
  };

  /// The [count] numbers at [key], or null when the key is absent.
  List<double>? numbers(String key, {required int count}) =>
      switch (_json[key]) {
        null => null,
        final List<Object?> list
            when list.length == count &&
                list.every((Object? e) => e is num && e.isFinite) =>
          List<double>.unmodifiable(
            list.map((Object? e) => (e! as num).toDouble()),
          ),
        final other => throw MaterialFormatException(
          '"$_group.$key" must be $count finite numbers, not $other',
        ),
      };

  /// The group's source. Throws a [MaterialFormatException] when there is
  /// none: every group says where its numbers come from.
  String get source => switch (_json['source']) {
    final String said when said.trim().isNotEmpty => said,
    _ => throw MaterialFormatException(
      '"$_group" has no "source": every group of a material names where its '
      'numbers come from',
    ),
  };

  /// The keys this group's reader did not ask for, as they were.
  Map<String, Object?> get unknown => <String, Object?>{
    for (final MapEntry(:key, :value) in _json.entries)
      if (!_known.contains(key) && key != 'source') key: value,
  };
}
