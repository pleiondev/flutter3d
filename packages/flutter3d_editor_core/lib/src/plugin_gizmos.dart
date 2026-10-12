/// Gizmos a plugin draws over the things of a level, and the commands a drag
/// of one of their handles turns into.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'editor_command.dart';
import 'gizmos.dart';
import 'picking.dart';

/// The shape a [GizmoMark] is drawn as.
///
/// A class with constants rather than an enum, so a shape added in a minor
/// breaks no `switch`; an editor that meets one it does not draw draws a
/// [cage] around the mark's box.
final class GizmoShape {
  const GizmoShape._(this.name);

  /// A solid box.
  static const GizmoShape box = GizmoShape._('box');

  /// The twelve edges of a box: a region.
  static const GizmoShape cage = GizmoShape._('cage');

  /// A ball: a radius, a reach.
  static const GizmoShape ball = GizmoShape._('ball');

  /// A segment from one point to another: a direction, a link.
  static const GizmoShape line = GizmoShape._('line');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<GizmoShape> values = <GizmoShape>[box, cage, ball, line];

  /// The value called [name], or null for a name this version does not know.
  static GizmoShape? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name. Never renamed within a major.
  final String name;

  @override
  String toString() => 'GizmoShape.$name';
}

/// One thing a gizmo draws: a shape in the world, in metres, and the name
/// of the handle it is, when it can be dragged.
final class GizmoMark {
  /// A solid box at [center], [size] across.
  GizmoMark.box(Vector3 center, Vector3 size, {this.tint, this.handle})
    : shape = GizmoShape.box,
      from = center.clone(),
      to = center.clone(),
      size = size.clone();

  /// The edges of a box at [center], [size] across.
  GizmoMark.cage(Vector3 center, Vector3 size, {this.tint, this.handle})
    : shape = GizmoShape.cage,
      from = center.clone(),
      to = center.clone(),
      size = size.clone();

  /// A ball at [center] of [radius].
  GizmoMark.ball(
    Vector3 center, {
    required double radius,
    this.tint,
    this.handle,
  }) : shape = GizmoShape.ball,
       from = center.clone(),
       to = center.clone(),
       size = Vector3.all(radius * 2.0);

  /// A segment from [from] to [to], [width] thick.
  GizmoMark.line(
    Vector3 from,
    Vector3 to, {
    double width = 0.04,
    this.tint,
    this.handle,
  }) : shape = GizmoShape.line,
       from = from.clone(),
       to = to.clone(),
       size = Vector3.all(width);

  /// How it is drawn.
  final GizmoShape shape;

  /// Its centre, or a line's first end.
  final Vector3 from;

  /// A line's second end; [from] for every other shape.
  final Vector3 to;

  /// Its extent: a box's size, a ball's diameter on every axis, a line's
  /// width on every axis.
  final Vector3 size;

  /// The colour it is drawn in, linear, or null for the colour of what it
  /// marks.
  final LinearColor? tint;

  /// The name of the handle it is, handed back in a [GizmoDrag]; null for a
  /// mark that is only looked at.
  final String? handle;

  /// Its centre: [from], or a line's midpoint.
  Vector3 get center => shape == GizmoShape.line ? (from + to) * 0.5 : from;

  /// The box that holds it, for a pointer to hit.
  (Vector3, Vector3) get bounds {
    if (shape == GizmoShape.line) {
      final half = size * 0.5;
      final low = Vector3.zero();
      final high = Vector3.zero();
      Vector3.min(from, to, low);
      Vector3.max(from, to, high);
      return (low - half, high + half);
    }
    return (from - size * 0.5, from + size * 0.5);
  }
}

/// What a gizmo is asked about: one thing of the level, where it is, and
/// whether it is selected.
///
/// Made by the editor, never by a plugin. **One object, so it can grow**: a
/// member added in a minor reaches every gizmo without changing a signature.
final class GizmoContext {
  GizmoContext({
    required this.level,
    required this.kind,
    required this.index,
    required this.selected,
  });

