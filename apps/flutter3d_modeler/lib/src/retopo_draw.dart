/// Drawing a retopology by hand — `pro-rt-03`'s own overlay, given something
/// to draw: which two objects a quad is drawn between, the corners placed so
/// far, and where all of it lands on the glass.
///
/// **Two objects, because a retopology is one mesh traced over another.**
/// `DrawQuad` adds a face to `objectId` and pulls its corners onto
/// `sourceId`; the low mesh and the high one are different objects by
/// construction. The selection says which: the last object picked is the one
/// being drawn onto — the *active* object, which is what every mesh command
/// already acts on — and the one picked before it is what it is traced over.
///
/// **And remembered, because `DrawQuad` forgets.** A quad that lands leaves
/// the selection on the target alone — the command's own outcome, so that
/// the new face is what is selected — which would make the second quad of a
/// retopology impossible to draw without selecting both objects again. So
/// the pair last seen is kept, and a selection of just that target goes on
/// meaning the same pair. Anything else — another object, nothing — drops
/// it: the memory is for the command's own side effect, not a mode that
/// outlives what a person selected.
///
/// Pure where it can be. The projection is handed in as a function, so the
/// part of this that decides *what* is drawn is testable with no camera.
library;

import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter3d_core/geometry.dart' show TriangleBvh;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

/// How many faces of the target the overlay draws. A retopology is low by
/// definition — the panel's own slider stops at twenty thousand quads and
/// hand-drawn ones are a few hundred — so this is a guard against somebody
/// naming the *high* mesh as the target, which would otherwise project a
/// million corners every frame.
const int kRetopoOverlayFaceBudget = 4000;

/// The high mesh and the low one.
typedef RetopoPair = ({int sourceId, int targetId});

/// `pro-rt-03`: the pair, the corners, and the high mesh's surface.
final class RetopoDraw {
  RetopoPair? _pair;

  /// The corners of the quad being placed, in world space, in the order
  /// they were clicked. Never four: the fourth click runs the command and
  /// empties this.
  final List<Vector3> corners = <Vector3>[];

  TriangleBvh? _surface;
  EditMesh? _surfaceOf;
  int? _surfaceAtVersion;

  /// Which two objects a quad is drawn between, given what is [selected] —
  /// see this file's own doc comment for the rule — or null when the
  /// selection names no pair. [exists] answers whether the document still
  /// has an object, so a source deleted since is not traced over.
  ///
  /// A different pair from the last one abandons the quad in progress: its
  /// corners are points on a surface that is no longer the one being traced.
  RetopoPair? pairFor(List<int> selected, bool Function(int id) exists) {
    final RetopoPair? was = _pair;
    final RetopoPair? now = switch (selected) {
      [..., final int source, final int target] => (
        sourceId: source,
        targetId: target,
      ),
      [final int only]
          when was != null && only == was.targetId && exists(was.sourceId) =>
        was,
      _ => null,
    };
    if (now != was) corners.clear();
    return _pair = now;
  }

  /// A triangle tree over [mesh] in world space, rebuilt when the mesh or
  /// its owner's [version] is a different one.
  ///
  /// Kept between clicks because the high mesh is the expensive one: a tree
  /// over a million triangles per corner placed would be four pauses per
  /// quad. In world space, because the ray a click casts is.
  TriangleBvh surfaceFor(EditMesh mesh, Matrix4 toWorld, int version) {
    final TriangleBvh? kept = _surface;
    if (kept != null &&
        identical(mesh, _surfaceOf) &&
        version == _surfaceAtVersion) {
      return kept;
    }
    _surfaceOf = mesh;
    _surfaceAtVersion = version;
    return _surface = worldSurfaceOf(mesh, toWorld);
  }

  /// Forgets everything — what leaving the mode does.
  void reset() {
    _pair = null;
    corners.clear();
    _surface = null;
    _surfaceOf = null;
    _surfaceAtVersion = null;
  }
}

/// A triangle tree over [mesh]'s surface with [toWorld] applied — the same
/// walk `flutter3d_mesh`'s own `surfaceOf` makes, in the space a pointer's
/// ray is in rather than the mesh's own.
TriangleBvh worldSurfaceOf(EditMesh mesh, Matrix4 toWorld) {
  final plan = MeshLayoutPlan()..build(mesh);
  final rows = plan.indices;
  final indices = Uint32List(rows.length);
  for (var i = 0; i < rows.length; i++) {
    indices[i] = plan.gpuVertexToVertex[rows[i]];
  }
  final positions = Float32List(mesh.vertexSlotCount * 3);
  final at = Vector3.zero();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    mesh.positionOf(v, at);
    toWorld.transform3(at);
    positions[v * 3] = at.x;
    positions[v * 3 + 1] = at.y;
    positions[v * 3 + 2] = at.z;
  }
  return TriangleBvh.fromArrays(positions, indices);
}

/// Every face of [mesh] as a polygon on the glass — what `RetopoOverlay`
/// draws as its grid.
///
/// [project] answers null for a point behind the camera, and a face with any
/// corner there is left out whole: a polygon closed through a corner the
/// camera cannot see is a wedge across the screen. At most [budget] faces;
/// see [kRetopoOverlayFaceBudget].
List<List<Offset>> retopoFacesOnScreen(
  EditMesh mesh,
  Matrix4 toWorld,
  Offset? Function(Vector3 world) project, {
  int budget = kRetopoOverlayFaceBudget,
}) {
  final at = Vector3.zero();
  final faces = <List<Offset>>[];
  for (
    var face = 0;
    face < mesh.faceSlotCount && faces.length < budget;
    face++
  ) {
    if (!mesh.isFaceAlive(face)) continue;
    final corners = <Offset?>[];
    mesh.forEachHalfEdge(face, (int half) {
      mesh.positionOf(mesh.originOf(half), at);
      toWorld.transform3(at);
      corners.add(project(at));
    });
    if (corners.length < 3 || corners.contains(null)) continue;
    faces.add(corners.cast<Offset>());
  }
  return faces;
}

/// [corners] on the glass, for the quad being placed. Stops at the first one
/// the camera cannot see, so the painter never closes a polygon through it.
List<Offset> retopoCornersOnScreen(
  List<Vector3> corners,
  Offset? Function(Vector3 world) project,
) => <Offset>[
  for (final Offset? each
      in corners.map(project).takeWhile((Offset? it) => it != null))
    each!,
];
