/// Which way a face points, and which way a corner of it does.
///
/// **A face normal is arithmetic; a corner normal is a decision.** The face's
/// own normal is Newell over its loop and there is nothing to choose. What a
/// corner gets is the answer to "does this vertex look faceted or round from
/// here", and three separate things say no to averaging: the face is not marked
/// smooth, the edge between it and its neighbour is marked sharp, or the two
/// faces simply disagree by more than the angle the caller allows. Each exists
/// because the others cannot express it — a cylinder's cap is sharp against the
/// side while the side is smooth around itself, a box's every edge is hard
/// whatever the angle, and a mesh from a file has no flags at all and still has
/// to look right.
///
/// **Corners are grouped, not walked.** Asking each corner to walk the fan
/// around its vertex is quadratic in the valency, and a vertex where twelve
/// faces meet is not rare in a subdivided model. So one pass unions each corner
/// with the one across the edge it may average over, and a second pass adds
/// each face's normal into its group — every corner in a group ends with the
/// same answer, which is what a smooth fan *is*.
///
/// **The share a face gets is its angle at the corner.** Weighting by area or
/// not weighting at all makes the normal at a vertex depend on how the faces
/// around it happen to be cut: triangulate a quad and the corner it was fanned
/// from suddenly counts twice. The angle at the corner does not change when a
/// face is cut into two along a diagonal through it, so the normal does not
/// either.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';

/// Face and corner normals for a mesh, in buffers it keeps.
///
/// **One object rebuilt rather than a function returning lists.** Normals are
/// recomputed after every edit that moves a vertex — which, while somebody is
/// dragging one, is every frame — and a pair of fresh `Float32List`s per frame
/// on a 200 000-face mesh is nine megabytes a second of garbage for numbers
/// that are overwritten immediately.
final class MeshNormals {
  /// The angle beyond which two faces are taken to disagree, in radians.
  ///
  /// Thirty degrees is where the usual defaults sit: it keeps a cylinder of
  /// twenty-four sides round, and it breaks a box, which is what the two ends
  /// of the range look like.
  static const double defaultSmoothAngle = 30.0 * degrees2Radians;

  Float32List _faces = Float32List(0);
  Float32List _corners = Float32List(0);
  Float32List _sums = Float32List(0);
  Int32List _previous = Int32List(0);
  Int32List _group = Int32List(0);

  int _faceSlots = 0;
  int _halfEdgeSlots = 0;

  /// Three floats per face slot, unit length. Zero where the face is dead.
  ///
  /// **For a caller that walks every face and wants the array, not a vector
  /// per face.** The viewport's face-normal overlay (`view-12`) and the export
  /// checks (`mesh-27`) both do; a caller asking about one face wants
  /// [faceNormal] instead, and this stays because handing those two a
  /// `Vector3` allocation per face of a 200 000-face mesh is the cost the
  /// buffers exist to avoid.
  Float32List get faceNormals => _faces;

  /// Three floats per half-edge slot, unit length. Zero where the half-edge is
  /// on a dead face.
  Float32List get cornerNormals => _corners;

  /// The normal of [face], as a vector.
  Vector3 faceNormal(int face, [Vector3? out]) => (out ?? Vector3.zero())
    ..setValues(_faces[face * 3], _faces[face * 3 + 1], _faces[face * 3 + 2]);

  /// The normal at the corner [halfEdge] starts at, as a vector.
  Vector3 cornerNormal(int halfEdge, [Vector3? out]) => (out ?? Vector3.zero())
    ..setValues(
      _corners[halfEdge * 3],
      _corners[halfEdge * 3 + 1],
      _corners[halfEdge * 3 + 2],
    );

  /// Which smooth fan the corner [halfEdge] belongs to, as the number of one
  /// of its corners.
  ///
  /// **What a layout plan merges on.** Two corners of one vertex end up in the
  /// same fan exactly when they share a normal, so a plan deciding whether they
  /// can be one GPU vertex has the answer already and does not have to compare
  /// three floats and hope the arithmetic came out identical on both sides.
  int groupOf(int halfEdge) => _find(halfEdge);

  /// Recomputes both sets against [mesh].
  ///
  /// [smoothAngle] is in radians and is the widest disagreement two faces may
  /// have and still be averaged across.
  void build(EditMesh mesh, {double smoothAngle = defaultSmoothAngle}) {
    _resize(mesh);
    _buildFaceNormals(mesh);
    _buildPrevious(mesh);
    _groupCorners(mesh, math.cos(smoothAngle));
    _accumulate(mesh);
    _normalise(mesh);
  }

