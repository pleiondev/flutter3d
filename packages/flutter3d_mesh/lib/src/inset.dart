/// Shrinking a face's own border inward, and walling in the ring it leaves.
///
/// **The same wall-building shape [extrudeFaces] uses, with a different
/// position for the new ring.** A face's own vertices stay exactly where
/// they are — shared with whatever is on the other side of each edge, the
/// same as before — and a fresh copy of the ring is added, walled to the
/// old one, and the face itself is remapped onto the new ring. Extrude moves
/// that new ring along the face's own normal by a distance; inset moves it
/// inward by [thickness] and, when [depth] is not zero, along the normal
/// too — a combined inset-and-push in one call, which is what a person
/// dragging both at once expects rather than two operations chained.
///
/// **Each selected face is its own region.** Two adjacent selected faces
/// sharing an edge are each inset on their own rather than treated as one
/// region with only the outer rim walled — that grouping is
/// [extrudeFaces]'s own `individual: false` case and needs the boundary of
/// a face group worked out first; nothing here builds that yet, so every
/// call insets face by face regardless of how many are selected.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';
import 'operations.dart';
import 'selection.dart';

/// Insets every selected face by [thickness], pushed along its own normal by
/// [depth].
///
/// [individual] is accepted for the shape the plan's own row names — every
/// call already insets face by face, so it changes nothing yet; it is where
/// region-mode's own switch will live once that is built.
OpResult insetFaces(
  EditMesh mesh,
  Selection selection, {
  required double thickness,
  double depth = 0.0,
  bool individual = true,
}) {
  final faces = selection.convertedTo(mesh, ElementLevel.face);
  if (faces.isEmpty) {
    return OpResult.refused(
      'no faces are selected to inset',
      selection: selection,
    );
  }

  final made = <int>[];
  final moved = <int>{};
  for (final face in faces.ids) {
    final (int? inner, String? refusal) = _insetOneFace(
      mesh,
      face,
      thickness,
      depth,
    );
    if (refusal != null) return OpResult.refused(refusal, selection: selection);
    made.add(inner!);
    mesh.forEachVertex(inner, moved.add);
  }

  return OpResult.done(
    selection: Selection.of(ElementLevel.face, made),
    movedVertices: Int32List.fromList(moved.toList()..sort()),
    topologyChanged: true,
  );
}

/// Insets [face] on its own, or the sentence to show somebody when it
/// cannot. The face this returns is the same id [face] was — its own
/// half-edges are remapped onto the new, inset ring rather than replaced.
(int?, String?) _insetOneFace(
  EditMesh mesh,
  int face,
  double thickness,
  double depth,
) {
  if (!mesh.isFaceAlive(face)) {
    return (null, 'a selected face is no longer there');
  }

  final boundary = <int>[]; // half-edges of the face, in loop order
  mesh.forEachHalfEdge(face, boundary.add);
  final n = boundary.length;
  final from = <int>[for (final half in boundary) mesh.originOf(half)];
  final outside = <int>[
    for (final half in boundary)
      mesh.hasLiveTwin(half) ? mesh.twinOf(half) : EditMesh.none,
  ];

  final normal = mesh.normalOf(face);
  final positions = <Vector3>[for (final v in from) mesh.positionOf(v)];
  final insetAt = insetCornerPositions(positions, normal, thickness, depth);

  final lifted = <int>[for (final p in insetAt) mesh.addVertex(p)];
  for (var i = 0; i < n; i++) {
    mesh.setOrigin(boundary[i], lifted[i]);
  }

  final firsts = <int>[];
  for (var i = 0; i < n; i++) {
    final next = (i + 1) % n;
    final first = mesh.halfEdgeSlotCount;
    final wall = mesh.addFace(<int>[
      from[i],
      from[next],
      lifted[next],
      lifted[i],
    ]);
    firsts.add(first);
    if (outside[i] != EditMesh.none) mesh.weldTwins(first, outside[i]);
    mesh.weldTwins(first + 2, boundary[i]);
    _inheritWall(mesh, wall, first, face);
    mesh.setOutgoing(from[i], first);
  }
  for (var i = 0; i < n; i++) {
    final next = (i + 1) % n;
    mesh.weldTwins(firsts[i] + 1, firsts[next] + 3);
  }

  return (face, null);
}

