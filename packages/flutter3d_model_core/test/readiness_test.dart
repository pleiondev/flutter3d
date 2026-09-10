/// What a project refuses to export, and what it merely warns about.
///
///     dart test test/readiness_test.dart
///
/// One project per rule, built to have exactly the fault the rule is for and
/// nothing else, so a rule that fires on the wrong shape fails here rather than
/// in front of somebody who is trying to ship. The severities are tested as
/// hard as the counts: an error greys out a button and a warning does not, so a
/// rule that picks the wrong one either blocks a good export or waves a broken
/// one through.
library;

import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
// By path rather than through the barrel, and both of these for one reason:
// readiness is not exported yet, and a test that reached for the barrel to get
// `ModelProject` would drag in the commands and the history to check a rule
// about triangles. What it needs is the document and the rules over it.
import 'package:flutter3d_model_core/src/project.dart';
import 'package:flutter3d_model_core/src/readiness.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A project holding [geometries], named `a`, `b`, …
ModelProject projectOf(
  List<Geometry> geometries, {
  ProjectProfile profile = const ProjectProfile(),
}) {
  var project = ModelProject(profile: profile);
  for (var i = 0; i < geometries.length; i++) {
    final geometry = geometries[i];
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: String.fromCharCode(0x61 + i),
        geometry: geometry,
        transform: Matrix4.identity(),
      ),
    );
  }
  return project;
}

/// A closed, manifold, outward-wound solid of four triangles and nothing else:
/// the one shape that passes every rule here, so a rule that fires on it is a
/// rule firing on nothing.
EditMesh tetrahedron() => EditMesh.fromFaces(
  <Vector3>[
    Vector3(0, 0, 0),
    Vector3(1, 0, 0),
    Vector3(0, 1, 0),
    Vector3(0, 0, 1),
  ],
  <List<int>>[
    <int>[0, 2, 1],
    <int>[0, 3, 2],
    <int>[0, 1, 3],
    <int>[1, 2, 3],
  ],
);

/// Two boxes sharing one corner and no edge: a surface pinched at a point.
EditMesh boxesAtACorner() {
  const box = <List<int>>[
    <int>[4, 5, 6, 7],
    <int>[1, 0, 3, 2],
    <int>[5, 1, 2, 6],
    <int>[0, 4, 7, 3],
    <int>[3, 7, 6, 2],
    <int>[0, 1, 5, 4],
  ];
  const second = <int>[6, 8, 9, 10, 11, 12, 13, 14];
  return EditMesh.fromFaces(
    <Vector3>[
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
    ],
    <List<int>>[
      ...box,
      for (final List<int> face in box)
        <int>[for (final int v in face) second[v]],
    ],
  );
}

/// Buffers as they arrived, with [triangles] of them.
ImportedGeometry imported(int triangles) => ImportedGeometry(
  MeshData(
    layout: VertexLayout.positionOnly,
    vertices: Float32List(triangles * 9),
    indices: Uint32List(triangles * 3),
  ),
);

