/// Snapping a dragged vertex or edge onto *somebody else's* geometry.
///
/// **`view-23n`'s gizmo drag already snaps to a grid, a fifteen-degree turn and
/// a tenth of scale — none of which knows the model has a neighbour.** Putting
/// a table leg in the corner of a tabletop, or lining up the seam of a modular
/// set, needs the dragged element to land on a vertex or an edge that already
/// exists on some *other* piece of geometry, exactly — not on the nearest
/// multiple of a tenth of a metre. `MeshPicker` already answers "what is near
/// this ray" for a click; this file asks the same question once a frame,
/// through the point the drag currently wants to move to rather than through
/// the pointer, so a search that only ever runs on a click can be run on every
/// report of a drag without becoming a different kind of code.
///
/// **What is not here is a screen.** [findSnapTarget] takes a [PickingView] —
/// the same camera-and-viewport value `element_picking.dart` already built
/// picking around — and a plain list of other objects' pickers; nothing in
/// this file reads a pointer event or draws anything, so a test can ask what a
/// drag to a given world point snaps onto with no widget anywhere near it.
///
/// **A face snaps by the ray hitting it, not by a radius scan.** A vertex and
/// an edge have no area, so "near" for them means "within a few pixels of the
/// line the drag is pointing along" — a scan over [MeshPicker.vertexNear] and
/// [MeshPicker.edgeNear]. A face has area, so the same question a click
/// already asks of it — [MeshBvh.raycast], the same tree walk [MeshPicker
/// .faceAt] wraps — answers exactly where a face snap belongs: the point on
/// the face's own plane, inside its own bounds, that the drag's ray actually
/// passes through, not a projection that could land outside the face
/// entirely.
library;

import 'package:flutter3d_geometry/flutter3d_geometry.dart' show Ray;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

import 'element_picking.dart' show PickingView;

/// Which kind of element a drag can snap onto.
///
/// Ordered the way [findSnapTarget] considers them when two or more
/// candidates land at the same distance: a vertex first, since every edge has
/// one on it and a tie is more often aimed at the point than at the line
/// through it; an edge before a face, for the same reason one level down —
/// every face's boundary is edges, and a tie is more often aimed at the seam
/// than at the open surface either side of it.
enum SnapLevel { vertex, edge, face }

/// One other object's geometry, offered up as something a drag might snap
/// onto.
///
/// **A picker and a transform, not a mesh and a matrix kept separately.** The
/// two are asked for together everywhere else in this application —
/// `element_picking.dart`'s own `objectToWorld` — and a caller that built one
/// without the other would be a caller free to hand over a picker for one
/// object and the transform of another.
final class SnapSource {
  const SnapSource({
    required this.id,
    required this.picker,
    this.objectToWorld,
  });

  /// The object this geometry belongs to, so a caller can tell which one a
  /// [SnapTarget] landed on — for excluding it from a later search, or for
  /// naming it in a highlight.
  final int id;

  final MeshPicker picker;

  /// This object's local-to-world transform, or null when it already is one
  /// — the same convention `pickElementAt`'s own `objectToWorld` uses.
  final Matrix4? objectToWorld;
}

/// What a drag would snap onto: which object, which element of it, and the
/// exact world position that element sits at.
///
/// [position] is the value a caller hands the dragged element rather than
/// wherever the pointer landed — copied straight out of the target mesh's own
/// vertex positions for [SnapLevel.vertex], so the acceptance this row is
/// built to is not approximate: the two positions are the same [Vector3],
/// bit for bit.
final class SnapTarget {
  const SnapTarget({
    required this.sourceId,
    required this.level,
    required this.element,
    required this.position,
  });

  final int sourceId;
  final SnapLevel level;

  /// A vertex id for [SnapLevel.vertex], the half-edge `edgeNear` answered
  /// with for [SnapLevel.edge], or the face `MeshBvh.raycast` answered with
  /// for [SnapLevel.face].
  final int element;

  final Vector3 position;
}

/// A vertex wins a near-tie against an edge, for the reason [SnapLevel]
/// states — and it has to be a *near*-tie rather than an exact one: a point a
/// hair from a cube's corner sits, up to rounding, the same distance from that
/// corner's own vertex as from the two edges that meet there, and `from +
/// (to - from) * 1.0` is not always bit-identical to `to`. Comparing the raw
/// floats and letting whichever rounded smaller win would make the tie-break
/// a coin flip decided by which edge the scan happened to visit, on the exact
/// case the rule above exists to settle.
const double _vertexPriorityEpsilon = 1e-9;