  /// The level being edited.
  final Level level;

  /// Which of the level's lists the thing is in.
  final Piece kind;

  /// Which one, in that list.
  final int index;

  /// Whether it is selected.
  final bool selected;

  /// The entity, when [kind] is an entity.
  EntityDef? get entity => kind == Piece.entity && index < level.entities.length
      ? level.entities[index]
      : null;

  /// The light, when [kind] is a light.
  LevelLight? get light => kind == Piece.light && index < level.lights.length
      ? level.lights[index]
      : null;

  /// The brush, when [kind] is a brush.
  Brush? get brush => kind == Piece.brush && index < level.brushes.length
      ? level.brushes[index]
      : null;

  /// Where the thing is: an entity's or a light's position, a brush's
  /// centre.
  Vector3 get where =>
      (entity?.position ?? light?.position ?? brush?.center ?? Vector3.zero())
          .clone();
}

/// A handle of a [GizmoMark] dragged from one point to another.
final class GizmoDrag {
  GizmoDrag({
    required this.target,
    required this.handle,
    required Vector3 from,
    required Vector3 to,
  }) : from = from.clone(),
       to = to.clone();

  /// What the dragged mark marks.
  final GizmoContext target;

  /// The [GizmoMark.handle] dragged.
  final String handle;

  /// Where the drag started, in the world.
  final Vector3 from;

  /// Where it is now.
  final Vector3 to;

  /// How far it went.
  Vector3 get by => to - from;
}

/// A gizmo a plugin draws: marks over the things it [appliesTo], and the
/// command a drag of one of their handles is.
///
/// ```dart
/// final class RangeRing extends EditorGizmo {
///   @override
///   bool appliesTo(GizmoContext context) => context.entity?.type == 'tower';
///
///   @override
///   List<GizmoMark> marksFor(GizmoContext context) => [
///     GizmoMark.ball(context.where,
///         radius: context.entity!.number('range') ?? 8, handle: 'range'),
///   ];
///
///   @override
///   DocumentCommand? dragged(GizmoDrag drag) =>
///       SetField('range', drag.to.distanceTo(drag.target.where));
/// }
/// ```
///
/// **A drag is a command, not a write**, so it is undone as any edit is and
/// an agent can do the same with `command.run`. `base`, so a member added
/// in a minor arrives with a body; each hook takes one context.
abstract base class EditorGizmo {
  const EditorGizmo();

  /// Whether this gizmo marks the thing [context] names. Every entity by
  /// default.
  bool appliesTo(GizmoContext context) => context.kind == Piece.entity;

  /// What it draws for the thing [context] names.
  List<GizmoMark> marksFor(GizmoContext context);

  /// The command a drag of one of its handles is, or null to leave the
  /// document alone. Null by default.
  DocumentCommand? dragged(GizmoDrag drag) => null;
}

/// A [GizmoMark] where an editor drew it: the gizmo that drew it, by its
/// published name, and the thing of the level it marks.
final class DrawnMark {
  const DrawnMark({
    required this.gizmo,
    required this.kind,
    required this.index,
    required this.mark,
  });

  /// The gizmo's published name, `<namespace>.<name>`.
  final String gizmo;

  /// Which of the level's lists the marked thing is in.
  final Piece kind;

  /// Which one, in that list.
  final int index;

  /// What is drawn.
  final GizmoMark mark;
}

/// Which mark with a handle [from] pointing [along] hits first, or null.
///
/// Only a mark with a [GizmoMark.handle]: one that is only looked at is no
/// more in the way of a click than a label.
DrawnMark? markUnder(List<DrawnMark> marks, Vector3 from, Vector3 along) {
  DrawnMark? nearest;
  var nearestAt = double.infinity;
  for (final drawn in marks) {
    if (drawn.mark.handle == null) continue;
    final (low, high) = drawn.mark.bounds;
    final distance = Picking.hit(low, high, from, along);
    if (distance != null && distance < nearestAt) {
      nearestAt = distance;
      nearest = drawn;
    }
  }
  return nearest;
}
