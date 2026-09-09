import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart';

/// A mesh with its topology still in it: faces of any valency, and half-edges
/// that know what is next to what.
///
/// **The spike, and it is labelled as one.** `MeshData` is a finished mesh —
/// vertices in the order a GPU wants them, with a corner duplicated once per
/// face normal that meets there — and every question a modeller asks is about
/// what that arrangement has thrown away: which faces share this edge, what
/// ring does this edge belong to, what is the loop around this face. So the
/// editable representation is a different one, and this file is the smallest
/// version of it that can answer the question the plan asks of it: can a cube
/// be built, a face extruded, and the result handed back to the engine, with
/// the numbers to say what that costs.
///
/// **What it does not do yet, said plainly so nothing here is mistaken for the
/// real thing.** An operation rebuilds the arrays rather than editing them in
/// place, there are no tombstones, no attribute layers beyond position, and no
/// persistent sharing between versions. Those are `mesh-10` through `mesh-13`
/// of `doc/model-editor-plan.md`; the rebuild is deliberate here, because one
/// of the answers the measurement may give is that rebuilding a whole mesh per
/// edit is affordable, and a spike that assumed otherwise could not report it.
///
/// The arrays are the shape the real one keeps: four `Int32List`s over
/// half-edges, one per face, one per vertex, and positions interleaved in a
/// `Float32List`. Every index is an index — no objects, no maps, nothing to
/// walk on a garbage collector's behalf.
final class EditMesh {
  EditMesh._(
    this._positions,
    this._vertexCount,
    this._origin,
    this._next,
    this._twin,
    this._halfEdgeFace,
    this._faceHalfEdge,
    this._outgoing,
  );

  /// Builds a mesh from points and faces, each face a list of point indices
  /// wound counter-clockwise seen from outside.
  ///
  /// Twins are matched by the pair of vertices an edge runs between: a
  /// half-edge from `a` to `b` twins with the one from `b` to `a`, and a
  /// half-edge with no partner is a boundary — [twinOf] answers [noHalfEdge]
  /// for it rather than pretending there is a face on the other side.
  ///
  /// A third face on one edge is a mesh this spike does not model, and it says
  /// so rather than silently keeping the last one it saw: repairing
  /// non-manifold input is `mesh-13`, and quietly dropping a face would make
  /// the Euler characteristic below agree with nothing anybody could see.
  factory EditMesh.fromFaces(List<Vector3> points, List<List<int>> faces) {
    final halfEdgeCount = faces.fold<int>(0, (sum, face) => sum + face.length);

    final positions = Float32List(points.length * 3);
    for (var i = 0; i < points.length; i++) {
      positions[i * 3] = points[i].x;
      positions[i * 3 + 1] = points[i].y;
      positions[i * 3 + 2] = points[i].z;
    }

    final origin = Int32List(halfEdgeCount);
    final next = Int32List(halfEdgeCount);
    final twin = Int32List(halfEdgeCount)..fillRange(0, halfEdgeCount, -1);
    final halfEdgeFace = Int32List(halfEdgeCount);
    final faceHalfEdge = Int32List(faces.length);
    final outgoing = Int32List(points.length)..fillRange(0, points.length, -1);

    // The pair a half-edge runs between, packed into one key so the match is a
    // map lookup rather than a scan of everything built so far. Vertices are
    // int32 by construction, so `from * count + to` cannot collide.
    final byPair = <int, int>{};

    var half = 0;
    for (var face = 0; face < faces.length; face++) {
      final loop = faces[face];
      if (loop.length < 3) {
        throw ArgumentError('face $face has ${loop.length} vertices');
      }
      faceHalfEdge[face] = half;
      for (var i = 0; i < loop.length; i++) {
        final from = loop[i];
        final to = loop[(i + 1) % loop.length];
        final index = half + i;

        origin[index] = from;
        next[index] = half + (i + 1) % loop.length;
        halfEdgeFace[index] = face;
        if (outgoing[from] < 0) outgoing[from] = index;

        final partner = byPair.remove(to * points.length + from);
        if (partner != null) {
          twin[index] = partner;
          twin[partner] = index;
        } else if (byPair.containsKey(from * points.length + to)) {
          throw ArgumentError(
            'the edge $from-$to is used twice the same way round, which is a '
            'third face on one edge rather than two',
          );
        } else {
          byPair[from * points.length + to] = index;
        }
      }
      half += loop.length;
    }

    return EditMesh._(
      positions,
      points.length,
      origin,
      next,
      twin,
      halfEdgeFace,
      faceHalfEdge,
      outgoing,
    );
  }