/// The nearest thing in [sources] worth snapping [near] onto, within
/// [radiusPixels] of it on screen — or null when nothing in [levels] is that
/// close.
///
/// **[near] stands in for the pointer.** A drag does not move the mouse to
/// where a vertex is; it moves a vertex to wherever the drag's own arithmetic
/// currently wants it, and *that* point is what has to be near somebody else's
/// geometry on screen for a snap to make sense. Projecting it and casting a
/// ray back through the same pixel is the same round trip `pickElementAt`
/// makes from an actual click — the two are answering the same question, one
/// from a press and one from wherever a drag has got to.
///
/// The radius is measured in world units at [near]'s own depth, the way every
/// picker in this application sizes a pixel: a target a hand's width away in
/// the foreground and one three pixels wide in the distance are not offered
/// the same slack, because a screen-space radius is what "within a few pixels"
/// has to mean for it to still mean that up close and far away both.
SnapTarget? findSnapTarget({
  required PickingView view,
  required Vector3 near,
  required List<SnapSource> sources,
  required double radiusPixels,
  Set<SnapLevel> levels = const <SnapLevel>{
    SnapLevel.vertex,
    SnapLevel.edge,
    SnapLevel.face,
  },
}) {
  if (levels.isEmpty || sources.isEmpty) return null;

  final screen = view.project(near);
  if (screen == null) return null;
  final ray = view.rayThrough(screen);
  final depth = (near - ray.origin).dot(ray.direction);
  if (depth <= 0.0) return null;
  final worldRadius = view.worldWidthAt(
    screen,
    pixels: radiusPixels,
    distance: depth,
  );
  if (worldRadius <= 0.0) return null;

  SnapTarget? bestVertex;
  var bestVertexDistance = double.infinity;
  SnapTarget? bestEdge;
  var bestEdgeDistance = double.infinity;
  SnapTarget? bestFace;
  var bestFaceDistance = double.infinity;
  final at = Vector3.zero();
  final from = Vector3.zero();
  final to = Vector3.zero();

  for (final source in sources) {
    final local = _intoLocal(ray, source.objectToWorld);
    final localRadius = worldRadius * local.shrink;

    if (levels.contains(SnapLevel.vertex)) {
      final vertex = source.picker.vertexNear(local.ray, radius: localRadius);
      if (vertex != EditMesh.none) {
        source.picker.mesh.positionOf(vertex, at);
        final world = _toWorld(at, source.objectToWorld);
        final distance = (world - near).length;
        if (distance < bestVertexDistance) {
          bestVertexDistance = distance;
          bestVertex = SnapTarget(
            sourceId: source.id,
            level: SnapLevel.vertex,
            element: vertex,
            position: world,
          );
        }
      }
    }

    if (levels.contains(SnapLevel.edge)) {
      final edge = source.picker.edgeNear(local.ray, radius: localRadius);
      if (edge != EditMesh.none) {
        final mesh = source.picker.mesh;
        mesh.positionOf(mesh.originOf(edge), from);
        mesh.positionOf(mesh.originOf(mesh.nextOf(edge)), to);
        final worldFrom = _toWorld(from, source.objectToWorld);
        final worldTo = _toWorld(to, source.objectToWorld);
        final onSegment = _nearestOnSegment(near, worldFrom, worldTo);
        final distance = (onSegment - near).length;
        if (distance < bestEdgeDistance) {
          bestEdgeDistance = distance;
          bestEdge = SnapTarget(
            sourceId: source.id,
            level: SnapLevel.edge,
            element: edge,
            position: onSegment,
          );
        }
      }
    }

    if (levels.contains(SnapLevel.face)) {
      final hit = source.picker.bvh.raycast(local.ray);
      if (hit != null) {
        final world = _toWorld(hit.point, source.objectToWorld);
        final distance = (world - near).length;
        if (distance <= worldRadius && distance < bestFaceDistance) {
          bestFaceDistance = distance;
          bestFace = SnapTarget(
            sourceId: source.id,
            level: SnapLevel.face,
            element: hit.face,
            position: world,
          );
        }
      }
    }
  }

  // Priority order — vertex, then edge, then face, [SnapLevel]'s own doc
  // comment says why — broken only by whichever is unambiguously nearer than
  // every level ahead of it in that order.
  final candidates = <SnapTarget?>[bestVertex, bestEdge, bestFace];
  final distances = <double>[
    bestVertexDistance,
    bestEdgeDistance,
    bestFaceDistance,
  ];
  var nearest = double.infinity;
  for (final distance in distances) {
    if (distance < nearest) nearest = distance;
  }
  for (var i = 0; i < candidates.length; i++) {
    if (candidates[i] != null &&
        distances[i] <= nearest + _vertexPriorityEpsilon) {
      return candidates[i];
    }
  }
  return null;
}

/// [world] carried into the space [objectToWorld] maps out of, with how much
/// shorter world lengths are there — the same conversion `element_picking.dart`
/// makes to trace a click into a mesh's own space, needed again here because
/// [MeshPicker] answers in whatever space its mesh's own positions are in.
({Ray ray, double shrink}) _intoLocal(Ray world, Matrix4? objectToWorld) {
  if (objectToWorld == null) return (ray: world, shrink: 1.0);
  final inverse = Matrix4.copy(objectToWorld)..invert();
  final local = world.transformInto(inverse, Ray.zero());
  final shrink = local.direction.length;
  return (ray: local.normalizeDirection(), shrink: shrink);
}

Vector3 _toWorld(Vector3 local, Matrix4? objectToWorld) {
  if (objectToWorld == null) return Vector3.copy(local);
  final world = Vector3.copy(local);
  objectToWorld.transform3(world);
  return world;
}

/// The point on the segment [from]–[to] nearest [point], clamped to the
/// segment rather than to the infinite line through it — an edge seen end-on
/// snaps onto its own end, not onto a point hanging past it in space.
Vector3 _nearestOnSegment(Vector3 point, Vector3 from, Vector3 to) {
  final along = to - from;
  final length2 = along.length2;
  if (length2 < 1e-18) return Vector3.copy(from);
  final t = ((point - from).dot(along) / length2).clamp(0.0, 1.0);
  return from + along * t;
}