/// [positions] moved inward by [thickness] and along [normal] by [depth],
/// one per vertex of a planar, convex polygon loop.
///
/// **Corrected for the angle at each corner, not a plain sum of two unit
/// normals.** A vertex where two edges meet at a shallow angle needs to move
/// further along their shared bisector than one at a right angle does, for
/// the two edges of the inset ring to end up the same [thickness] from the
/// originals as every other edge is — the same reason a mitred picture
/// frame's outer corners are cut steeper than its straight run. Uncorrected,
/// only a rectangle's own right angles would happen to come out even.
///
/// **Public rather than file-private because `bevel.dart` needs the exact
/// same formula.** A face whose every edge is being beveled shrinks by
/// exactly this same mitred amount at each of its own corners — the two
/// operations part ways only in what happens to the gap that shrinking
/// leaves: [insetFaces] walls it back to the face's own original boundary,
/// `bevelEdges`/`bevelVertices` bridge it to the *neighbouring* face's own
/// shrunk corner instead, since both sides of a beveled edge move.
List<Vector3> insetCornerPositions(
  List<Vector3> positions,
  Vector3 normal,
  double thickness,
  double depth,
) {
  final n = positions.length;
  final out = <Vector3>[];
  final along = normal.scaled(depth);
  for (var i = 0; i < n; i++) {
    final prev = positions[(i - 1 + n) % n];
    final curr = positions[i];
    final next = positions[(i + 1) % n];

    final incoming = (curr - prev).normalized();
    final outgoing = (next - curr).normalized();
    // In the face's own plane, perpendicular to each edge, pointing inward
    // for a face wound the way this package's own faces always are.
    final inwardIncoming = normal.cross(incoming).normalized();
    final inwardOutgoing = normal.cross(outgoing).normalized();

    final bisector = inwardIncoming + inwardOutgoing;
    final length = bisector.length;
    if (length < 1e-9) {
      // A corner that doubles back on itself (180°): the two edge normals
      // cancel and there is no single bisector. Its own inward normal is
      // the only direction left to move it.
      out.add(curr + inwardIncoming.scaled(thickness) + along);
      continue;
    }
    bisector.scale(1 / length);
    // How far along the bisector puts the new edge `thickness` from the old
    // one: `bisector · inwardIncoming` is the cosine of the half-angle
    // between the bisector and either edge normal, and dividing by it is
    // exactly the 1/sin(θ/2) correction a mitred corner needs.
    final cosHalfAngle = bisector.dot(inwardIncoming);
    final scale = cosHalfAngle.abs() < 1e-9
        ? thickness
        : thickness / cosHalfAngle;
    out.add(curr + bisector.scaled(scale) + along);
  }
  return out;
}

/// Gives a wall grown out of an inset the shading and the material of the
/// face it came from, and a unit square of texture of its own — the same
/// choice [extrudeFaces]'s own walls make, for the same reason: a wall is a
/// surface that did not exist, so its place in a texture says nothing.
///
/// **Deliberately not carried: vertex colour.** [extrudeFaces]'s own version
/// interpolates a wall's four corners between the colours at its two source
/// vertices; nothing has asked for that here yet, and it is a real gap worth
/// closing before this is relied on for a painted mesh, not one silently
/// papered over — a wall left uncoloured reads as white rather than as
/// whatever colour a person expected it to inherit.
void _inheritWall(EditMesh mesh, int wall, int first, int source) {
  if (mesh.hasLayer(MeshDomain.face, MeshAttribute.materialSlot)) {
    mesh.setMaterialSlot(wall, mesh.materialSlotOf(source));
  }
  if (mesh.hasLayer(MeshDomain.face, MeshAttribute.flags)) {
    mesh.setFaceFlag(
      wall,
      FaceFlags.smooth,
      on: mesh.faceHas(source, FaceFlags.smooth),
    );
  }
  if (mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0)) {
    mesh
      ..setUv(first, Vector2(0, 0))
      ..setUv(first + 1, Vector2(1, 0))
      ..setUv(first + 2, Vector2(1, 1))
      ..setUv(first + 3, Vector2(0, 1));
  }
}