  /// Recomputes only what moving [vertices] can have changed, and answers how
  /// many corners that came to.
  ///
  /// **`pro-sc-01` measured this and both of its platforms missed both
  /// thresholds on it.** A sculpt stroke moves a few thousand vertices and
  /// then [build] recomputes every face normal, every fan and every corner of
  /// the whole mesh: on a 1.2M-triangle model, twenty thousand moved vertices
  /// pay for 1.2 million faces. Nothing about the far side of the model
  /// changed, and this is the call that says so.
  ///
  /// What can change is bounded and local. A face's normal moves only if one
  /// of its own vertices did. A corner's normal moves only if some face in its
  /// fan did — so the fans to rebuild are the fans at every vertex of every
  /// face touching a moved one, and nothing beyond that ring.
  ///
  /// **The boundary is where this goes wrong if it is written the obvious
  /// way.** [EditMesh.neighborsOf] rotates one way and stops where an edge has
  /// no twin, which on a boundary vertex is halfway round; a fan gathered that
  /// way is rebuilt from half its faces and comes back as a crease that is not
  /// there. [_forEachCornerAt] therefore walks back from where it started
  /// whenever the forward walk ran out, and `normals_partial_test.dart` holds
  /// the result to a whole [build], float for float, on a mesh with an open
  /// edge.
  ///
  /// **Positions only, and that is a contract rather than a hope.** This reads
  /// the loop links the last [build] walked, so it is for an edit that moved
  /// vertices and left the topology alone — a sculpt stroke, a gizmo drag, a
  /// shape-key blend. Anything that added, removed or relinked a face needs
  /// [build]. Slot counts that do not match what the last build saw are the
  /// cheap, certain half of that — a different mesh, or one that grew — and
  /// they fall back to the whole rebuild; a deletion that left the counts
  /// where they were is the caller's to know about.
  /// [touched], when given, is filled with every vertex whose fans were
  /// rebuilt — the moved ones and the ring around them. **A caller patching a
  /// vertex buffer needs this and not the list it passed in**:
  /// [MeshLayoutPlan.fillVerticesOf] writes the rows of the vertices it is
  /// given, and the rows carrying a changed normal are the ring's, not just
  /// the moved ones'. Filling only what moved leaves a seam of old lighting
  /// one vertex wide around every stroke.
  int rebuildAround(
    EditMesh mesh,
    Iterable<int> vertices, {
    double smoothAngle = defaultSmoothAngle,
    Set<int>? touched,
  }) {
    if (_faceSlots != mesh.faceSlotCount ||
        _halfEdgeSlots != mesh.halfEdgeSlotCount) {
      build(mesh, smoothAngle: smoothAngle);
      var live = 0;
      for (var face = 0; face < _faceSlots; face++) {
        if (!mesh.isFaceAlive(face)) continue;
        mesh.forEachHalfEdge(face, (int half) {
          live++;
          touched?.add(mesh.originOf(half));
        });
      }
      return live;
    }

    // The faces whose own normal can have moved: those with a moved vertex.
    final faces = <int>{};
    for (final int vertex in vertices) {
      _forEachCornerAt(mesh, vertex, (int half) {
        final face = mesh.faceOf(half);
        if (face != EditMesh.none && mesh.isFaceAlive(face)) faces.add(face);
      });
    }
    if (faces.isEmpty) return 0;

    final normal = Vector3.zero();
    for (final int face in faces) {
      mesh.normalOf(face, normal);
      _faces[face * 3] = normal.x;
      _faces[face * 3 + 1] = normal.y;
      _faces[face * 3 + 2] = normal.z;
    }

    // Every vertex of every such face — the ring whose fans now disagree with
    // what is in the buffers.
    final ring = touched ?? <int>{};
    for (final int face in faces) {
      mesh.forEachHalfEdge(face, (int half) {
        ring.add(mesh.originOf(half));
      });
    }

    // And every corner at every one of them. Whole fans, never part of one:
    // the grouping below resets each of these corners to stand alone, and a
    // fan left half-reset would be split down the middle.
    final corners = <int>{};
    for (final int vertex in ring) {
      _forEachCornerAt(mesh, vertex, (int half) {
        final face = mesh.faceOf(half);
        if (face != EditMesh.none && mesh.isFaceAlive(face)) corners.add(half);
      });
    }

    for (final int half in corners) {
      _group[half] = half;
      _sums[half * 3] = 0;
      _sums[half * 3 + 1] = 0;
      _sums[half * 3 + 2] = 0;
    }

    // A union only ever links two corners at the same vertex, and every corner
    // at every touched vertex is in `corners` — so no rebuilt corner can be
    // joined to a root left over from the last build.
    final cosLimit = math.cos(smoothAngle);
    for (final int half in corners) {
      final face = mesh.faceOf(half);
      if (_breaks(mesh, half, face, cosLimit)) continue;
      _union(half, mesh.nextOf(mesh.twinOf(half)));
    }

    final here = Vector3.zero();
    final ahead = Vector3.zero();
    final behind = Vector3.zero();
    for (final int half in corners) {
      final face = mesh.faceOf(half);
      mesh.positionOf(mesh.originOf(half), here);
      mesh.positionOf(mesh.originOf(mesh.nextOf(half)), ahead);
      mesh.positionOf(mesh.originOf(_previous[half]), behind);
      ahead.sub(here);
      behind.sub(here);
      final weight = math.atan2(ahead.cross(behind).length, ahead.dot(behind));
      final at = _find(half) * 3;
      _sums[at] += _faces[face * 3] * weight;
      _sums[at + 1] += _faces[face * 3 + 1] * weight;
      _sums[at + 2] += _faces[face * 3 + 2] * weight;
    }

    for (final int half in corners) {
      final face = mesh.faceOf(half);
      final at = _find(half) * 3;
      final x = _sums[at];
      final y = _sums[at + 1];
      final z = _sums[at + 2];
      final length = math.sqrt(x * x + y * y + z * z);
      if (length == 0) {
        _corners[half * 3] = _faces[face * 3];
        _corners[half * 3 + 1] = _faces[face * 3 + 1];
        _corners[half * 3 + 2] = _faces[face * 3 + 2];
        continue;
      }
      _corners[half * 3] = x / length;
      _corners[half * 3 + 1] = y / length;
      _corners[half * 3 + 2] = z / length;
    }

    return corners.length;
  }

