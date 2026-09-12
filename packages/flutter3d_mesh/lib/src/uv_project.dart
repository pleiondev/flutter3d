/// Assigning UV coordinates to a face's own corners by projection — no
/// solved system, just a plane.
///
/// **The second chip instead of ABF++ — `pro-uv-03`.** `pro-uv-02`'s own
/// `lscm` solves a sparse system per island to keep angles as close to
/// undistorted as it can; this instead picks one plane and reads a corner's
/// UV straight off its world position projected onto it. Cheaper, and exact
/// rather than approximate on the one shape that matters most for it: a face
/// already parallel to the plane it is projected onto has zero stretch,
/// which is what every axis-aligned box (crates, walls, most hard-surface
/// work) already is.
library;

import 'package:vector_math/vector_math.dart';

import 'edit_mesh.dart';

/// Which plane [projectUv] reads a corner's UV from.
///
/// **A value class rather than an enum, so this list is not closed** — the
/// same reason `LightingModel` is one. A third projection (cylindrical,
/// spherical) is exactly the kind of thing a caller with its own unwrap
/// needs might add, and an enum in a published package would make that
/// somebody else's breaking change rather than an addition.
final class UvProjection {
  const UvProjection._(this._name);

  final String _name;

  /// One plane for the whole island, perpendicular to its own average
  /// normal — right for an island that is already close to flat.
  static const UvProjection planar = UvProjection._('planar');

  /// Each face projected onto whichever of the six cardinal planes its own
  /// normal points closest to — right for an island whose faces already
  /// point in one of six directions, the way a box's six sides do.
  static const UvProjection box = UvProjection._('box');

  @override
  String toString() => 'UvProjection.$_name';
}

/// Assigns a UV to every corner of every face in [island], writing through
/// [EditMesh.setUv] — `mesh-12`'s own per-corner layer, the one that can
/// hold a seam at all.
///
/// [island] is a caller's own group of faces — `pro-uv-02`'s `splitIslands`
/// is one way to get one, a plain selection is another — and nothing here
/// checks that the faces it names are connected or share a normal; [box]
/// tolerates either, [planar] only reads well off faces already close to
/// flat.
void projectUv(EditMesh mesh, List<int> island, UvProjection mode) {
  if (mode == UvProjection.planar) {
    _projectPlanar(mesh, island);
  } else {
    for (final face in island) {
      _projectFaceBox(mesh, face);
    }
  }
}

/// One shared plane, perpendicular to the island's own average normal.
///
/// **The average, not the first face's own** — an island bent slightly
/// across its own faces (an unwrap never asked to be perfectly flat) still
/// gets one plane closest to all of them, rather than one biased towards
/// whichever face happened to be named first.
void _projectPlanar(EditMesh mesh, List<int> island) {
  final normal = Vector3.zero();
  for (final face in island) {
    normal.add(mesh.normalOf(face));
  }
  if (normal.length2 == 0) normal.setValues(0, 1, 0);
  normal.normalize();

  // Any vector not near-parallel to `normal` gives a stable perpendicular
  // pair by Gram-Schmidt; the axis less aligned with `normal` is picked so
  // the subtraction below never fights against near-cancellation.
  final reference = normal.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
  final u = (reference - normal * reference.dot(normal))..normalize();
  final v = normal.cross(u);

  for (final face in island) {
    mesh.forEachHalfEdge(face, (int half) {
      final p = mesh.positionOf(mesh.originOf(half));
      mesh.setUv(half, Vector2(p.dot(u), p.dot(v)));
    });
  }
}

/// One face, onto whichever of the six cardinal planes its own normal is
/// closest to — the standard box/triplanar choice, and the one under which
/// an axis-aligned face (every face of a cuboid) reads its world-space edge
/// lengths straight into UV space with nothing lost.
void _projectFaceBox(EditMesh mesh, int face) {
  final n = mesh.normalOf(face);
  final ax = n.x.abs();
  final ay = n.y.abs();
  final az = n.z.abs();

  mesh.forEachHalfEdge(face, (int half) {
    final p = mesh.positionOf(mesh.originOf(half));
    final Vector2 uv;
    if (ax >= ay && ax >= az) {
      // Facing along X: read the other two axes. Flipped on +X so the two
      // opposite faces of a box do not mirror each other's texture.
      uv = Vector2(n.x >= 0 ? -p.z : p.z, p.y);
    } else if (ay >= ax && ay >= az) {
      uv = Vector2(p.x, n.y >= 0 ? -p.z : p.z);
    } else {
      uv = Vector2(n.z >= 0 ? p.x : -p.x, p.y);
    }
    mesh.setUv(half, uv);
  });
}
