/// Splitting edges and faces, and running a loop of them across a strip.
///
/// A cylinder of sixteen sides is the shape that decides it: a loop cut round
/// the middle has to add sixteen vertices, thirty-two edges and sixteen faces
/// and leave every face four-sided. A torus is the one that says the ring
/// closes. A flat strip is the one that says it stops.
library;

import 'dart:math' as math;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Runs [body] as one step of history.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

/// The side of a cylinder as [sides] quads, with no caps.
EditMesh openCylinder(int sides) {
  final points = <Vector3>[];
  for (var height = 0; height < 2; height++) {
    for (var i = 0; i < sides; i++) {
      final angle = 2 * math.pi * i / sides;
      points.add(Vector3(math.cos(angle), height.toDouble(), math.sin(angle)));
    }
  }
  int at(int ring, int i) => ring * sides + i % sides;
  return EditMesh.fromFaces(points, <List<int>>[
    for (var i = 0; i < sides; i++)
      <int>[at(0, i), at(0, i + 1), at(1, i + 1), at(1, i)],
  ]);
}

/// A torus of [major] by [minor] quads.
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
  return EditMesh.fromFaces(points, <List<int>>[
    for (var i = 0; i < major; i++)
      for (var j = 0; j < minor; j++)
        <int>[at(i, j), at(i, j + 1), at(i + 1, j + 1), at(i + 1, j)],
  ]);
}

/// A strip of [n] quads in a row.
EditMesh strip(int n) {
  final points = <Vector3>[
    for (var x = 0; x <= n; x++) ...<Vector3>[
      Vector3(x.toDouble(), 0, 0),
      Vector3(x.toDouble(), 1, 0),
    ],
  ];
  return EditMesh.fromFaces(points, <List<int>>[
    for (var x = 0; x < n; x++) <int>[x * 2, x * 2 + 2, x * 2 + 3, x * 2 + 1],
  ]);
}

/// Whether every live face has four corners.
bool allQuads(EditMesh mesh) {
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (mesh.isFaceAlive(face) && mesh.valencyOf(face) != 4) return false;
  }
  return true;
}

/// A half-edge of [face] running between the two rings of a cylinder.
int uprightOf(EditMesh mesh, int face) {
  var found = EditMesh.none;
  mesh.forEachHalfEdge(face, (int half) {
    final from = mesh.positionOf(mesh.originOf(half));
    final to = mesh.positionOf(mesh.originOf(mesh.nextOf(half)));
    if ((from.y - to.y).abs() > 0.5) found = half;
  });
  return found;
}

