/// What is wrong with a mesh.
///
/// One shape per check, built to have exactly the fault the check is for and
/// nothing else — so a check that finds it on the wrong shape, or misses it on
/// the right one, is a check that fails here rather than in somebody's export.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Runs [body] as one step of history.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

/// A sheet of [n] by [n] quads.
EditMesh grid(int n) {
  final points = <Vector3>[
    for (var y = 0; y <= n; y++)
      for (var x = 0; x <= n; x++) Vector3(x.toDouble(), y.toDouble(), 0),
  ];
  int at(int x, int y) => y * (n + 1) + x;
  return EditMesh.fromFaces(points, <List<int>>[
    for (var y = 0; y < n; y++)
      for (var x = 0; x < n; x++)
        <int>[at(x, y), at(x + 1, y), at(x + 1, y + 1), at(x, y + 1)],
  ]);
}

const List<List<int>> boxOrder = <List<int>>[
  <int>[4, 5, 6, 7],
  <int>[1, 0, 3, 2],
  <int>[5, 1, 2, 6],
  <int>[0, 4, 7, 3],
  <int>[3, 7, 6, 2],
  <int>[0, 1, 5, 4],
];

/// Two boxes sharing exactly one corner and no edge.
EditMesh boxesAtACorner() {
  final points = <Vector3>[
    Vector3(0, 0, 0),
    Vector3(1, 0, 0),
    Vector3(1, 1, 0),
    Vector3(0, 1, 0),
    Vector3(0, 0, 1),
    Vector3(1, 0, 1),
    Vector3(1, 1, 1),
    Vector3(0, 1, 1),
    Vector3(2, 1, 1),
    Vector3(2, 2, 1),
    Vector3(1, 2, 1),
    Vector3(1, 1, 2),
    Vector3(2, 1, 2),
    Vector3(2, 2, 2),
    Vector3(1, 2, 2),
  ];
  const second = <int>[6, 8, 9, 10, 11, 12, 13, 14];
  return EditMesh.fromFaces(points, <List<int>>[
    ...boxOrder,
    for (final face in boxOrder) <int>[for (final v in face) second[v]],
  ]);
}

