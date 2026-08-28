import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'gizmos.dart';

/// The word a palette uses for a light, which is not an entity type and not a
/// material.
const String kLight = 'light';

/// One row of the palette.
final class Placeable {
  const Placeable({
    required this.kind,
    required this.what,
    required this.count,
    required this.tint,
  });

  /// Which of the three lists a row adds to.
  final Piece kind;

  /// A material for a brush, an entity type for an entity, [kLight] for a
  /// light.
  final String what;

  /// How many of these the level has, which is worth showing: a level with no
  /// exit and a level with three are both worth noticing before playing it.
  final int count;

  final Vector3 tint;

  /// What a row says. A brush row says its material and nothing else, because
  /// "brush · wall" is two words for one thing and the second is the one that
  /// means something.
  String get label => what;
}

/// What can be put into a level, in the order a palette lists it.
///
/// **Built from the document, which is the only honest place to get it.** This
/// application has no vocabulary — it cannot know that a game has monsters, or
/// that this one calls them `monster` — so the list of what can be placed is
/// the list of what is already here. A level with lifts offers lifts; a racing
/// game's level would offer whatever a racing game's levels contain, without a
/// line of code being written about racing.
///
/// **A brush is not one row but one per material**, and the question that
/// caused that is worth keeping: *"is brush a wall?"* It is not — a brush is a
/// box, and what makes it a wall rather than a floor is the material it names.
/// A palette offering "brush" is asking somebody to place a thing and then find
/// out what it turned out to be; one offering `wall`, `floor`, `ceiling` and
/// `iron` is offering what the level is actually made of, in the colours it is
/// made of them in.
///
/// The light is the other exception. Both it and the brush are things the
/// *engine* defines, which is what lets an editor invent one without guessing
/// at anybody's vocabulary.
/// [declared] is everything a game or a template says it has, whether this
/// level contains one or not. **Without it a palette can only offer what is
/// already there**, which is nothing at all in a level nobody has built yet —
/// and it is why a game that describes a torch in its own `editor.json` could
/// not place one in a level with no torches in it.
List<Placeable> paletteOf(
  Level level, {
  Iterable<String> declared = const <String>[],
}) {
  final byMaterial = <String, int>{};
  for (final brush in level.brushes) {
    byMaterial[brush.material] = (byMaterial[brush.material] ?? 0) + 1;
  }
  // Every material the document declares, used or not: an unused one is
  // usually one somebody wrote down in order to build with it.
  for (final name in level.materials.keys) {
    byMaterial.putIfAbsent(name, () => 0);
  }
  if (byMaterial.isEmpty) byMaterial['default'] = 0;

  final counts = <String, int>{};
  for (final entity in level.entities) {
    counts[entity.type] = (counts[entity.type] ?? 0) + 1;
  }
  for (final type in declared) {
    counts.putIfAbsent(type, () => 0);
  }

  return <Placeable>[
    for (final name in byMaterial.keys.toList()..sort())
      Placeable(
        kind: Piece.brush,
        what: name,
        count: byMaterial[name]!,
        // The colour it is actually painted, which says more about what a row
        // will put down than any word does.
        tint: atLeast(
          level.materials[name]?.baseColor.xyz ?? Vector3.all(0.7),
          0.25,
        ),
      ),
    Placeable(
      kind: Piece.light,
      what: kLight,
      count: level.lights.length,
      tint: Vector3(1.0, 0.9, 0.5),
    ),
    for (final type in counts.keys.toList()..sort())
      Placeable(
        kind: Piece.entity,
        what: type,
        count: counts[type]!,
        tint: tintFor(type),
      ),
  ];
}
