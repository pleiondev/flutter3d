/// What is selected, and the walks that turn one selection into another.
///
/// Two fixtures carry most of it. A torus is the shape where every vertex joins
/// four edges and every face is a quad, so loops and rings run all the way round
/// and their length is known before the code says anything; a cube is the shape
/// where neither is true, and stopping is the right answer. A grid is what shows
/// what happens at an edge of the world.
library;

import 'dart:math' as math;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A torus of [major] segments round and [minor] across, all quads, every
/// vertex joining four edges.
EditMesh torus({int major = 8, int minor = 8}) {
  final points = <Vector3>[];
  for (var i = 0; i < major; i++) {
    final u = 2 * math.pi * i / major;
    for (var j = 0; j < minor; j++) {
      final v = 2 * math.pi * j / minor;
      final ring = 2 + math.cos(v);
      points.add(Vector3(ring * math.cos(u), math.sin(v), ring * math.sin(u)));
    }
  }
  int at(int i, int j) => (i % major) * minor + (j % minor);
  final faces = <List<int>>[
    for (var i = 0; i < major; i++)
      for (var j = 0; j < minor; j++)
        <int>[at(i, j), at(i, j + 1), at(i + 1, j + 1), at(i + 1, j)],
  ];
  return EditMesh.fromFaces(points, faces);
}

/// A flat sheet of [n] by [n] quads, so its outside is a boundary.
EditMesh grid(int n) {
  final points = <Vector3>[
    for (var y = 0; y <= n; y++)
      for (var x = 0; x <= n; x++) Vector3(x.toDouble(), y.toDouble(), 0),
  ];
  int at(int x, int y) => y * (n + 1) + x;
  final faces = <List<int>>[
    for (var y = 0; y < n; y++)
      for (var x = 0; x < n; x++)
        <int>[at(x, y), at(x + 1, y), at(x + 1, y + 1), at(x, y + 1)],
  ];
  return EditMesh.fromFaces(points, faces);
}

/// Some half-edge of [face] running out of [from].
int halfEdgeFrom(EditMesh mesh, int face, int from) {
  var found = EditMesh.none;
  mesh.forEachHalfEdge(face, (int half) {
    if (mesh.originOf(half) == from) found = half;
  });
  return found;
}

