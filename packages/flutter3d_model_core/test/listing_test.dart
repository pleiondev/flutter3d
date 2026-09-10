/// What is in a project, the way an outliner or an MCP `list` tool reads it.
///
///     dart test test/listing_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('contentsOf', () {
    test('every object exactly once, in outliner order, with its kind', () {
      var project = const ModelProject()
          .added(
            (int id) => ModelObject(
              id: id,
              name: 'sphere',
              geometry: ParametricGeometry(ParametricSphere()),
              transform: Matrix4.identity(),
            ),
          )
          .added(
            (int id) => ModelObject(
              id: id,
              name: 'cube',
              geometry: EditedGeometry(EditMesh.cuboid()),
              transform: Matrix4.identity(),
            ),
          );
      project = project.added(
        (int id) => ModelObject(
          id: id,
          name: 'scan',
          geometry: ImportedGeometry(
            MeshData(
              layout: VertexLayout.positionOnly,
              vertices: Float32List(9),
              indices: Uint32List(3),
            ),
          ),
          transform: Matrix4.identity(),
        ),
      );

      final listed = contentsOf(project);

      // Mutation: walk `project.objects.reversed`, or drop one geometry case
      // from the switch — either reads as a normal list until the kinds or
      // the order are checked against what the project actually holds.
      expect(listed.map((Listed l) => (l.name, l.kind)), <(String, String?)>[
        ('sphere', 'parametric'),
        ('cube', 'mesh'),
        ('scan', 'imported'),
      ]);
      expect(listed.map((Listed l) => l.id), project.objects.map((o) => o.id));
    });

    test('stable between calls on a project nothing has touched', () {
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'a',
          geometry: EditedGeometry(EditMesh.cuboid()),
          transform: Matrix4.identity(),
        ),
      );

      final first = contentsOf(project);
      final second = contentsOf(project);
      expect(
        first.map((Listed l) => (l.id, l.name, l.kind)),
        second.map((Listed l) => (l.id, l.name, l.kind)),
      );
    });

    test('an empty project lists nothing', () {
      expect(contentsOf(const ModelProject()), isEmpty);
    });
  });

  group('materialsOf', () {
    test('addressed by row, named or not', () {
      final project = ModelProject(
        materials: <ProjectMaterial>[
          ProjectMaterial(surface: SurfaceMaterial(name: 'steel')),
          ProjectMaterial(surface: SurfaceMaterial()),
        ],
      );

      final listed = materialsOf(project);

      expect(listed[0].id, 0);
      expect(listed[0].name, 'steel');
      // Mutation: leave the unnamed one blank instead of "material 1". An
      // agent or a picker offering an empty string as a choice is offering
      // nothing a person can act on.
      expect(listed[1].id, 1);
      expect(listed[1].name, 'material 1');
    });
  });

  group('what phase 3 has not built yet', () {
    test('skeletonsOf and clipsOf are empty rather than missing', () {
      // Not a placeholder that throws — a project genuinely has none of
      // either today, and a caller listing everything should not need a
      // special case for the two kinds that always come back empty.
      expect(skeletonsOf(const ModelProject()), isEmpty);
      expect(clipsOf(const ModelProject()), isEmpty);
    });
  });
}
