/// `ux-39`'s own bridge: two open borders joined by a ring of quads.
///
///     dart test test/bridge_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Two squares facing each other, four metres apart — the shape a bridge is
/// for, and the smallest one there is.
(EditMesh, Selection) _twoBorders() {
  final mesh = EditMesh.empty()..beginStep();
  final low = <int>[
    mesh.addVertex(Vector3(-1, 0, -1)),
    mesh.addVertex(Vector3(1, 0, -1)),
    mesh.addVertex(Vector3(1, 0, 1)),
    mesh.addVertex(Vector3(-1, 0, 1)),
  ];
  final high = <int>[
    mesh.addVertex(Vector3(-1, 4, -1)),
    mesh.addVertex(Vector3(1, 4, -1)),
    mesh.addVertex(Vector3(1, 4, 1)),
    mesh.addVertex(Vector3(-1, 4, 1)),
  ];
  mesh
    ..addFace(low)
    ..addFace(high.reversed.toList())
    ..endStep();
  final borders = <int>[
    for (var half = 0; half < mesh.halfEdgeSlotCount; half++)
      if (!mesh.hasLiveTwin(half)) half,
  ];
  return (mesh, Selection.of(ElementLevel.edge, borders));
}

void main() {
  test('two four-edge borders give four quads', () {
    final (EditMesh mesh, Selection borders) = _twoBorders();
    mesh.beginStep();
    final OpResult result = bridgeLoops(mesh, borders);
    mesh.endStep();

    expect(result.reason, isNull);
    // The row's own acceptance. Mutation: build a triangle fan between the
    // two rims instead, which is what "join these" looks like if the pairing
    // is dropped — eight faces, and every one of them a sliver.
    expect(result.selection.ids, hasLength(4));
    for (final int face in result.selection.ids) {
      expect(mesh.valencyOf(face), 4);
    }
    expect(mesh.faceCount, 6);
    mesh.validate();
  });

  test('and the result is closed: no border edge is left anywhere', () {
    final (EditMesh mesh, Selection borders) = _twoBorders();
    mesh.beginStep();
    bridgeLoops(mesh, borders);
    mesh.endStep();

    // **Mutation: weld the new quads to the borders and not to each other.**
    // The mesh then has eight border edges running up the sides, which every
    // exporter and every check downstream reads as four holes.
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      if (!mesh.isFaceAlive(face)) continue;
      mesh.forEachHalfEdge(face, (int half) {
        expect(mesh.hasLiveTwin(half), isTrue, reason: 'half-edge $half');
      });
    }
    mesh.validate();
  });

  test('the ring is joined corner to nearest corner, not index to index', () {
    final (EditMesh mesh, Selection borders) = _twoBorders();
    mesh.beginStep();
    final OpResult result = bridgeLoops(mesh, borders);
    mesh.endStep();

    // Each quad has two corners on the floor and two on the ceiling, and its
    // two floor corners are neighbours on the floor's own square. A twisted
    // pairing gives quads whose corners are diagonal from each other, which
    // shows up as a side longer than the square is wide.
    //
    // **Mutation: pair `a[0]` with `b[0]`.** A border has no natural first
    // corner — the one a selection starts at is an accident of half-edge
    // numbering — so the ring comes out twisted whenever the accident does
    // not line up.
    final here = Vector3.zero();
    final there = Vector3.zero();
    for (final int face in result.selection.ids) {
      final corners = <int>[];
      mesh.forEachVertex(face, corners.add);
      for (var i = 0; i < corners.length; i++) {
        mesh.positionOf(corners[i], here);
        mesh.positionOf(corners[(i + 1) % corners.length], there);
        // Two metres along the square, four between the floor and the
        // ceiling; a diagonal would be more than four.
        expect(here.distanceTo(there), lessThanOrEqualTo(4.0 + 1e-6));
      }
    }
  });

  test('a closed edge refuses rather than guessing which face to cut', () {
    final mesh = EditMesh.cuboid();
    final int edge = mesh.edgeOf(mesh.halfEdgeOf(0));
    final OpResult result = bridgeLoops(
      mesh,
      Selection.of(ElementLevel.edge, <int>[edge]),
    );

    expect(result.reason, contains('open borders'));
    expect(mesh.faceCount, 6);
  });

  test('borders of different lengths refuse, and say both numbers', () {
    final mesh = EditMesh.empty()..beginStep();
    final square = <int>[
      mesh.addVertex(Vector3(-1, 0, -1)),
      mesh.addVertex(Vector3(1, 0, -1)),
      mesh.addVertex(Vector3(1, 0, 1)),
      mesh.addVertex(Vector3(-1, 0, 1)),
    ];
    final triangle = <int>[
      mesh.addVertex(Vector3(-1, 4, -1)),
      mesh.addVertex(Vector3(1, 4, -1)),
      mesh.addVertex(Vector3(0, 4, 1)),
    ];
    mesh
      ..addFace(square)
      ..addFace(triangle.reversed.toList())
      ..endStep();
    final borders = <int>[
      for (var half = 0; half < mesh.halfEdgeSlotCount; half++)
        if (!mesh.hasLiveTwin(half)) half,
    ];

    final OpResult result = bridgeLoops(
      mesh,
      Selection.of(ElementLevel.edge, borders),
    );

    // A refusal that names both numbers is a person one glance from knowing
    // what to do; "cannot bridge" is a person opening the manual.
    expect(result.reason, contains('4'));
    expect(result.reason, contains('3'));
    expect(mesh.faceCount, 2);
  });
}
