/// A path into JSON-shaped values ([Map], [List], or a primitive) leading
/// to the first leaf where [a] and [b] differ, or null if they are equal.
///
/// Here rather than in `flutter3d_net`, where it was written for
/// `diffRuns`: the timeline asks the same question after a code reload —
/// where does the run the new code makes first part from the one the old
/// code made — and the timeline does not depend on networking. `flutter3d_net`
/// exports it from here, so nothing that reached it there has moved.
DifferingPath? firstDifferingPath(Object? a, Object? b, {String prefix = ''}) {
  if (a is Map && b is Map) {
    final keys = <Object?>{...a.keys, ...b.keys}.toList()
      ..sort((x, y) => x.toString().compareTo(y.toString()));
    for (final key in keys) {
      final childPrefix = prefix.isEmpty ? '$key' : '$prefix.$key';
      final result = firstDifferingPath(a[key], b[key], prefix: childPrefix);
      if (result != null) return result;
    }
    return null;
  }
  if (a is List && b is List) {
    final shorter = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < shorter; i++) {
      final result = firstDifferingPath(a[i], b[i], prefix: '$prefix[$i]');
      if (result != null) return result;
    }
    if (a.length != b.length) {
      return DifferingPath(
        path: prefix.isEmpty ? '<length>' : '$prefix.<length>',
        a: a.length,
        b: b.length,
      );
    }
    return null;
  }
  if (a != b) return DifferingPath(path: prefix, a: a, b: b);
  return null;
}

/// Where two JSON-shaped values first differ, and what each holds there:
/// what [firstDifferingPath] answers.
final class DifferingPath {
  const DifferingPath({required this.path, required this.a, required this.b});

  /// The address of the first leaf that differs, keys joined by `.` and list
  /// indices in brackets (`entities.7.health`, `shots[1]`); a list of
  /// different lengths ends in `<length>`, and the values themselves differing
  /// at the top is the empty string.
  final String path;

  /// What the first value holds at [path]: a leaf, a list's length, or a
  /// whole map or list present on one side only.
  final Object? a;

  /// What the second value holds at [path], as [a].
  final Object? b;

  /// Two answers are the same when their paths are and the values under
  /// them compare equal leaf by leaf, so a map or list answered twice is
  /// the same answer.
  @override
  bool operator ==(Object other) =>
      other is DifferingPath &&
      other.path == path &&
      firstDifferingPath(other.a, a) == null &&
      firstDifferingPath(other.b, b) == null;

  @override
  int get hashCode => Object.hash(path, _leafHash(a), _leafHash(b));

  @override
  String toString() => 'DifferingPath($path: $a, $b)';

  /// A collection hashes as its length: equal collections are equal leaf by
  /// leaf, which a hash of the instance would not respect.
  static int _leafHash(Object? value) => switch (value) {
    final Map<Object?, Object?> map => map.length,
    final List<Object?> list => list.length,
    _ => value.hashCode,
  };
}