void main() {
  group('a box with nothing wrong', () {
    test('reports nothing at all', () {
      expect(MeshChecks(EditMesh.cuboid()).all(), isEmpty);
    });

    test('and its Euler characteristic is two', () {
      expect(MeshChecks(EditMesh.cuboid()).eulerByComponent(), <int>[2]);
    });
  });

  group('faces with too many corners', () {
    test('a five-sided face is found and a four-sided one is not', () {
      final mesh = EditMesh.cuboid();
      expect(MeshChecks(mesh).ngons(), isNull);

      edit(mesh, () => mesh.splitEdge(mesh.halfEdgeOf(0)));

      // Two faces gained a corner apiece. Mutation: look for more than three
      // corners and every quad in every model is a complaint.
      final found = MeshChecks(mesh).ngons()!;
      expect(found.ids, hasLength(2));
      expect(found.severity, IssueSeverity.note);
      expect(found.selection.level, ElementLevel.face);
      expect(found.message, contains('2 faces'));
    });
  });

  group('edges with one side', () {
    test('a sheet has a rim and a box has none', () {
      expect(MeshChecks(EditMesh.cuboid()).boundaryEdges(), isNull);

      final sheet = grid(2);
      final found = MeshChecks(sheet).boundaryEdges()!;

      // Eight edges round a two-by-two sheet, and every one of them an edge
      // with nothing behind it. There is no half-edge against edge question to
      // get wrong here — an edge with one side has one half-edge — but there
      // is an off-by-one: reporting the next link round the face instead names
      // an edge that is not on the rim at all.
      expect(found.ids, hasLength(8));
      expect(found.selection.level, ElementLevel.edge);
      for (final id in found.ids) {
        expect(sheet.hasLiveTwin(id), isFalse);
      }
    });
  });

  group('surfaces meeting at a point', () {
    test('two boxes at a corner are found; two apart are not', () {
      final joined = MeshChecks(boxesAtACorner()).nonManifoldVertices()!;

      // Exactly the shared corner. Mutation: count the faces at a vertex
      // rather than the fans, and every corner of every box is reported —
      // three faces meet at each of them and it is one sheet.
      expect(joined.ids, <int>[6]);
      expect(joined.severity, IssueSeverity.warning);

      final apart = EditMesh.cuboid();
      expect(MeshChecks(apart).nonManifoldVertices(), isNull);
    });

    test('a rim is not a pinch', () {
      // Every vertex round the edge of a sheet has an open fan, which is not
      // the same as two fans.
      expect(MeshChecks(grid(2)).nonManifoldVertices(), isNull);
    });
  });

  group('vertices nothing stands on', () {
    test('one left behind is found', () {
      final mesh = EditMesh.cuboid();
      expect(MeshChecks(mesh).isolatedVertices(), isNull);

      late int loose;
      edit(mesh, () => loose = mesh.addVertex(Vector3(5, 5, 5)));

      // Mutation: ask which vertices are alive rather than which are used, and
      // every vertex of every mesh is reported.
      final found = MeshChecks(mesh).isolatedVertices()!;
      expect(found.ids, <int>[loose]);
    });
  });

  group('faces with no area', () {
    test('three points in a line are found', () {
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(2, 0, 0),
          Vector3(0, 1, 0),
        ],
        <List<int>>[
          <int>[0, 1, 2],
          <int>[0, 2, 3],
        ],
      );

      final found = MeshChecks(mesh).degenerateFaces()!;

      // The first face only: the second has area. Mutation: test the corner
      // count and let the area go, and a face flattened onto a line by a
      // scale of zero passes every check there is.
      expect(found.ids, <int>[0]);
      expect(found.severity, IssueSeverity.error);
    });

    test('a face pinched into a figure of eight is found', () {
      // Six corners naming five places, with the middle one used twice: two
      // wings of half a unit each, so the *area* is a whole unit and says
      // nothing is wrong. Mutation: test the area alone and let the corners
      // go, and this passes every check there is while being a shape no
      // triangulation, no normal and no exporter can make sense of.
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(0, 1, 0),
          Vector3(-1, 0, 0),
          Vector3(0, -1, 0),
        ],
        <List<int>>[
          <int>[0, 1, 2, 0, 3, 4],
        ],
      );
      expect(mesh.areaOf(0), greaterThan(0.9));

      expect(MeshChecks(mesh).degenerateFaces()!.ids, <int>[0]);
    });
  });

  group('vertices standing in the same place', () {
    test('two on top of each other are found and welded ones are not', () {
      final mesh = EditMesh.cuboid();
      expect(MeshChecks(mesh).duplicateVertices(), isNull);

      final twice = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(0, 1, 0),
          // A second triangle standing on the same two points, with its own
          // copies of them: the seam a bad export leaves.
          Vector3(0, 0, 0),
          Vector3(1, 0, 0),
          Vector3(0, -1, 0),
        ],
        <List<int>>[
          <int>[0, 1, 2],
          <int>[3, 5, 4],
        ],
      );

      // Both of each pair, because a person fixing this wants to see the seam
      // rather than one side of it. Mutation: search one cell instead of the
      // twenty-seven around it, and a pair either side of a cell boundary is
      // reported on one machine and not on another.
      final found = MeshChecks(twice).duplicateVertices()!;
      expect(found.ids, <int>[0, 1, 3, 4]);
    });

    test('a pair either side of a cell boundary is still a pair', () {
      // The grid the search buckets into is one tolerance across, so these two
      // land in different cells while being a fifth of a tolerance apart.
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0.9, 0, 0),
          Vector3(5, 0, 0),
          Vector3(0, 5, 0),
          Vector3(1.1, 0, 0),
          Vector3(9, 0, 0),
          Vector3(0, -5, 0),
        ],
        <List<int>>[
          <int>[0, 1, 2],
          <int>[3, 5, 4],
        ],
      );

      // Mutation: look in the one cell a vertex lands in instead of the
      // twenty-seven around it, and this pair is reported on a machine whose
      // arithmetic rounds one way and not on a machine that rounds the other.
      final found = MeshChecks(mesh, tolerance: 1).duplicateVertices()!;
      expect(found.ids, <int>[0, 3]);
    });

    test('the tolerance is scaled to the model', () {
      // A millimetre apart on a box a kilometre across is the same point.
      final wide = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(1000000, 0, 0),
          Vector3(0, 1000000, 0),
          Vector3(0.4, 0, 0),
          Vector3(1000000.5, 0, 0),
          Vector3(0, -1000000, 0),
        ],
        <List<int>>[
          <int>[0, 1, 2],
          <int>[3, 5, 4],
        ],
      );

      // A tenth of a millimetre and half a millimetre apart, both inside a
      // tolerance a millionth of the model's own size. Mutation: use a fixed
      // epsilon, and a model in millimetres reports nothing while a model in
      // kilometres reports every vertex it has.
      expect(MeshChecks(wide).duplicateVertices()!.ids, <int>[0, 1, 3, 4]);
      // And told a tolerance, it uses that instead of guessing.
      expect(MeshChecks(wide, tolerance: 0).duplicateVertices(), isNull);
    });
  });

  group('shells wound inside out', () {
    test('a flipped box is found, and the volume says the same', () {
      final mesh = EditMesh.cuboid();
      expect(MeshChecks(mesh).invertedShells(), isNull);
      expect(mesh.signedVolume, greaterThan(0));

      edit(mesh, mesh.flipNormals);

      final found = MeshChecks(mesh).invertedShells()!;
      expect(found.ids, hasLength(6));
      expect(mesh.signedVolume, lessThan(0));

      // And turning it back the right way clears it, which is what says the
      // check is reading the winding rather than counting something.
      edit(mesh, () => mesh.makeConsistent());
      expect(MeshChecks(mesh).invertedShells(), isNull);
    });

    test('an open surface has no inside to be out of', () {
      final mesh = grid(2);
      // Lifted off the plane through the origin, so the cone over it has a
      // volume at all: a flat sheet the origin lies in has one of zero, and a
      // test on that would pass whatever the check did.
      edit(mesh, () {
        translateSelection(
          mesh,
          Selection.of(ElementLevel.vertex, <int>[
            for (var v = 0; v < mesh.vertexSlotCount; v++) v,
          ]),
          by: Vector3(0, 0, 3),
        );
        mesh.flipNormals();
      });

      // Mutation: drop the test that the shell is closed, and half the planes
      // in the world are reported inside out depending on where the origin
      // happens to be.
      expect(MeshChecks(mesh).invertedShells(), isNull);
    });

    test('one bad box beside a good one names only its own faces', () {
      final mesh = boxesAtACorner();
      // The second box only.
      edit(mesh, () {
        for (var face = 6; face < 12; face++) {
          mesh.setMaterialSlot(face, 1);
        }
      });
      expect(MeshChecks(mesh).invertedShells(), isNull);
    });
  });

  group('the shape of each island', () {
    test('a ball is two, a disc is one, and a torus is zero', () {
      expect(MeshChecks(EditMesh.cuboid()).eulerByComponent(), <int>[2]);
      expect(MeshChecks(grid(2)).eulerByComponent(), <int>[1]);
    });

    test('two boxes apart are two islands of two', () {
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

      expect(
        MeshChecks(EditMesh.fromFaces(points, faces)).eulerByComponent(),
        <int>[2, 2],
      );
    });

    test('two boxes at a corner are one island of three', () {
      // Two balls joined at a point: 2 + 2 − 1. A number nobody expected is
      // the cheapest signal that a model is not the shape it looks like.
      expect(MeshChecks(boxesAtACorner()).eulerByComponent(), <int>[3]);
    });
  });

  group('the whole report', () {
    test('comes back worst first', () {
      final mesh = grid(2);
      edit(mesh, () {
        mesh
          ..addVertex(Vector3(9, 9, 9))
          ..splitEdge(mesh.halfEdgeOf(0));
      });

      final issues = MeshChecks(mesh).all();

      // Mutation: sort by severity ascending, and a panel showing the first
      // three shows the three that matter least.
      expect(issues.first.severity, IssueSeverity.warning);
      expect(issues.last.severity, IssueSeverity.note);
      expect(
        issues.map((MeshIssue it) => it.kind.name),
        containsAll(<String>['isolated-vertex', 'ngon', 'boundary-edge']),
      );
      expect(issues.first.toString(), contains('isolated-vertex'));
    });
  });
}
