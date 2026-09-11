/// Reflecting a mesh across a plane through the origin, and welding the seam.
///
/// **A plain function, the same split `mergeByDistance` already made** between
/// the geometry (here) and the modifier-stack wrapper (`MirrorModifier`, in
/// `modifier.dart`) that just calls it with its own stored parameters. Testing
/// the geometry does not need a `Modifier` or a `ModifierContext` in the way.
library;

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';
import 'merge.dart';

/// [base], unioned with itself reflected across the plane through the origin
/// with unit normal [normal], welded within [mergeDistance] of the seam when
/// given.
///
/// **Through the origin only.** An object's own local space already puts a
/// symmetry plane there for the ordinary case — mirroring across the middle
/// of the thing being modelled — and an arbitrary offset plane is a second
/// number nothing asks for yet; [normal] alone is enough to say which way.
///
/// **Every face is kept twice: once as it was, once reflected with its
/// winding reversed** (reflection inverts handedness, so a face that drew
/// outward before would draw inward after if wound the same way). A `base`
/// that already touches the plane — the ordinary case, since that is what
/// makes the result one closed shape rather than two — has its own
/// on-the-plane geometry doubled by this and needs [mergeDistance] to both
/// weld the coincident seam vertices and drop the coincident, oppositely
/// wound face each side leaves sitting exactly on the other (the same "wall
/// seen from both sides" case [mergeByDistance] already detects).
///
/// [bisect] is not built: trimming `base` to one side of the plane before
/// mirroring needs real geometric clipping along it, which nothing in this
/// package does yet — that is `mesh-47`'s BSP machinery's problem to solve,
/// not written either. Passing `true` throws rather than silently mirroring
/// the whole, unclipped mesh regardless.
EditMesh mirror(
  EditMesh base, {
  required Vector3 normal,
  double? mergeDistance,
  bool bisect = false,
}) {
  if (bisect) {
    throw UnimplementedError(
      'mirror(bisect: true) is not built: trimming a mesh to one side of a '
      'plane needs real geometric clipping, which nothing in flutter3d_mesh '
      'does yet. Mirror a base that is already the half you want instead.',
    );
  }

  final axis = normal.normalized();
  final builder = EditMeshBuilder();
  final liveVertices = <int>[
    for (var v = 0; v < base.vertexSlotCount; v++)
      if (base.isVertexAlive(v)) v,
  ];
  final baseFaces = base.faces();
  final baseSlots = <int>[
    for (var f = 0; f < base.faceSlotCount; f++)
      if (base.isFaceAlive(f)) base.materialSlotOf(f),
  ];
  final hasSlots = base.hasLayer(MeshDomain.face, MeshAttribute.materialSlot);

  final kept = <int, int>{
    for (final int old in liveVertices)
      old: builder.addVertex(base.positionOf(old)),
  };
  final mirrored = <int, int>{
    for (final int old in liveVertices)
      old: builder.addVertex(_reflected(base.positionOf(old), axis)),
  };

  final newFaces = <int>[];
  for (final List<int> loop in baseFaces) {
    newFaces.add(builder.addFace(<int>[for (final int v in loop) kept[v]!]));
  }
  for (final List<int> loop in baseFaces) {
    newFaces.add(
      builder.addFace(<int>[for (final int v in loop.reversed) mirrored[v]!]),
    );
  }

  var result = builder.build();
  if (hasSlots) {
    result.beginStep();
    for (var i = 0; i < baseFaces.length; i++) {
      result.setMaterialSlot(newFaces[i], baseSlots[i]);
      result.setMaterialSlot(newFaces[baseFaces.length + i], baseSlots[i]);
    }
    result.endStep();
  }
  if (mergeDistance != null) {
    final (EditMesh merged, _) = mergeByDistance(
      result,
      distance: mergeDistance,
    );
    result = merged;
  }
  return result;
}

/// [p] reflected across the plane through the origin with unit normal
/// [axis]: `p - 2 * (p · axis) * axis`.
Vector3 _reflected(Vector3 p, Vector3 axis) => p - axis.scaled(2 * p.dot(axis));
