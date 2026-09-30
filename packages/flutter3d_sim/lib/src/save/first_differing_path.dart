/// A path into JSON-shaped values ([Map], [List], or a primitive) leading
/// to the first leaf where [a] and [b] differ, or null if they are equal.
///
/// Here rather than in `flutter3d_net`, where it was written for
/// `diffRuns`: the timeline asks the same question after a code reload —
/// where does the run the new code makes first part from the one the old
/// code made — and the timeline does not depend on networking. `flutter3d_net`
/// exports it from here, so nothing that reached it there has moved.
({String path, Object? a, Object? b})? firstDifferingPath(
  Object? a,
  Object? b, [
  String prefix = '',
]) {
  if (a is Map && b is Map) {
    final keys = <Object?>{...a.keys, ...b.keys}.toList()
      ..sort((x, y) => x.toString().compareTo(y.toString()));
    for (final key in keys) {
      final childPrefix = prefix.isEmpty ? '$key' : '$prefix.$key';
      final result = firstDifferingPath(a[key], b[key], childPrefix);
      if (result != null) return result;
    }
    return null;
  }
  if (a is List && b is List) {
    final shorter = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < shorter; i++) {
      final result = firstDifferingPath(a[i], b[i], '$prefix[$i]');
      if (result != null) return result;
    }
    if (a.length != b.length) {
      return (
        path: prefix.isEmpty ? '<length>' : '$prefix.<length>',
        a: a.length,
        b: b.length,
      );
    }
    return null;
  }
  if (a != b) return (path: prefix, a: a, b: b);
  return null;
}