void main() {
  group('a project with nothing wrong', () {
    test('has nothing to say and says so', () {
      final ready = ExportReadiness.check(
        projectOf(<Geometry>[EditedGeometry(tetrahedron())]),
      );

      expect(ready.issues, isEmpty);
      expect(ready.canExport, isTrue);
      expect(ready.says, 'ready to export');
    });
  });

  group('faces with more than three sides', () {
    test('a box of quads is a warning when the format holds triangles', () {
      final ready = ExportReadiness.check(
        projectOf(<Geometry>[EditedGeometry(EditMesh.cuboid())]),
      );

      // Mutation: ask `MeshChecks.ngons()` for this instead of counting the
      // faces here. That check wants more than *four* corners, because a quad
      // is a normal thing to have in a modeller — so a box of six quads
      // reports nothing at all, the six-quad expectation below reads `0
      // issues`, and every quad in the project goes into a glTF as whatever
      // the writer felt like cutting it into.
      expect(ready.issues, hasLength(1));
      expect(ready.issues.single.severity, ExportSeverity.warning);
      expect(ready.issues.single.message, contains('6 faces'));
      expect(ready.issues.single.message, contains('"a"'));
      expect(ready.issues.single.object?.name, 'a');

      // And it loads, so it does not stop the export.
      expect(ready.canExport, isTrue);
    });

    test('and nothing at all when the format holds n-gons', () {
      // Mutation: drop the `trianglesOnly` argument and check the faces
      // always. An OBJ export, which can write the quad exactly as it stands,
      // then reports six problems it is about to not have — this expectation
      // sees 1 issue where it wants none.
      expect(
        ExportReadiness.check(
          projectOf(<Geometry>[EditedGeometry(EditMesh.cuboid())]),
          trianglesOnly: false,
        ).issues,
        isEmpty,
      );
    });
  });

  group('geometry with nothing in it', () {
    test('an edited mesh with no faces stops the export', () {
      final ready = ExportReadiness.check(
        projectOf(<Geometry>[EditedGeometry(EditMesh.empty())]),
      );

      // Mutation: make this a warning rather than an error — it is only an
      // empty object, after all — and `canExport` comes back true, so the
      // panel writes a file with a primitive some loaders reject outright and
      // the rest draw as nothing.
      expect(ready.issues, hasLength(1));
      expect(ready.issues.single.severity, ExportSeverity.error);
      expect(ready.issues.single.object?.name, 'a');
      expect(ready.canExport, isFalse);
      expect(ready.says, startsWith('will not export'));
    });

    test('and so does an imported mesh with no triangles', () {
      // The same rule reaching a geometry with no topology behind it, which is
      // why it is asked of the triangle count rather than of the faces: an
      // `ImportedGeometry` has no faces to count.
      final ready = ExportReadiness.check(
        projectOf(<Geometry>[imported(0), imported(2)]),
      );

      expect(ready.issues, hasLength(1));
      expect(ready.issues.single.object?.name, 'a');
      expect(ready.canExport, isFalse);
    });
  });

  group('the triangle budget', () {
    test('is spent by the whole project, not by one object', () {
      // Four triangles each, against a budget of six: neither object is over
      // it and together they are.
      final ready = ExportReadiness.check(
        projectOf(<Geometry>[
          EditedGeometry(tetrahedron()),
          EditedGeometry(tetrahedron()),
        ], profile: const ProjectProfile(name: 'tiny', maxTriangles: 6)),
      );

      // Mutation: measure each object against the budget instead of the
      // project — the loop is right there and it is the easy mistake — and a
      // scene of two hundred props inside the budget apiece and four times
      // over it together reports nothing. This expectation sees 0 issues.
      expect(ready.issues, hasLength(1));
      expect(ready.issues.single.message, contains('8 triangles'));
      expect(ready.issues.single.message, contains('tiny'));

      // No object to blame, because they are all spending it.
      expect(ready.issues.single.object, isNull);

      // Mutation: call it an error. A model over budget loads on every engine
      // there is, and blocking the export over it is refusing to write a file
      // that works.
      expect(ready.issues.single.severity, ExportSeverity.warning);
      expect(ready.canExport, isTrue);
    });

    test('and a project inside it is not mentioned', () {
      expect(
        ExportReadiness.check(
          projectOf(<Geometry>[
            EditedGeometry(tetrahedron()),
          ], profile: const ProjectProfile(name: 'tiny', maxTriangles: 4)),
        ).issues,
        isEmpty,
      );
    });
  });

  group('topology, which is MeshChecks and not this', () {
    test('a surface pinched at a point is a warning naming the object', () {
      final ready = ExportReadiness.check(
        projectOf(<Geometry>[EditedGeometry(boxesAtACorner())]),
        // Quads are not what this test is about; the two boxes are made of
        // them and would otherwise report as well.
        trianglesOnly: false,
      );

      // Mutation: drop `nonManifoldVertices` from the list. Nothing else in
      // the readiness looks at how faces meet, so this is 0 issues, and a
      // model that cannot be thickened, subdivided or printed exports without
      // a word.
      expect(ready.issues, hasLength(1));
      expect(ready.issues.single.severity, ExportSeverity.warning);
      expect(ready.issues.single.message, contains('1 vertex'));
      expect(ready.issues.single.message, contains('"a"'));

      // It draws, so it does not stop the export.
      expect(ready.canExport, isTrue);
    });

    test('a shell wound inside out is a warning', () {
      final mesh = EditMesh.cuboid();
      mesh.beginStep();
      mesh.flipNormals();
      mesh.endStep();

      final ready = ExportReadiness.check(
        projectOf(<Geometry>[EditedGeometry(mesh)]),
        trianglesOnly: false,
      );

      // Mutation: drop `invertedShells`, and a box you can see straight
      // through into the far wall of goes out with nothing said — 0 issues
      // here.
      expect(ready.issues, hasLength(1));
      expect(ready.issues.single.severity, ExportSeverity.warning);
      expect(ready.issues.single.message, contains('6 faces'));
      expect(ready.issues.single.message, contains('inside out'));
    });

    test('a face with no area stops the export', () {
      // Three points in a line, and a second face beside it that is fine.
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

      final ready = ExportReadiness.check(
        projectOf(<Geometry>[EditedGeometry(mesh)]),
      );

      // Mutation: lift this as a warning like the other two. A face with no
      // area has no normal, so what gets written for it is a division by zero
      // in a vertex buffer, and `canExport` saying true here is the panel
      // handing somebody a file that disappears on half the drivers that open
      // it.
      expect(ready.issues.first.severity, ExportSeverity.error);
      expect(ready.issues.first.message, contains('1 face'));
      expect(ready.canExport, isFalse);
    });
  });

  group('a shape that still knows its own parameters', () {
    test('is not an issue, because it is built on the way out', () {
      final ready = ExportReadiness.check(
        projectOf(<Geometry>[ParametricGeometry(ParametricCuboid())]),
      );

      // Mutation: report anything at all about a `ParametricGeometry` — that
      // it has no topology to check, that it should be converted first — and
      // this is 1 issue. The shape builds itself into triangles on the way
      // out, so the only thing such an issue could tell somebody is to throw
      // away the parameters that let them change the segment count.
      expect(ready.issues, isEmpty);
      expect(ready.canExport, isTrue);
    });
  });

  group('the line for the status bar', () {
    test('is the worst of it, with the rest counted', () {
      final ready = ExportReadiness.check(
        projectOf(<Geometry>[
          EditedGeometry(EditMesh.cuboid()),
          EditedGeometry(EditMesh.empty()),
        ]),
      );

      // Mutation: put the warnings first — the order the objects are in, which
      // is the order they were found. The bar then leads with a quad while the
      // export is blocked by an empty mesh one object further down, and this
      // reads `exports with a warning`.
      //
      // What is *not* tested is the order among issues of one severity. The
      // two passes in `check` hold it because they do not sort at all, and a
      // `List.sort` on the severity would pass everything here while being
      // free to swap two warnings between runs. Catching that wants a project
      // large enough for the sort to reorder, which is a test about Dart
      // rather than about this.
      expect(ready.issues.first.severity, ExportSeverity.error);
      expect(ready.says, startsWith('will not export: "b" has no faces'));

      // Mutation: leave the count of the rest off the line, which is the line
      // anybody would write first. Somebody then fixes the empty object,
      // presses Export and meets the next problem, one at a time for as long
      // as the list is.
      expect(ready.says, endsWith('(and 1 more)'));
    });
  });
}
