import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'looks.dart';

/// What a level is made of, from an editor's side.
///
/// **Three, and a material is deliberately not a fourth.** A material is the
/// other thing an editor authors — it is what a brush's `material` names, and
/// the panel that edits one is `material_panel.dart` — so the question of
/// adding it here was asked and answered no. Everything this set reaches is
/// *a list and an index into it*: [Handle] carries an `index`, `Editing`
/// selects with an `int`, and its `switch`es turn a kind into `brushes`,
/// `lights` or `entities` and then call `removeAt` on one. A level's materials
/// are a map keyed by name, with no position, nothing to draw, nothing to
/// point at and nothing to nudge — so a material as a fourth member would be
/// one every one of those `switch`es had to answer "not that one" to, and the
/// set would stop meaning what [Handle]'s own doc says it means: something in
/// the document that can be pointed at and moved. A fourth list in a level
/// that *can* be pointed at is another matter, and why the set is open.
///
/// So the material panel selects by name instead, and that selection is the
/// panel's own: nothing else in the editor — no gizmo, no arrow key, no click
/// — needs to know which material is open, which is exactly the difference
/// from a selected brush.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class Piece {
  const Piece._(this.name);

  /// Geometry. The only one of the three that is drawn by the game.
  static const Piece brush = Piece._('brush');

  /// A light: a lamp, the sun, a torch's flame.
  static const Piece light = Piece._('light');

  /// Everything else the document names — a monster, a lift, a door, a
  /// pickup, the point the player starts at. What any of those *are* belongs
  /// to the game; where they are does not.
  static const Piece entity = Piece._('entity');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<Piece> values = <Piece>[brush, light, entity];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static Piece? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'Piece.$name';
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
    required this.center,
    required this.size,
    required this.tint,
    this.volume = false,
  });

  final Piece kind;

  /// Which one, in the document's own list for [kind].
  final int index;

  final Vector3 center;
  final Vector3 size;

  /// What to draw it in, linear. A light wears its own colour, which is the
  /// fastest way to see that a room is lit orange because somebody made it
  /// orange.
  final LinearColor tint;

  /// Whether the *document* gave this a size of its own.
  ///
  /// **The editor's way of saying "this is a region, not a thing"** without
  /// knowing what a trigger is. Something the author sized is something whose
  /// extent is the point — a trigger volume, a lift's platform — and a solid
  /// box drawn over one hides whatever it contains and lies flat against the
  /// wall it was placed on. Those are drawn as a cage of edges instead.
  final bool volume;

  Vector3 get min => center - size / 2.0;
  Vector3 get max => center + size / 2.0;
}

/// How big the mark for something with no geometry is, in metres.
///
/// Half a metre: large enough to hit with a mouse from across a room, small
/// enough not to hide the thing it stands for. A monster is about this wide
/// anyway, which makes the mark read as the monster rather than as a label.
const double gizmoSize = 0.5;

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
      center: level.brushes[i].center,
      size: level.brushes[i].size,
      tint: const LinearColor(1.0, 0.45, 0.05),
    ),
  for (var i = 0; i < level.lights.length; i++)
    Handle(
      kind: Piece.light,
      index: i,
      center: level.lights[i].position,
      size: Vector3.all(gizmoSize),
      // Its own colour, brightened so a dim lamp is still visible as a mark.
      tint: atLeast(level.lights[i].color, 0.35),
    ),
  for (var i = 0; i < level.entities.length; i++)
    Handle(
      kind: Piece.entity,
      index: i,
      center: level.entities[i].position,
      // **Its own size when the document gives it one**, then whatever the
      // game said this type is, then a mark. A door is six metres by five
      // and a lift is a platform somebody stands on, and both say so in
      // `size`; a torch says nothing, and the game's `editor.json` can say
      // it is a slim upright thing rather than a cube.
      size: looks.sizeFor(level.entities[i]) ?? Vector3.all(gizmoSize),
      volume: level.entities[i].vector('size') != null,
      tint: looks.tintFor(level.entities[i]) ?? tintFor(level.entities[i].type),
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
LinearColor tintFor(String type) {
  if (type.contains('spawn')) return const LinearColor(0.35, 1.0, 0.4);
  var hash = 0;
  for (final unit in type.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _fromHue((hash % 360) / 360.0);
}

/// A saturated colour at [hue], which is the whole of the colour wheel this
/// needs: the marks are small and want to be told apart, not shaded.
LinearColor _fromHue(double hue) {
  final sector = hue * 6.0;
  final rise = sector - sector.floorToDouble();
  final fall = 1.0 - rise;
  return switch (sector.floor() % 6) {
    0 => LinearColor(1.0, rise, 0.0),
    1 => LinearColor(fall, 1.0, 0.0),
    2 => LinearColor(0.0, 1.0, rise),
    3 => LinearColor(0.0, fall, 1.0),
    4 => LinearColor(rise, 0.0, 1.0),
    _ => LinearColor(1.0, 0.0, fall),
  };
}

/// [color], brightened up to [floor] if it is dimmer than that.
///
/// Public rather than a private helper of this file alone: `palette_items.dart`
/// needs the same brightening for a palette row's swatch, and a colour that
/// reads as black in one place and is nudged up in the other is a colour that
/// looks like two different bugs.
LinearColor atLeast(LinearColor color, double floor) {
  final brightest = <double>[
    color.r,
    color.g,
    color.b,
  ].reduce((double a, double b) => a > b ? a : b);
  if (brightest >= floor) return color;
  if (brightest < 1e-6) return LinearColor(floor, floor, floor, color.a);
  return color.scaled(floor / brightest);
}