  /// An axis-aligned box of [size], centred on the origin, as six quads.
  ///
  /// Quads and not triangles, which is the whole reason this exists beside
  /// `CuboidShape`: that one builds what a GPU draws — twenty-four vertices,
  /// because a corner carries three different normals — and a loop cut through
  /// a triangulated cube has nothing to cut along.
  factory EditMesh.cuboid({Vector3? size}) {
    final half = (size ?? Vector3(1, 1, 1)) * 0.5;
    final points = <Vector3>[
      Vector3(-half.x, -half.y, -half.z),
      Vector3(half.x, -half.y, -half.z),
      Vector3(half.x, half.y, -half.z),
      Vector3(-half.x, half.y, -half.z),
      Vector3(-half.x, -half.y, half.z),
      Vector3(half.x, -half.y, half.z),
      Vector3(half.x, half.y, half.z),
      Vector3(-half.x, half.y, half.z),
    ];
    return EditMesh.fromFaces(points, <List<int>>[
      <int>[4, 5, 6, 7], // +Z
      <int>[1, 0, 3, 2], // −Z
      <int>[5, 1, 2, 6], // +X
      <int>[0, 4, 7, 3], // −X
      <int>[3, 7, 6, 2], // +Y
      <int>[0, 1, 5, 4], // −Y
    ]);
  }

  /// The answer [twinOf] gives for a half-edge on a boundary.
  static const int noHalfEdge = -1;

  final Float32List _positions;
  final int _vertexCount;
  final Int32List _origin;
  final Int32List _next;
  final Int32List _twin;
  final Int32List _halfEdgeFace;
  final Int32List _faceHalfEdge;
  final Int32List _outgoing;

  int get vertexCount => _vertexCount;
  int get faceCount => _faceHalfEdge.length;
  int get halfEdgeCount => _origin.length;

  /// Edges, counting a pair of twins once and a boundary half-edge once.
  int get edgeCount {
    var paired = 0;
    var boundary = 0;
    for (var i = 0; i < _twin.length; i++) {
      if (_twin[i] == noHalfEdge) {
        boundary++;
      } else {
        paired++;
      }
    }
    return paired ~/ 2 + boundary;
  }

  /// `V − E + F`, which is 2 for anything shaped like a sphere.
  ///
  /// The cheapest question that notices a mesh coming apart, and the one every
  /// operation below is tested with: a face left behind, a twin not rewired or
  /// a vertex nothing points at all move it.
  int get eulerCharacteristic => vertexCount - edgeCount + faceCount;

  /// The position of [vertex], as a new vector.
  Vector3 positionOf(int vertex) => Vector3(
    _positions[vertex * 3],
    _positions[vertex * 3 + 1],
    _positions[vertex * 3 + 2],
  );

  int originOf(int halfEdge) => _origin[halfEdge];
  int nextOf(int halfEdge) => _next[halfEdge];
  int twinOf(int halfEdge) => _twin[halfEdge];
  int faceOf(int halfEdge) => _halfEdgeFace[halfEdge];

  /// The half-edges of [face], in winding order.
  ///
  /// A generator rather than a list, because the loops are walked far more
  /// often than they are stored and a list per face per operation is the
  /// allocation this representation exists to avoid.
  Iterable<int> halfEdgesOf(int face) sync* {
    final start = _faceHalfEdge[face];
    var current = start;
    do {
      yield current;
      current = _next[current];
    } while (current != start);
  }

  /// The vertices of [face], in winding order.
  Iterable<int> verticesOf(int face) =>
      halfEdgesOf(face).map((int half) => _origin[half]);

  /// The face's normal by Newell's method, which is the one that answers for a
  /// quad whose four points are not quite in a plane.
  Vector3 normalOf(int face) {
    final normal = Vector3.zero();
    final loop = halfEdgesOf(face).toList(growable: false);
    for (var i = 0; i < loop.length; i++) {
      final current = positionOf(_origin[loop[i]]);
      final ahead = positionOf(_origin[loop[(i + 1) % loop.length]]);
      normal
        ..x += (current.y - ahead.y) * (current.z + ahead.z)
        ..y += (current.z - ahead.z) * (current.x + ahead.x)
        ..z += (current.x - ahead.x) * (current.y + ahead.y);
    }
    final length = normal.length;
    return length == 0 ? Vector3(0, 1, 0) : normal / length;
  }

  /// The area of [face], summed over the fan its normal projects onto.
  double areaOf(int face) {
    final loop = verticesOf(face).toList(growable: false);
    final anchor = positionOf(loop.first);
    var total = 0.0;
    for (var i = 1; i + 1 < loop.length; i++) {
      final b = positionOf(loop[i]) - anchor;
      final c = positionOf(loop[i + 1]) - anchor;
      total += b.cross(c).length * 0.5;
    }
    return total;
  }

  /// The volume the surface encloses, signed by winding.
  ///
  /// What a test uses to say an extrusion actually moved something: a face
  /// pushed out by `d` adds `area × d`, and an extrusion that pushed the wrong
  /// way, or left the original face behind, does not.
  double get signedVolume {
    var total = 0.0;
    for (var face = 0; face < faceCount; face++) {
      final loop = verticesOf(face).toList(growable: false);
      final anchor = positionOf(loop.first);
      for (var i = 1; i + 1 < loop.length; i++) {
        final b = positionOf(loop[i]);
        final c = positionOf(loop[i + 1]);
        total += anchor.dot(b.cross(c)) / 6.0;
      }
    }
    return total;
  }