  /// Every corner at [vertex], both ways round, once each.
  ///
  /// The forward rotation `nextOf(twinOf(h))` comes back to where it started
  /// on an interior vertex, and that is how it knows it is finished. On a
  /// boundary vertex it runs into the edge with no twin and stops with half
  /// the fan unvisited — so the other half is walked back from the start,
  /// through the half-edge before each one on its own loop.
  void _forEachCornerAt(EditMesh mesh, int vertex, void Function(int) visit) {
    final start = mesh.outgoingOf(vertex);
    if (start == EditMesh.none) return;

    var half = start;
    while (true) {
      visit(half);
      if (!mesh.hasLiveTwin(half)) break;
      half = mesh.nextOf(mesh.twinOf(half));
      // All the way round: an interior vertex, and there is no other half.
      if (half == start) return;
    }

    half = start;
    while (true) {
      final back = _previous[half];
      if (!mesh.hasLiveTwin(back)) break;
      half = mesh.twinOf(back);
      // Unreachable on a sane twin table — the forward walk would have come
      // back round instead of stopping — and a cheap guard against spinning
      // forever on a broken one.
      if (half == start) break;
      visit(half);
    }
  }

  void _resize(EditMesh mesh) {
    _faceSlots = mesh.faceSlotCount;
    _halfEdgeSlots = mesh.halfEdgeSlotCount;
    if (_faces.length < _faceSlots * 3) _faces = Float32List(_faceSlots * 3);
    if (_corners.length < _halfEdgeSlots * 3) {
      _corners = Float32List(_halfEdgeSlots * 3);
      _sums = Float32List(_halfEdgeSlots * 3);
      _previous = Int32List(_halfEdgeSlots);
      _group = Int32List(_halfEdgeSlots);
    }
    // Cleared rather than trusted: a slot that belonged to a face deleted since
    // the last build would otherwise answer with the normal that face had.
    _faces.fillRange(0, _faceSlots * 3, 0);
    _corners.fillRange(0, _halfEdgeSlots * 3, 0);
    _sums.fillRange(0, _halfEdgeSlots * 3, 0);
  }

  void _buildFaceNormals(EditMesh mesh) {
    final normal = Vector3.zero();
    for (var face = 0; face < _faceSlots; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      mesh.normalOf(face, normal);
      _faces[face * 3] = normal.x;
      _faces[face * 3 + 1] = normal.y;
      _faces[face * 3 + 2] = normal.z;
    }
  }

  /// The half-edge before each one on its own loop.
  ///
  /// The mesh does not store it — a loop is singly linked, and a second link
  /// per half-edge is four bytes each that only this and a handful of edits
  /// ever read. Walking the loops once here costs one pass over the same
  /// half-edges the next three passes go over anyway.
  void _buildPrevious(EditMesh mesh) {
    for (var face = 0; face < _faceSlots; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      mesh.forEachHalfEdge(face, (int half) {
        _previous[mesh.nextOf(half)] = half;
      });
    }
  }