void main() {
  group('putting a vertex on an edge', () {
    test('both faces gain a corner and nothing is cut in two', () {
      final mesh = EditMesh.cuboid();
      final edge = mesh.halfEdgeOf(0);
      final behind = mesh.faceOf(mesh.twinOf(edge));

      late int middle;
      edit(mesh, () => middle = mesh.splitEdge(edge));

      expect(mesh.vertexCount, 9);
      expect(mesh.faceCount, 6);
      expect(mesh.valencyOf(0), 5);
      expect(mesh.valencyOf(behind), 5);
      expect(mesh.eulerCharacteristic, 2);
      // Mutation: leave the twins as they were, and the two new halves face the
      // whole edge on the other side — `validate` catches it, because they no
      // longer run between the same two vertices.
      mesh.validate();

      expect(mesh.positionOf(middle).x, closeTo(0, 1e-6));
      expect(mesh.signedVolume, closeTo(1, 1e-5));
    });

    test('the factor runs from the end the caller named', () {
      final mesh = EditMesh.cuboid();
      final edge = mesh.halfEdgeOf(0);
      final from = mesh.positionOf(mesh.originOf(edge));

      late int middle;
      edit(mesh, () => middle = mesh.splitEdge(edge, factor: 0.25));

      final at = mesh.positionOf(middle);
      expect((at - from).length, closeTo(0.25, 1e-6));
    });

    test('the corner attributes are interpolated on both sides', () {
      final mesh = EditMesh.cuboid();
      final edge = mesh.halfEdgeOf(0);
      edit(mesh, () {
        mesh
          ..setUv(edge, Vector2(0, 0))
          ..setUv(mesh.nextOf(edge), Vector2(1, 0));
      });

      edit(mesh, () => mesh.splitEdge(edge, factor: 0.25));

      // Mutation: give the new corner the source corner's coordinates instead
      // of a blend, and a texture jumps at every cut somebody makes.
      expect(mesh.uvOf(mesh.nextOf(edge)).x, closeTo(0.25, 1e-6));
    });

    test('an edge on a rim splits with only one side to answer for', () {
      final mesh = strip(1);
      final rim = mesh.halfEdgeOf(0);

      edit(mesh, () => mesh.splitEdge(rim));

      expect(mesh.vertexCount, 5);
      expect(mesh.valencyOf(0), 5);
      mesh.validate();
    });
  });

  group('cutting a face in two', () {
    test('a six-sided face becomes two, and χ does not move', () {
      final mesh = EditMesh.cuboid();
      final edge = mesh.halfEdgeOf(0);
      edit(mesh, () => mesh.splitEdge(edge));
      final opposite = mesh.nextOf(mesh.nextOf(mesh.nextOf(edge)));

      edit(mesh, () => mesh.splitFace(0, mesh.nextOf(edge), opposite));

      expect(mesh.faceCount, 7);
      expect(mesh.eulerCharacteristic, 2);
      mesh.validate();
    });

    test('a cut between neighbours is refused', () {
      final mesh = EditMesh.cuboid();
      final edge = mesh.halfEdgeOf(0);

      late int made;
      edit(mesh, () => made = mesh.splitFace(0, edge, mesh.nextOf(edge)));

      // Mutation: cut anyway, and one side of it has two corners — a face the
      // builder would have refused outright and every walk over it loops on.
      expect(made, EditMesh.none);
      expect(mesh.faceCount, 6);
    });
  });

  group('a loop across a ring', () {
    test('a cylinder of sixteen gains sixteen of everything', () {
      final mesh = openCylinder(16);
      expect(mesh.vertexCount, 32);
      expect(mesh.edgeCount, 48);
      expect(mesh.faceCount, 16);

      late OpResult result;
      edit(mesh, () {
        result = loopCut(
          mesh,
          Selection.of(ElementLevel.edge, <int>[
            mesh.edgeOf(uprightOf(mesh, 0)),
          ]),
        );
      });

      expect(result.ok, isTrue);
      expect(mesh.vertexCount, 48);
      expect(mesh.edgeCount, 80);
      expect(mesh.faceCount, 32);
      // Mutation: cut every rung at the factor measured from its own start
      // rather than from the direction the walk arrived in, and the new loop
      // zig-zags — every second quad comes out with the wrong shape.
      expect(allQuads(mesh), isTrue);
      mesh.validate();
    });

    test('the new loop lies where the factor says', () {
      final mesh = openCylinder(8);

      edit(mesh, () {
        loopCut(
          mesh,
          Selection.of(ElementLevel.edge, <int>[
            mesh.edgeOf(uprightOf(mesh, 0)),
          ]),
          factor: 0.25,
        );
      });

      // Every vertex the cut added stands a quarter of the way up, and they all
      // stand at the same height — which is what says the walk kept its
      // direction all the way round.
      for (var vertex = 32; vertex < mesh.vertexSlotCount; vertex++) {
        expect(mesh.positionOf(vertex).y, closeTo(0.25, 1e-6));
      }
    });

    test('the far rim of an open strip is cut from the same side', () {
      final mesh = strip(3);

      edit(mesh, () {
        loopCut(
          mesh,
          Selection.of(ElementLevel.edge, <int>[
            mesh.edgeOf(uprightOf(mesh, 1)),
          ]),
          factor: 0.25,
        );
      });

      // Every vertex the cut added stands at the same height, the far rim
      // included. Mutation: measure the last rung from its own start like all
      // the others, and it comes out at 0.75 while the rest are at 0.25 — the
      // new loop runs across the strip and then kinks at the end of it.
      for (var vertex = 8; vertex < mesh.vertexSlotCount; vertex++) {
        expect(mesh.positionOf(vertex).y, closeTo(0.25, 1e-6));
      }
      expect(mesh.vertexSlotCount, 12);
    });

    test('a torus closes the loop rather than stopping', () {
      final mesh = torus();
      final before = mesh.faceCount;

      edit(mesh, () {
        loopCut(
          mesh,
          Selection.of(ElementLevel.edge, <int>[
            mesh.edgeOf(mesh.halfEdgeOf(0)),
          ]),
        );
      });

      // Eight quads round, so eight more faces and χ still zero.
      expect(mesh.faceCount, before + 8);
      expect(mesh.eulerCharacteristic, 0);
      expect(allQuads(mesh), isTrue);
      mesh.validate();
    });

    test('a flat strip is cut from rim to rim', () {
      final mesh = strip(3);

      edit(mesh, () {
        loopCut(
          mesh,
          Selection.of(ElementLevel.edge, <int>[
            mesh.edgeOf(uprightOf(mesh, 1)),
          ]),
        );
      });

      // Six, from a cut that reached both rims: the edge picked is in the
      // middle quad, so a walk that only went forwards would leave the quad
      // behind it whole. Mutation: drop the backward walk and this is five.
      expect(mesh.faceCount, 6);
      expect(allQuads(mesh), isTrue);
      expect(mesh.eulerCharacteristic, 1);
      mesh.validate();
    });

    test('two cuts land a third and two thirds along', () {
      final mesh = openCylinder(4);

      edit(mesh, () {
        loopCut(
          mesh,
          Selection.of(ElementLevel.edge, <int>[
            mesh.edgeOf(uprightOf(mesh, 0)),
          ]),
          cuts: 2,
        );
      });

      expect(mesh.faceCount, 12);
      expect(allQuads(mesh), isTrue);
      final heights = <double>[
        for (var v = 8; v < mesh.vertexSlotCount; v++) mesh.positionOf(v).y,
      ]..sort();
      // Mutation: place every cut at the same relative factor of what is left,
      // and the second lands half way up rather than two thirds.
      expect(heights.first, closeTo(1 / 3, 1e-5));
      expect(heights.last, closeTo(2 / 3, 1e-5));
      mesh.validate();
    });

    test('a ring that runs into a triangle stops there', () {
      // Two quads and a triangle in a row: the ring cannot cross the triangle.
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, 0, 0),
          Vector3(0, 1, 0),
          Vector3(1, 0, 0),
          Vector3(1, 1, 0),
          Vector3(2, 0, 0),
          Vector3(2, 1, 0),
          Vector3(3, 0.5, 0),
        ],
        <List<int>>[
          <int>[0, 2, 3, 1],
          <int>[2, 4, 5, 3],
          <int>[4, 6, 5],
        ],
      );

      edit(mesh, () {
        loopCut(
          mesh,
          Selection.of(ElementLevel.edge, <int>[
            mesh.edgeOf(uprightOf(mesh, 0)),
          ]),
        );
      });

      // Two quads cut in half and the triangle left in one piece. Mutation:
      // step across a face of any valency, and the ring goes on into the
      // triangle and cuts it too — six faces rather than five.
      expect(mesh.faceCount, 5);
      // It does gain a corner, and that is not the same thing: the edge it
      // shares with the last quad has to carry the end of the cut, so a
      // triangle capping a strip comes out four-sided. Leaving it three-sided
      // would mean stopping the cut one edge short of the rim, which is a
      // T-junction and a hole in every renderer that meets it.
      expect(mesh.valencyOf(2), 4);
      mesh.validate();
    });

    test('an edge with no quad on it is refused', () {
      final mesh = EditMesh.fromFaces(
        <Vector3>[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)],
        <List<int>>[
          <int>[0, 1, 2],
        ],
      );

      late OpResult result;
      edit(mesh, () {
        result = loopCut(
          mesh,
          Selection.of(ElementLevel.edge, <int>[mesh.halfEdgeOf(0)]),
        );
      });

      expect(result.ok, isFalse);
      expect(result.reason, contains('four-sided'));
      expect(mesh.faceCount, 1);
    });

    test('nothing selected is refused with something to say', () {
      final mesh = openCylinder(4);

      late OpResult result;
      edit(mesh, () {
        result = loopCut(mesh, Selection.empty(ElementLevel.edge));
      });

      expect(result.ok, isFalse);
      expect(result.reason, contains('selected'));
    });
  });

  group('history', () {
    test('a loop cut is one step and comes all the way back', () {
      final mesh = openCylinder(8);
      final before = mesh.faceCount;

      edit(mesh, () {
        loopCut(
          mesh,
          Selection.of(ElementLevel.edge, <int>[
            mesh.edgeOf(uprightOf(mesh, 0)),
          ]),
        );
      });
      expect(mesh.faceCount, before + 8);

      expect(mesh.undo(), isTrue);

      expect(mesh.faceCount, before);
      expect(mesh.vertexCount, 16);
      expect(mesh.vertexSlotCount, 16);
      expect(mesh.halfEdgeSlotCount, 32);
      mesh.validate();

      expect(mesh.redo(), isTrue);
      expect(mesh.faceCount, before + 8);
      expect(allQuads(mesh), isTrue);
      mesh.validate();
    });
  });
}