  /// Every face as a list of vertex indices, which is what an operation edits
  /// and [EditMesh.fromFaces] reads back.
  List<List<int>> faces() => <List<int>>[
    for (var face = 0; face < faceCount; face++)
      verticesOf(face).toList(growable: false),
  ];

  /// Pushes [face] out along its own normal by [distance], walling in the gap.
  ///
  /// The face keeps its winding and its valency and arrives on new vertices;
  /// the old ones stay where they were, joined to the new ones by one quad per
  /// edge. On a closed mesh the characteristic does not move: a quad face
  /// gains four vertices, eight edges and four faces.
  ///
  /// The lifted face is renumbered: the faces that were kept come first in
  /// their old order, then the lifted one, then the walls. So extruding face
  /// `f` of a mesh with `n` faces leaves the lifted face at `n - 1`, which is
  /// what a caller extrudes again to build a step.
  ///
  /// Rebuilt rather than rewired, for the reason the class doc gives — this is
  /// the spike, and `mesh-23` is the operation.
  EditMesh extrudeFace(int face, double distance) {
    final loop = verticesOf(face).toList(growable: false);
    final offset = normalOf(face) * distance;

    final points = <Vector3>[
      for (var i = 0; i < vertexCount; i++) positionOf(i),
    ];
    // Indexed by position in the loop rather than by vertex, so a loop that
    // visits one vertex twice still gets two new ones.
    final base = points.length;
    final lifted = <int>[for (var i = 0; i < loop.length; i++) base + i];
    for (final vertex in loop) {
      points.add(positionOf(vertex) + offset);
    }

    final rebuilt = <List<int>>[
      for (var f = 0; f < faceCount; f++)
        if (f != face) verticesOf(f).toList(growable: false),
      lifted,
      // One quad per edge of the loop, wound so its normal points outwards:
      // along the original edge, up, back, and down.
      for (var i = 0; i < loop.length; i++)
        <int>[
          loop[i],
          loop[(i + 1) % loop.length],
          lifted[(i + 1) % loop.length],
          lifted[i],
        ],
    ];
    return EditMesh.fromFaces(points, rebuilt);
  }

  /// The mesh a renderer can draw: triangles, with one vertex per corner so
  /// every face keeps its own flat normal.
  ///
  /// A fan from the first vertex of each face, which is right for the convex
  /// faces a primitive is made of and wrong for an L-shaped n-gon — `mesh-15`
  /// is the triangulation that is not.
  MeshData toMeshData({VertexLayout layout = VertexLayout.standard}) {
    final builder = MeshBuilder(
      layout,
      reserveVertices: halfEdgeCount,
      reserveIndices: halfEdgeCount * 3,
    );
    for (var face = 0; face < faceCount; face++) {
      final normal = normalOf(face);
      final corners = <int>[
        for (final vertex in verticesOf(face))
          builder.addVertex(
            position: positionOf(vertex),
            normal: normal,
            texcoord: Vector2.zero(),
          ),
      ];
      for (var i = 1; i + 1 < corners.length; i++) {
        builder.addTriangle(corners[0], corners[i], corners[i + 1]);
      }
    }
    return builder.build();
  }

  /// Throws unless the arrays agree with each other.
  ///
  /// **The invariant, not the shape.** Every one of these has been broken by an
  /// operation at some point in some modeller: a `next` that leaves the face it
  /// started in, a twin that is not mutual, an `outgoing` left pointing at a
  /// half-edge that now starts somewhere else. Each is silent until a loop walk
  /// runs forever or a picked edge belongs to the wrong face.
  void validate() {
    for (var half = 0; half < halfEdgeCount; half++) {
      final twin = _twin[half];
      if (twin != noHalfEdge) {
        if (_twin[twin] != half) {
          throw StateError(
            'half-edge $half twins $twin, which twins ${_twin[twin]}',
          );
        }
        if (_origin[_next[half]] != _origin[twin]) {
          throw StateError(
            'half-edge $half and its twin do not run between '
            'the same two vertices',
          );
        }
      }
      if (_halfEdgeFace[_next[half]] != _halfEdgeFace[half]) {
        throw StateError('next of $half leaves its face');
      }
    }
    for (var face = 0; face < faceCount; face++) {
      var walked = 0;
      for (final _ in halfEdgesOf(face)) {
        walked++;
        if (walked > halfEdgeCount) {
          throw StateError('the loop of face $face does not close');
        }
      }
      if (walked < 3) throw StateError('face $face has $walked half-edges');
    }
    for (var vertex = 0; vertex < vertexCount; vertex++) {
      final out = _outgoing[vertex];
      if (out == noHalfEdge) throw StateError('vertex $vertex is in no face');
      if (_origin[out] != vertex) {
        throw StateError('outgoing of $vertex starts at ${_origin[out]}');
      }
    }
  }
}