  /// Which corner belongs with which, as a forest of half-edge numbers.
  void _groupCorners(EditMesh mesh, double cosLimit) {
    for (var half = 0; half < _halfEdgeSlots; half++) {
      _group[half] = half;
    }
    for (var face = 0; face < _faceSlots; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      mesh.forEachHalfEdge(face, (int half) {
        if (_breaks(mesh, half, face, cosLimit)) return;
        // Both of these start at the same vertex: `half` runs from it, its twin
        // runs back into it, and the twin's successor leaves it again into the
        // neighbouring face. Rotating the other way round the vertex crosses
        // the same edges seen from the other side, so one direction unions the
        // whole fan.
        _union(half, mesh.nextOf(mesh.twinOf(half)));
      });
    }
  }

  /// Whether the edge [half] lies on stops the two faces sharing a normal.
  bool _breaks(EditMesh mesh, int half, int face, double cosLimit) {
    final twin = mesh.twinOf(half);
    if (twin == EditMesh.none) return true;
    final other = mesh.faceOf(twin);
    if (other == EditMesh.none || !mesh.isFaceAlive(other)) return true;
    if (!mesh.faceHas(face, FaceFlags.smooth)) return true;
    if (!mesh.faceHas(other, FaceFlags.smooth)) return true;
    if (mesh.edgeHas(half, EdgeFlags.sharp)) return true;
    final dot =
        _faces[face * 3] * _faces[other * 3] +
        _faces[face * 3 + 1] * _faces[other * 3 + 1] +
        _faces[face * 3 + 2] * _faces[other * 3 + 2];
    return dot < cosLimit;
  }

  int _find(int half) {
    var root = half;
    while (_group[root] != root) {
      root = _group[root];
    }
    // Path halving on the way back, which keeps the walks flat without a second
    // loop or a rank array.
    var walk = half;
    while (_group[walk] != root) {
      final parent = _group[walk];
      _group[walk] = root;
      walk = parent;
    }
    return root;
  }

  void _union(int a, int b) {
    final rootA = _find(a);
    final rootB = _find(b);
    if (rootA != rootB) _group[rootB] = rootA;
  }

  /// Adds each face's normal into its corners' groups, weighted by the angle
  /// the face turns through at that corner.
  void _accumulate(EditMesh mesh) {
    final here = Vector3.zero();
    final ahead = Vector3.zero();
    final behind = Vector3.zero();
    for (var face = 0; face < _faceSlots; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      mesh.forEachHalfEdge(face, (int half) {
        mesh.positionOf(mesh.originOf(half), here);
        mesh.positionOf(mesh.originOf(mesh.nextOf(half)), ahead);
        mesh.positionOf(mesh.originOf(_previous[half]), behind);
        ahead.sub(here);
        behind.sub(here);
        // atan2 of the cross against the dot rather than acos of the dot: the
        // two edges at a corner are very nearly parallel often enough — a loop
        // cut leaves them that way — and acos there is all rounding error. It
        // also needs no guard: two coincident neighbours give atan2(0, 0),
        // which is zero, and a corner that weighs nothing adds nothing.
        final weight = math.atan2(
          ahead.cross(behind).length,
          ahead.dot(behind),
        );
        final at = _find(half) * 3;
        _sums[at] += _faces[face * 3] * weight;
        _sums[at + 1] += _faces[face * 3 + 1] * weight;
        _sums[at + 2] += _faces[face * 3 + 2] * weight;
      });
    }
  }

  void _normalise(EditMesh mesh) {
    for (var face = 0; face < _faceSlots; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      mesh.forEachHalfEdge(face, (int half) {
        final at = _find(half) * 3;
        final x = _sums[at];
        final y = _sums[at + 1];
        final z = _sums[at + 2];
        final length = math.sqrt(x * x + y * y + z * z);
        if (length == 0) {
          // A fan whose faces cancel — two coincident faces wound against each
          // other, which a bad import leaves behind. The face's own normal is
          // wrong for nobody and lets the mesh still be drawn.
          _corners[half * 3] = _faces[face * 3];
          _corners[half * 3 + 1] = _faces[face * 3 + 1];
          _corners[half * 3 + 2] = _faces[face * 3 + 2];
          return;
        }
        _corners[half * 3] = x / length;
        _corners[half * 3 + 1] = y / length;
        _corners[half * 3 + 2] = z / length;
      });
    }
  }
}
