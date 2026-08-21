import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

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
  });

  final Piece kind;

  /// Which one, in the document's own list for [kind].
  final int index;

  final Vector3 centre;
  final Vector3 size;

  /// What to draw it in. A light wears its own colour, which is the fastest way
  /// to see that a room is lit orange because somebody made it orange.
  final Vector3 tint;

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
List<Handle> handlesOf(Level level) => <Handle>[
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
          size: Vector3.all(kGizmoSize),
          tint: tintFor(level.entities[i].type),
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
