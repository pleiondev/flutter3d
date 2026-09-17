/// Two readings of one file, and everything they disagree about.
///
/// Pure: no Godot, no file system, no `ModelDocument`. That is what lets
/// `test/compare_test.dart` break each rule on purpose and watch this notice,
/// which is the only way anybody knows the rules are load-bearing.
library;

import 'reading.dart';

/// How far a bound may sit *inside* ours before it counts as geometry lost.
///
/// A float32 round-down measured 1.9e-9 across the seven committed fixtures;
/// this is three decades of room above that and still far below anything a
/// real fault moves.
const double containmentSlack = 1e-6;

/// How far an unskinned surface's bounds may differ at all. The measured
/// worst is 2.4e-7, on `case1.glb`, whose positions are quantised by the
/// compressing writer.
const double boundsTolerance = 1e-5;

/// What [ours] and [theirs] disagree about, as sentences in
/// `compareModelDocuments`' own "N in, M out" shape. Empty means they agree.
List<String> compareReadings(
  String name,
  FileReading ours,
  FileReading theirs,
) {
  if (theirs.error != null) return <String>['$name: ${theirs.error}'];
  if (ours.error != null) return <String>['$name: ${ours.error}'];

  if (ours.surfaces.length != theirs.surfaces.length) {
    // Nothing below can be said about readings that disagree about how many
    // surfaces there are — the same reason `compareModelDocuments` stops at
    // its own count checks before comparing anything by index.
    final said =
        '$name: surfaces: ${ours.surfaces.length} in the document, '
        '${theirs.surfaces.length} in Godot';
    return <String>[said];
  }

  final problems = <String>[];
  if (ours.triangles != theirs.triangles) {
    problems.add(
      '$name: triangles: ${ours.triangles} in the document, '
      '${theirs.triangles} in Godot',
    );
  }

  if (!_same(ours.materials, theirs.materials)) {
    problems.add(
      '$name: materials: ${_listed(ours.materials)} in the document, '
      '${_listed(theirs.materials)} in Godot',
    );
    // A material name is half the pairing key, so a disagreement about them
    // makes every surface comparison below noise rather than evidence.
    return problems;
  }

  final ourGroups = _group(ours.surfaces);
  final theirGroups = _group(theirs.surfaces);
  final keys = <String>{...ourGroups.keys, ...theirGroups.keys}.toList()
    ..sort();
  for (final key in keys) {
    final ourGroup = ourGroups[key] ?? const <SurfaceReading>[];
    final theirGroup = theirGroups[key] ?? const <SurfaceReading>[];
    if (ourGroup.length != theirGroup.length) {
      problems.add(
        '$name: $key: ${ourGroup.length} in the document, '
        '${theirGroup.length} in Godot',
      );
      continue;
    }
    for (var i = 0; i < ourGroup.length; i++) {
      problems.addAll(_compareBounds(name, key, ourGroup[i], theirGroup[i]));
    }
  }
  return problems;
}

/// The two boxes, which is the whole of the geometry these readings can be
/// compared on: Godot's must contain ours, and on an unskinned surface it
/// must be the same box.
List<String> _compareBounds(
  String name,
  String key,
  SurfaceReading ours,
  SurfaceReading theirs,
) {
  for (var axis = 0; axis < 3; axis++) {
    final cut =
        (theirs.min[axis] - ours.min[axis]) > containmentSlack ||
        (ours.max[axis] - theirs.max[axis]) > containmentSlack;
    if (cut) {
      final said =
          "$name: $key: Godot's bounds cut into ours on axis $axis — "
          '$ours in the document, $theirs in Godot';
      return <String>[said];
    }
  }
  if (ours.skinned) return const <String>[];
  for (var axis = 0; axis < 3; axis++) {
    final apart = _bigger(
      (theirs.min[axis] - ours.min[axis]).abs(),
      (theirs.max[axis] - ours.max[axis]).abs(),
    );
    if (apart > boundsTolerance) {
      final said =
          '$name: $key: bounds differ by ${apart.toStringAsExponential(2)} on '
          'axis $axis — $ours in the document, $theirs in Godot';
      return <String>[said];
    }
  }
  return const <String>[];
}

/// Surfaces gathered by `(material, triangles)` and ordered within a group by
/// where they sit, which is a canonical order both sides agree on whenever
/// they agree about the boxes at all.
///
/// **Not by node name and not by order**, and both were measured: Godot
/// renames `Foot.L` to `Foot_L2` — a dot is not legal in a node name, and the
/// suffix keeps it off a bone of the same name — and it emits `case4.glb`'s
/// nineteen surfaces in a different order from the file's. Pairing by index
/// reported fifteen of those nineteen as changed when nothing had.
Map<String, List<SurfaceReading>> _group(List<SurfaceReading> surfaces) {
  final groups = <String, List<SurfaceReading>>{};
  for (final surface in surfaces) {
    groups.putIfAbsent(surface.group, () => <SurfaceReading>[]).add(surface);
  }
  for (final group in groups.values) {
    group.sort((a, b) {
      for (var axis = 0; axis < 3; axis++) {
        final order = a.min[axis].compareTo(b.min[axis]);
        if (order != 0) return order;
      }
      for (var axis = 0; axis < 3; axis++) {
        final order = a.max[axis].compareTo(b.max[axis]);
        if (order != 0) return order;
      }
      return 0;
    });
  }
  return groups;
}

double _bigger(double a, double b) => a > b ? a : b;

String _listed(Set<String> names) =>
    names.isEmpty ? 'none' : (names.toList()..sort()).join(', ');

bool _same(Set<String> a, Set<String> b) =>
    a.length == b.length && a.every(b.contains);
