import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// `edu-01`'s own arithmetic, kept out of any widget for the same reason
/// `bindingsInLevel` and `HeatmapLayout` (`ai-02`) were: a merge into a JSON
/// map or a reorder of a name list is cheaper to prove directly than through
/// a `WidgetTester` drag, which only shows that painting and hit-testing
/// agree with each other, not that either produces the right document.
///
/// Nothing here is a new [EditorCommand] — every one of `edu-00`'s new
/// entity types (`edu_sequence`, `edu_step`, `edu_annotation`,
/// `edu_clip_plane`) is an ordinary [EntityDef] with a flat property bag, so
/// `Place` puts one down and `SetField` writes into it exactly as it already
/// does for a `door` or a `monster`. This file only computes the *values*
/// those two existing commands are handed — a step panel's "drag this part
/// two centimetres" or "move this step up the list" turned into the map or
/// list `SetField` should carry.

/// The index of the entity named [name] in [level], or null.
///
/// **Why this exists at all.** `Level.named` already returns the entity
/// itself; a step panel or an `EditorCommand` caller needs the index instead
/// — `Editing.select`/the `select` MCP tool take a `(kind, index)` pair, not
/// a name, because a level keeps three plain lists and nothing in them is
/// addressed by name except through a linear scan like this one.
int? indexOfNamed(Level level, String name) {
  for (var i = 0; i < level.entities.length; i++) {
    if (level.entities[i].name == name) return i;
  }
  return null;
}

/// The `edu_step` entities [sequenceName] names, in the order it names them.
///
/// A name in `steps` that no entity carries is skipped rather than thrown
/// for — the same choice `Level.named` already makes for a dangling
/// reference elsewhere in the format: a step panel reading a document with a
/// typo in it should show the steps that do exist, not refuse all of them.
List<EntityDef> orderedSteps(Level level, String sequenceName) {
  final sequence = level.named(sequenceName);
  if (sequence == null || sequence.type != 'edu_sequence') {
    return const <EntityDef>[];
  }
  final names = sequence.properties['steps'];
  if (names is! List) return const <EntityDef>[];
  return <EntityDef>[
    for (final raw in names)
      if (raw is String)
        if (level.named(raw) case final EntityDef step) step,
  ];
}

/// [step]'s own `offsets` map, with [nodePath] set to [delta] — the value a
/// caller hands `SetField('offsets', ...)` after a drag on a named node.
///
/// Every other entry survives untouched: a drag on one part of a five-part
/// teardown must not forget where the other four already stand. Metres, not
/// pixels — the caller (a viewport that knows its own scale) converts a drag
/// distance to a world delta before this ever runs; this function only
/// merges, and merges the same way regardless of what produced the number.
Map<String, Object?> mergedOffsets(EntityDef step, String nodePath, Vector3 delta) {
  final existing = step.properties['offsets'];
  final offsets = <String, Object?>{
    if (existing is Map)
      for (final entry in existing.entries)
        if (entry.key is String) entry.key as String: entry.value,
  };
  offsets[nodePath] = <double>[delta.x, delta.y, delta.z];
  return offsets;
}

/// [steps] with the name at [from] moved to sit at [to] — the value a
/// caller hands `SetField('steps', ...)` on the `edu_sequence` after
/// dragging a row in a step list up or down.
///
/// Out-of-range indices return [steps] unchanged rather than throwing: a
/// drag that overshoots past the end of the list is a drag to the end of
/// the list, and refusing it outright would be a panel that sometimes drops
/// the row a person was moving.
List<String> movedStep(List<String> steps, int from, int to) {
  if (from < 0 || from >= steps.length) return steps;
  final clampedTo = to.clamp(0, steps.length - 1);
  final result = List<String>.of(steps);
  final moving = result.removeAt(from);
  result.insert(clampedTo, moving);
  return result;
}

/// A name for a new `edu_step`/`edu_annotation`/`edu_clip_plane` that no
/// entity in [level] already carries — `prefix-1`, `prefix-2`, ... — because
/// [Editing.place] copies the last entity of a type, name included, and two
/// steps sharing one name is two entries in `edu_sequence.steps` that
/// resolve to the same step.
String freshName(Level level, String prefix) {
  final taken = <String>{
    for (final entity in level.entities)
      if (entity.name != null) entity.name!,
  };
  var n = 1;
  while (taken.contains('$prefix-$n')) {
    n++;
  }
  return '$prefix-$n';
}
