import 'package:flutter3d_sim/flutter3d_sim.dart';

/// Where two runs claiming to be the same actually differ, once
/// [DigestTrace] has already said they do.
///
/// [path] reads as the JSON nesting a genre's own `Snapshot.toJson()`
/// happens to use — `entities.7.health` for an `EcsWorld`-backed save, say
/// — without this class knowing what an entity is: it only ever compared
/// two JSON trees and wrote down where they first stopped matching.
final class SnapshotDivergence {
  const SnapshotDivergence({
    required this.step,
    required this.path,
    required this.expected,
    required this.found,
  });

  /// The checkpoint step the two sides last agreed was fine — the same one
  /// [DigestTrace.divergenceFromHex] already names.
  final int step;

  /// A dotted path into the saved JSON — `.` between map keys, `[i]` into a
  /// list — leading to the first leaf value that differed. `<length>` when
  /// the two top-level values were lists of different lengths, and the
  /// empty string when they were different kinds of thing entirely (a map
  /// on one side, a list on the other).
  final String path;

  final Object? expected;
  final Object? found;

  @override
  String toString() =>
      'step $step at `$path`: expected $expected, found $found';
}

/// `net-04`'s whole shape: [DigestTrace.divergenceFromHex] already finds
/// the step cheaply, from nothing but the eight-digit hex numbers a
/// `.f3drun` already carries; this asks for the one thing a digest cannot
/// answer — *what*, at that step, differed — and only there, rather than at
/// every checkpoint either side ever recorded.
///
/// [snapshotAtA] and [snapshotAtB] answer with the full saved state at a
/// step, once a caller has replayed that side's own [Demo] to reach it —
/// neither is called here except at the one step [a] and [b] disagreed at.
/// This function does not replay anything itself, the same reason
/// `flutter3d_testing`'s `replayGolden` does not: only a genre's own
/// package knows how to step its own simulation, and teaching this one
/// package would mean teaching it every genre in turn.
///
/// Null if [a] and [b] never disagreed — see [DigestTrace.divergenceFromHex]
/// for what "never" covers (one ran short, or every checkpoint matched).
SnapshotDivergence? diffRuns({
  required DigestTrace a,
  required DigestTrace b,
  required Map<String, Object?> Function(int step) snapshotAtA,
  required Map<String, Object?> Function(int step) snapshotAtB,
}) {
  final digestDivergence = a.divergenceFromHex(b.hexDigests);
  if (digestDivergence == null) return null;
  final step = digestDivergence.step;
  final path = firstDifferingPath(snapshotAtA(step), snapshotAtB(step));
  if (path == null) {
    // The digests disagreed but the two full snapshots read back the same —
    // only reachable if a caller's `snapshotAtA`/`snapshotAtB` do not
    // actually reproduce the state each side's own checkpoint was taken
    // from. Named rather than silently returning null, which would read as
    // "no divergence" to a caller already told there was one.
    throw StateError(
      'the digests at step $step disagreed, but the full snapshots handed '
      'back for it do not — snapshotAtA/snapshotAtB must reach the exact '
      'state each side checkpointed there',
    );
  }
  return SnapshotDivergence(
    step: step,
    path: path.path,
    expected: path.a,
    found: path.b,
  );
}

/// A path into JSON-shaped values ([Map], [List], or a primitive) leading
/// to the first leaf where [a] and [b] differ, or null if they are equal —
/// exported so a caller that already has two full snapshots and already
/// knows which step to compare (a golden test disagreeing on one recorded
/// step, say) can ask this question directly, without going through
/// [diffRuns]'s digest-narrowing at all.
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
