import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'looks.dart';

/// What a level is made of, from an editor's side.
enum Piece {
  /// Geometry. The only one of the three that is drawn by the game.
  brush,

  /// A light: a lamp, the sun, a torch's flame.
  light,

  /// Everything else the document names — a monster, a lift, a door, a
  /// pickup, the point the player starts at. What any of those *are* belongs
  /// to the game; where they are does not.
  entity,
}

/// Something in the document that can be pointed at and moved.
///
/// **Two of the three have no geometry at all.** A brush is a box and can be
/// clicked on because it is on the screen; a monster is a coordinate and a word,
/// and a light is a coordinate and a colour. An editor that could only touch
/// what the renderer happens to draw would be an editor that cannot place a
/// monster — so the ones with nothing to show are given a box of their own, and
/// that box is both what a click hits and what gets drawn.
final class Handle {
  const Handle({
    required this.kind,
    required this.index,
    required this.centre,
    required this.size,
    required this.tint,
    this.volume = false,
  });

  final Piece kind;

  /// Which one, in the document's own list for [kind].
  final int index;

  final Vector3 centre;
  final Vector3 size;

  /// What to draw it in. A light wears its own colour, which is the fastest way
  /// to see that a room is lit orange because somebody made it orange.
  final Vector3 tint;

  /// Whether the *document* gave this a size of its own.
  ///
  /// **The editor's way of saying "this is a region, not a thing"** without
  /// knowing what a trigger is. Something the author sized is something whose
  /// extent is the point — a trigger volume, a lift's platform — and a solid
  /// box drawn over one hides whatever it contains and lies flat against the
  /// wall it was placed on. Those are drawn as a cage of edges instead.
  final bool volume;

  Vector3 get min => centre - size / 2.0;
  Vector3 get max => centre + size / 2.0;
}

/// How big the mark for something with no geometry is, in metres.
///
/// Half a metre: large enough to hit with a mouse from across a room, small
/// enough not to hide the thing it stands for. A monster is about this wide
/// anyway, which makes the mark read as the monster rather than as a label.
const double kGizmoSize = 0.5;

/// Every handle in [level], brushes included.
///
/// One list rather than three, because a click is one question — "what is under
/// this pixel" — and answering it from three lists means three sets of the same
/// arithmetic and three chances to disagree about which is nearest.
List<Handle> handlesOf(Level level, {Looks looks = Looks.none}) => <Handle>[
      for (var i = 0; i < level.brushes.length; i++)
        Handle(
          kind: Piece.brush,
          index: i,
          centre: level.brushes[i].centre,
          size: level.brushes[i].size,
          tint: Vector3(1.0, 0.45, 0.05),
        ),
      for (var i = 0; i < level.lights.length; i++)
        Handle(
          kind: Piece.light,
          index: i,
          centre: level.lights[i].position,
          size: Vector3.all(kGizmoSize),
          // Its own colour, brightened so a dim lamp is still visible as a mark.
          tint: _atLeast(level.lights[i].color, 0.35),
        ),
      for (var i = 0; i < level.entities.length; i++)
        Handle(
          kind: Piece.entity,
          index: i,
          centre: level.entities[i].position,
          // **Its own size when the document gives it one**, then whatever the
          // game said this type is, then a mark. A door is six metres by five
          // and a lift is a platform somebody stands on, and both say so in
          // `size`; a torch says nothing, and the game's `editor.json` can say
          // it is a slim upright thing rather than a cube.
          size: looks.sizeFor(level.entities[i]) ?? Vector3.all(kGizmoSize),
          volume: level.entities[i].vector('size') != null,
          tint: looks.tintFor(level.entities[i]) ??
              tintFor(level.entities[i].type),
        ),
    ];

/// A colour for an entity type.
///
/// **From the word itself, not from a table of the words this repository
/// happens to use.** The editor has no vocabulary — see `vocabularyOf` — so it
/// cannot know that `monster` is dangerous and `pickup` is not. What it can do
/// is give every distinct type its own hue and keep it stable between launches,
/// which is enough to see at a glance that these six things are the same kind
/// of thing and that one over there is not.
///
/// The one exception is anything with `spawn` in its name, which is green,
/// because where the player starts is the one thing an editor is always looking
/// for.
Vector3 tintFor(String type) {
  if (type.contains('spawn')) return Vector3(0.35, 1.0, 0.4);
  var hash = 0;
  for (final unit in type.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _fromHue((hash % 360) / 360.0);
}

/// A saturated colour at [hue], which is the whole of the colour wheel this
/// needs: the marks are small and want to be told apart, not shaded.
Vector3 _fromHue(double hue) {
  final sector = hue * 6.0;
  final rise = sector - sector.floorToDouble();
  final fall = 1.0 - rise;
  return switch (sector.floor() % 6) {
    0 => Vector3(1.0, rise, 0.0),
    1 => Vector3(fall, 1.0, 0.0),
    2 => Vector3(0.0, 1.0, rise),
    3 => Vector3(0.0, fall, 1.0),
    4 => Vector3(rise, 0.0, 1.0),
    _ => Vector3(1.0, 0.0, fall),
  };
}

Vector3 _atLeast(Vector3 colour, double floor) {
  final brightest = <double>[colour.x, colour.y, colour.z].reduce(
    (double a, double b) => a > b ? a : b,
  );
  if (brightest >= floor) return colour.clone();
  if (brightest < 1e-6) return Vector3.all(floor);
  return colour * (floor / brightest);
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
List<Placeable> paletteOf(Level level, {Iterable<String> declared = const <String>[]}) {
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
        tint: _atLeast(
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
