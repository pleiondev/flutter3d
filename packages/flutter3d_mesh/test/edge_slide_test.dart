/// `ux-39`'s own edge slide: a loop moved along the edges that cross it,
/// without changing a single face.
///
///     dart test test/edge_slide_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Three quads in a strip, so the middle two edges have rails on both
/// sides — the smallest mesh a slide has anywhere to go.
EditMesh _strip() => EditMesh.fromFaces(
  <Vector3>[
    Vector3(0, 0, 0),
    Vector3(1, 0, 0),
    Vector3(2, 0, 0),
    Vector3(3, 0, 0),
    Vector3(0, 1, 0),
    Vector3(1, 1, 0),
    Vector3(2, 1, 0),
    Vector3(3, 1, 0),
  ],
  <List<int>>[
    <int>[0, 1, 5, 4],
    <int>[1, 2, 6, 5],
    <int>[2, 3, 7, 6],
  ],
);

/// The vertex standing at ([x], [y]) — `fromFaces` welds and renumbers, so
/// the index a test hands it is not the index it comes back as.
int _at(EditMesh mesh, double x, double y) {
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    final Vector3 p = mesh.positionOf(v);
    if ((p.x - x).abs() < 1e-6 && (p.y - y).abs() < 1e-6) return v;
  }
  throw StateError('no vertex at $x, $y');
}

/// The edge between the vertices at ([ax], [ay]) and ([bx], [by]).
int _edgeBetween(EditMesh mesh, double ax, double ay, double bx, double by) {
  final int a = _at(mesh, ax, ay);
  final int b = _at(mesh, bx, by);
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    var found = EditMesh.none;
    mesh.forEachHalfEdge(face, (int half) {
      final int from = mesh.originOf(half);
      final int to = mesh.originOf(mesh.nextOf(half));
      if ((from == a && to == b) || (from == b && to == a)) {
        found = mesh.edgeOf(half);
      }
    });
    if (found != EditMesh.none) return found;
  }
  throw StateError('no edge between ($ax, $ay) and ($bx, $by)');
}

void main() {
  test('a slid vertex stays on its own edge', () {
    final mesh = _strip();
    final int edge = _edgeBetween(mesh, 1, 0, 1, 1);
    // Read before the slide: `_at` looks a vertex up by where it stands, and
    // after a slide it no longer stands there.
    final int low = _at(mesh, 1, 0);
    final int high = _at(mesh, 1, 1);

    mesh.beginStep();
    final OpResult result = slideEdges(
      mesh,
      Selection.of(ElementLevel.edge, <int>[edge]),
      amount: 0.5,
    );
    mesh.endStep();

    expect(result.reason, isNull);
    // The row's own acceptance, and the whole of what a slide promises: each
    // vertex is somewhere between where it was and one of its neighbours,
    // and nowhere else. **Mutation: move along the loop's own direction
    // instead of along the rails.** The vertices leave the surface, and the
    // faces either side of the loop stop being planar.
    expect(mesh.positionOf(low).x, closeTo(0.5, 1e-6));
    expect(mesh.positionOf(high).x, closeTo(0.5, 1e-6));
    expect(mesh.positionOf(low).y, closeTo(0.0, 1e-6));
    expect(mesh.positionOf(high).y, closeTo(1.0, 1e-6));
    mesh.validate();
  });

  test('and the sign picks the other rail', () {
    final mesh = _strip();
    final int edge = _edgeBetween(mesh, 1, 0, 1, 1);
    // Read before the slide: `_at` looks a vertex up by where it stands, and
    // after a slide it no longer stands there.
    final int low = _at(mesh, 1, 0);
    final int high = _at(mesh, 1, 1);

    mesh.beginStep();
    slideEdges(
      mesh,
      Selection.of(ElementLevel.edge, <int>[edge]),
      amount: -0.5,
    );
    mesh.endStep();

    // The two rails at vertex 1 run to 0 and to 2; the lower-numbered one is
    // forward, so backwards is towards 2. Mutation: take the absolute value
    // and always use the first rail — a drag then only ever moves the loop
    // one way, and the way back is an undo.
    expect(mesh.positionOf(low).x, closeTo(1.5, 1e-6));
    expect(mesh.positionOf(high).x, closeTo(1.5, 1e-6));
  });

  test('a full slide lands exactly on the neighbour, never past it', () {
    final mesh = _strip();
    final int edge = _edgeBetween(mesh, 1, 0, 1, 1);
    // Read before the slide: `_at` looks a vertex up by where it stands, and
    // after a slide it no longer stands there.
    final int low = _at(mesh, 1, 0);
    final int high = _at(mesh, 1, 1);

    mesh.beginStep();
    slideEdges(
      mesh,
      Selection.of(ElementLevel.edge, <int>[edge]),
      // Asked for two edges' worth; a vertex may travel one.
      amount: 2.0,
    );
    mesh.endStep();

    // Clamped, because a vertex slid past the end of its rail has left the
    // surface it belongs to — and a drag that runs off the end of the panel
    // is how somebody asks for that by accident.
    expect(mesh.positionOf(low).x, closeTo(0.0, 1e-6));
    expect(mesh.positionOf(high).x, closeTo(0.0, 1e-6));
  });

  test('nothing about the topology changes', () {
    final mesh = _strip();
    final int faces = mesh.faceCount;
    final int vertices = mesh.vertexCount;
    final int edges = mesh.edgeCount;

    mesh.beginStep();
    final OpResult result = slideEdges(
      mesh,
      Selection.of(ElementLevel.edge, <int>[_edgeBetween(mesh, 1, 0, 1, 1)]),
      amount: 0.3,
    );
    mesh.endStep();

    // **This is what separates a slide from every other way of moving a
    // loop.** Mutation: cut a new loop and delete the old one, which reaches
    // the same shape — and loses every UV, crease and material assignment
    // that was on the faces either side.
    expect(result.topologyChanged, isFalse);
    expect(mesh.faceCount, faces);
    expect(mesh.vertexCount, vertices);
    expect(mesh.edgeCount, edges);
  });

  test('a border edge has only one rail, and says so', () {
    final mesh = _strip();
    // The strip's own left-hand edge: its vertices have a rail to the right
    // and nothing to the left.
    final int edge = _edgeBetween(mesh, 0, 0, 0, 1);
    final int corner = _at(mesh, 0, 0);

    final OpResult result = slideEdges(
      mesh,
      Selection.of(ElementLevel.edge, <int>[edge]),
      amount: 0.3,
    );

    expect(result.reason, contains('two'));
    expect(mesh.positionOf(corner).x, closeTo(0.0, 1e-6));
  });
}