void main() {
  group('a selection is a value', () {
    test('the numbers come out sorted and once each', () {
      final selection = Selection.of(ElementLevel.face, <int>[5, 1, 5, 3]);

      expect(selection.ids, <int>[1, 3, 5]);
      expect(selection.length, 3);
      expect(selection.contains(3), isTrue);
      expect(selection.contains(4), isFalse);
      // "Nothing selected" is a number too, and asking whether it is in the
      // list has to answer no rather than search for -1.
      expect(selection.contains(EditMesh.none), isFalse);
      // What the sorting is for — a binary search — no test here can tell
      // apart from a linear scan, and saying otherwise would be a comment
      // making a claim the assertions do not carry. The order is what a
      // caller can see: it selected 5, 1, 5, 3 and gets 1, 3, 5.
    });

    test('the active element has to be one of them', () {
      expect(Selection.of(ElementLevel.face, <int>[1, 2], active: 2).active, 2);
      expect(
        Selection.of(ElementLevel.face, <int>[1, 2], active: 7).active,
        EditMesh.none,
      );
    });

    test('the active element survives an operation that keeps it', () {
      final selection = Selection.of(ElementLevel.vertex, <int>[
        1,
        2,
        3,
      ], active: 2);

      expect(
        selection
            .difference(Selection.of(ElementLevel.vertex, <int>[3]))
            .active,
        2,
      );
      // And is dropped by one that does not, rather than pointing at something
      // no longer selected — which is the state a tool would act on blindly.
      expect(
        selection
            .difference(Selection.of(ElementLevel.vertex, <int>[2]))
            .active,
        EditMesh.none,
      );
    });

    test('clicking one of the selected elements makes it the active one', () {
      final selection = Selection.of(ElementLevel.face, <int>[1, 2, 3]);

      expect(selection.withActive(2).active, 2);
      expect(selection.withActive(2).ids, selection.ids);
      // And clicking something outside the selection does not quietly add it:
      // that is a different gesture, and a tool pivoting on the active element
      // would otherwise pivot on something nobody selected.
      expect(selection.withActive(9).active, EditMesh.none);
    });

    test('the set operations do what their names say', () {
      final a = Selection.of(ElementLevel.edge, <int>[1, 2, 3]);
      final b = Selection.of(ElementLevel.edge, <int>[3, 4]);

      expect(a.union(b).ids, <int>[1, 2, 3, 4]);
      expect(a.difference(b).ids, <int>[1, 2]);
      expect(a.intersection(b).ids, <int>[3]);
      expect(a.toggle(b).ids, <int>[1, 2, 4]);
    });
  });

  group('edge loops', () {
    test('a torus loops all the way round and stops there', () {
      final mesh = torus();
      expect(mesh.eulerCharacteristic, 0, reason: 'a torus, not a sphere');

      final loop = Selection.edgeLoop(mesh, mesh.halfEdgeOf(0));

      // Eight quads round, so eight edges in line.
      expect(loop.length, 8);
      expect(loop.level, ElementLevel.edge);
      expect(loop.active, mesh.edgeOf(mesh.halfEdgeOf(0)));
    });

    test(
      'a cube stops at the first corner, because three edges meet there',
      () {
        final mesh = EditMesh.cuboid();

        final loop = Selection.edgeLoop(mesh, mesh.halfEdgeOf(0));

        // Mutation: take the edge two rotations along whatever the valency is,
        // and a cube's loop runs off round the box — which is what makes a loop
        // cut on a box cut something nobody pointed at.
        expect(loop.length, 1);
      },
    );

    test('a loop across a sheet stops at its edge', () {
      final mesh = grid(4);
      // A vertical edge inside the sheet: the loop along it runs the height.
      final face = 4; // row 1, column 0
      final vertical = halfEdgeFrom(mesh, face, 6);

      final loop = Selection.edgeLoop(mesh, vertical);

      // Mutation: rotate round the vertex without checking there is a live
      // face on the other side, and the walk reads a twin that is not there.
      // Counting the fan as four when it does not close is *not* what stops
      // this one — the rotation runs out first, and the count never gets asked.
      expect(loop.length, 4);
    });
  });

  group('edge rings', () {
    test('a torus rings all the way round', () {
      final mesh = torus();

      final ring = Selection.edgeRing(mesh, mesh.halfEdgeOf(0));

      expect(ring.length, 8);
    });

    test('a ring stops where the quads do', () {
      // Three quads in a strip with a triangle stuck on the end.
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(2, 0, 0),
          Vector3(3, 0, 0),
          Vector3(4, 0, 0),
          Vector3(0, 1, 0),
          Vector3(1, 1, 0),
          Vector3(2, 1, 0),
          Vector3(3, 1, 0),
        ],
        <List<int>>[
          <int>[0, 1, 6, 5],
          <int>[1, 2, 7, 6],
          <int>[2, 3, 8, 7],
          <int>[3, 4, 8],
        ],
      );

      final ring = Selection.edgeRing(mesh, halfEdgeFrom(mesh, 0, 1));

      // The four uprights of the strip, and not the triangle's two edges.
      // Mutation: drop the check that the face is a quad, and the ring steps
      // two along a three-sided face — which is the third edge, not an
      // opposite one, and the ring picks up an edge that is not across from
      // anything.
      expect(ring.length, 4);
    });
  });

  group('reading a region at another level', () {
    test('a face becomes its corners and comes back', () {
      final mesh = EditMesh.cuboid();
      final face = Selection.of(ElementLevel.face, <int>[0]);

      final corners = face.convertedTo(mesh, ElementLevel.vertex);
      expect(corners.length, 4);

      expect(corners.convertedTo(mesh, ElementLevel.face).ids, <int>[0]);
      expect(face.convertedTo(mesh, ElementLevel.edge).length, 4);
    });

    test('a region does not spill over its own edge', () {
      final mesh = grid(3);
      // The middle face of a three-by-three sheet.
      final middle = Selection.of(ElementLevel.face, <int>[4]);

      final edges = middle.convertedTo(mesh, ElementLevel.edge);

      // Mutation: take every edge touching a selected vertex instead of every
      // edge whose both ends are selected, and this is twelve — the four of
      // the face plus the eight running away from its corners.
      expect(edges.length, 4);
      expect(edges.convertedTo(mesh, ElementLevel.face).ids, <int>[4]);
    });

    test('the whole cube reads the same at every level', () {
      final mesh = EditMesh.cuboid();
      final everything = Selection.of(ElementLevel.vertex, <int>[
        for (var v = 0; v < mesh.vertexSlotCount; v++) v,
      ]);

      expect(everything.convertedTo(mesh, ElementLevel.face).length, 6);
      expect(everything.convertedTo(mesh, ElementLevel.edge).length, 12);
    });
  });

  group('growing and shrinking', () {
    test('a face grows to everything sharing a corner with it', () {
      final mesh = grid(3);

      final grown = Selection.of(ElementLevel.face, <int>[4]).grown(mesh);

      // Mutation: grow across shared edges instead of shared corners, and this
      // is five — the plus shape rather than the block, which is not what
      // "select more" does to a region somebody is widening by hand.
      expect(grown.length, 9);
    });

    test('shrinking takes back exactly what growing added', () {
      final mesh = grid(5);
      // The inner three-by-three block of a five-by-five sheet.
      final block = Selection.of(ElementLevel.face, <int>[
        for (var y = 1; y <= 3; y++)
          for (var x = 1; x <= 3; x++) y * 5 + x,
      ]);

      expect(block.grown(mesh).length, 25);
      // Mutation: keep an element when *any* neighbour is selected rather than
      // when all of them are, and shrinking a block does nothing at all.
      expect(block.shrunk(mesh).ids, <int>[12]);
    });

    test('a vertex grows along its edges, not to everything on its faces', () {
      final mesh = grid(5);
      // The vertex at (2, 2) of a six-by-six lattice of points.
      final grown = Selection.of(ElementLevel.vertex, <int>[14]).grown(mesh);

      // Four neighbours and itself. Mutation: grow a vertex by "shares a face"
      // and this is nine, so a soft selection or a proportional edit would
      // reach diagonally on the first ring.
      expect(grown.length, 5);
      expect(grown.contains(14), isTrue);
      expect(grown.contains(8), isTrue);
      expect(
        grown.contains(7),
        isFalse,
        reason: 'diagonals are not neighbours',
      );
    });

    test('shrinking a selection with nothing outside it changes nothing', () {
      final mesh = EditMesh.cuboid();
      final everything = Selection.of(ElementLevel.face, <int>[
        for (var f = 0; f < mesh.faceSlotCount; f++) f,
      ]);

      // There is no unselected face to be on the border of, so nothing is on
      // one. The alternative — treating the whole mesh as having an outside —
      // would empty a "select all" the moment somebody pressed shrink.
      expect(everything.shrunk(mesh).length, 6);
    });
  });

  group('linked', () {
    test('one face reaches its own island and stops', () {
      final one = EditMesh.cuboid();
      final points = <Vector3>[
        for (var v = 0; v < one.vertexSlotCount; v++) one.positionOf(v),
      ];
      final faces = <List<int>>[...one.faces()];
      final base = points.length;
      for (var v = 0; v < one.vertexSlotCount; v++) {
        points.add(one.positionOf(v)..add(Vector3(5, 0, 0)));
      }
      for (final face in one.faces()) {
        faces.add(<int>[for (final v in face) v + base]);
      }
      final mesh = EditMesh.fromFaces(points, faces);
      expect(mesh.faceCount, 12);

      final island = Selection.of(ElementLevel.face, <int>[0]).linked(mesh);

      // Mutation: grow once instead of walking, and this is five — the faces
      // touching the one clicked, which is not what "select linked" means.
      expect(island.length, 6);
      expect(
        island.contains(6),
        isFalse,
        reason: 'the other box is not joined',
      );
    });

    test('a vertex reaches every vertex of its island', () {
      final mesh = grid(4);

      final island = Selection.of(ElementLevel.vertex, <int>[0]).linked(mesh);

      expect(island.length, 25);
    });
  });

  group('the border of a region', () {
    test('one face of a cube is bordered by its four edges', () {
      final mesh = EditMesh.cuboid();

      final border = Selection.of(ElementLevel.face, <int>[0]).boundary(mesh);

      expect(border.level, ElementLevel.edge);
      expect(border.length, 4);
    });

    test('two faces share an edge that is not on the border', () {
      final mesh = grid(3);

      final border = Selection.of(ElementLevel.face, <int>[
        0,
        1,
      ]).boundary(mesh);

      // Six, not eight: the edge between them has a selected face on both
      // sides. Mutation: take every edge of every selected face and this is
      // eight, so an extrusion of two faces would wall in the seam between
      // them.
      expect(border.length, 6);
    });

    test('the border of a whole sheet is its own outside', () {
      final mesh = grid(3);
      final everything = Selection.of(ElementLevel.face, <int>[
        for (var f = 0; f < mesh.faceSlotCount; f++) f,
      ]);

      // Mutation: skip the edges with no face behind them and this is nothing
      // at all — the outside of the mesh is as much outside the region as a
      // neighbouring face is.
      expect(everything.boundary(mesh).length, 12);
    });
  });

  group('by material', () {
    test('a slot names the faces carrying it', () {
      final mesh = EditMesh.cuboid()..beginStep();
      mesh
        ..setMaterialSlot(0, 2)
        ..setMaterialSlot(3, 2)
        ..endStep();

      expect(Selection.byMaterialSlot(mesh, 2).ids, <int>[0, 3]);
      expect(Selection.byMaterialSlot(mesh, 0).length, 4);
      expect(Selection.byMaterialSlot(mesh, 9).isEmpty, isTrue);
    });

    test('a dead face carries nothing', () {
      final mesh = EditMesh.cuboid()..beginStep();
      mesh
        ..setMaterialSlot(0, 2)
        ..deleteFace(0)
        ..endStep();

      expect(Selection.byMaterialSlot(mesh, 2).isEmpty, isTrue);
    });
  });
}
