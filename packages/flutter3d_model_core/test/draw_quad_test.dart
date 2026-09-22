/// `DrawQuad` — `pro-rt-02`: the retopology tool's own quad, with the snap
/// that welds it to the strip beside it.
///
///     dart test test/draw_quad_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// An empty mesh for a retopology to be drawn into, and a high mesh beside
/// it to project onto.
ModelHistory opened({bool withSource = false}) {
  final ModelProject project = ModelProject(
    objects: <ModelObject>[
      ModelObject(
        id: 1,
        name: 'retopo',
        geometry: EditedGeometry(EditMeshBuilder().build()),
        transform: Matrix4.identity(),
      ),
      if (withSource)
        ModelObject(
          id: 2,
          name: 'high',
          // A unit sphere: every point of it is exactly one from the origin,
          // which is what makes the projection checkable without a tolerance
          // pulled out of the air.
          geometry: EditedGeometry(
            ParametricSphere(radius: 1, segments: 32, rings: 16).toEditMesh(),
          ),
          transform: Matrix4.identity(),
        ),
    ],
    nextId: 3,
  );
  return ModelHistory(project)
    ..selection = const ProjectSelection(objects: <int>[1]);
}

EditMesh meshOf(ModelHistory history) =>
    (history.project[1]!.geometry as EditedGeometry).mesh;

List<Vector3> square(double x) => <Vector3>[
  Vector3(x, 0, 0),
  Vector3(x + 1, 0, 0),
  Vector3(x + 1, 1, 0),
  Vector3(x, 1, 0),
];

void main() {
  group('one quad', () {
    test('adds four vertices and a face, and selects the face', () {
      final ModelHistory history = opened();
      expect(history.run(DrawQuad(objectId: 1, points: square(0))), isNull);
      expect(meshOf(history).vertexCount, 4);
      expect(meshOf(history).faceCount, 1);
      expect(history.selection.elements, hasLength(1));
      expect(history.selection.level, ElementLevel.face);
    });

    test('and undo takes it back', () {
      final ModelHistory history = opened();
      expect(history.run(DrawQuad(objectId: 1, points: square(0))), isNull);
      expect(history.undo(), isTrue);
      expect(meshOf(history).faceCount, 0);
      expect(meshOf(history).vertexCount, 0);
    });
  });

  group('the snap', () {
    test(
      'welds the second quad to the first rather than doubling its edge',
      () {
        final ModelHistory history = opened();
        expect(history.run(DrawQuad(objectId: 1, points: square(0))), isNull);
        expect(history.run(DrawQuad(objectId: 1, points: square(1))), isNull);

        // **Six vertices, not eight.** Mutation: add four fresh vertices every
        // time. The mesh looks right in a viewport and exports as a shell full
        // of holes, because the two quads share an edge in the picture and no
        // edge in the topology — which is the whole reason a retopology tool
        // is a tool rather than a way of placing quads.
        expect(meshOf(history).vertexCount, 6);
        expect(meshOf(history).faceCount, 2);
      },
    );

    test('and a snap of zero welds nothing', () {
      final ModelHistory history = opened();
      expect(
        history.run(DrawQuad(objectId: 1, points: square(0), snap: 0)),
        isNull,
      );
      expect(
        history.run(DrawQuad(objectId: 1, points: square(1), snap: 0)),
        isNull,
      );
      expect(meshOf(history).vertexCount, 8);
    });

    test('two corners on the same vertex is refused, and leaves no step', () {
      final ModelHistory history = opened();
      expect(history.run(DrawQuad(objectId: 1, points: square(0))), isNull);
      final String? refusal = history.run(
        DrawQuad(
          objectId: 1,
          points: <Vector3>[
            Vector3(0, 0, 0),
            Vector3(0, 0, 0),
            Vector3(1, 1, 0),
            Vector3(0, 1, 0),
          ],
        ),
      );
      expect(refusal, contains('triangle'));
      expect(meshOf(history).faceCount, 1);
      expect(history.steps, hasLength(1));
    });
  });

  group('the projection', () {
    test('pulls a corner onto the high surface', () {
      final ModelHistory history = opened(withSource: true);
      expect(
        history.run(
          DrawQuad(
            objectId: 1,
            sourceId: 2,
            // Well outside the unit sphere: every corner has to come back to
            // it, and a command that left them where they were would leave
            // the retopology floating.
            points: <Vector3>[
              Vector3(3, 0, 0),
              Vector3(0, 3, 0),
              Vector3(-3, 0, 0),
              Vector3(0, -3, 0),
            ],
          ),
        ),
        isNull,
      );

      final EditMesh mesh = meshOf(history);
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (!mesh.isVertexAlive(v)) continue;
        // A faceted sphere of thirty-two segments sits just inside the ideal
        // one, which is the whole of the tolerance here.
        expect(mesh.positionOf(v).length, closeTo(1, 0.02));
      }
    });

    test('and a source with no mesh is refused by name', () {
      final ModelHistory history = opened();
      expect(
        history.run(DrawQuad(objectId: 1, sourceId: 9, points: square(0))),
        contains('9'),
      );
    });
  });

  group('refusals', () {
    test('a point count that is not four', () {
      final ModelHistory history = opened();
      expect(
        history.run(DrawQuad(objectId: 1, points: <Vector3>[Vector3.zero()])),
        contains('not 1'),
      );
    });

    test('and an object that is not there', () {
      final ModelHistory history = opened();
      expect(
        history.run(DrawQuad(objectId: 99, points: square(0))),
        contains('99'),
      );
    });
  });

  group('written down', () {
    test('reads back as itself', () {
      final ModelCommand? read = modelCommandFromJson(
        DrawQuad(
          objectId: 1,
          points: square(0),
          sourceId: 2,
          snap: 0.05,
        ).toJson(),
      );
      expect(read, isA<DrawQuad>());
      final DrawQuad back = read! as DrawQuad;
      expect(back.objectId, 1);
      expect(back.sourceId, 2);
      expect(back.snap, 0.05);
      expect(back.points, hasLength(4));
    });
  });
}
