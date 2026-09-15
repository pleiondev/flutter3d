/// `brush_hit.dart`: casting a weight-paint ray against the mesh's own
/// POSED surface — `S5`'s own "the engine's live joints, not the document's".
///
///     flutter test test/brush_hit_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' show SceneNode, Skeleton;
import 'package:flutter3d_geometry/flutter3d_geometry.dart' show TriangleBvh;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/brush_hit.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A single quad, four vertices at rest around the origin — [joint] names
/// which local joint every one of them is fully bound to.
EditMesh _quad({required int joint}) {
  final mesh = EditMesh.fromFaces(
    <Vector3>[
      Vector3(-0.5, -0.5, 0),
      Vector3(0.5, -0.5, 0),
      Vector3(0.5, 0.5, 0),
      Vector3(-0.5, 0.5, 0),
    ],
    <List<int>>[
      <int>[0, 1, 2, 3],
    ],
  );
  mesh.beginStep();
  for (var v = 0; v < 4; v++) {
    mesh.setSkin(
      v,
      VertexAttributes(
        joints: Vector4(joint.toDouble(), 0, 0, 0),
        weights: Vector4(1, 0, 0, 0),
      ),
    );
  }
  mesh.endStep();
  return mesh;
}

void main() {
  group('buildPosedBrushSurface', () {
    test(
      "poses a vertex off the ENGINE's own live joint, not the rest pose",
      () {
        final mesh = _quad(joint: 1);
        final root = SceneNode(name: 'root');
        // Moved five metres along X purely on the live `SceneNode` — the
        // same thing `BendSliderBar` does, and never through `ModelProject`.
        final mid = SceneNode(name: 'mid')..setPosition(5, 0, 0);
        final skeleton = Skeleton(
          joints: <SceneNode>[root, mid],
          inverseBindMatrices: <Matrix4>[
            Matrix4.identity(),
            Matrix4.identity(),
          ],
        );
        final projectSkeleton = ProjectSkeleton(
          joints: <int>[10, 11],
          inverseBindMatrices: <Matrix4>[
            Matrix4.identity(),
            Matrix4.identity(),
          ],
        );

        final surface = buildPosedBrushSurface(
          mesh: mesh,
          skeleton: skeleton,
          projectSkeleton: projectSkeleton,
        );

        // Mutation: pose off `worldTransformOf(project, id)` or off the
        // rest position directly — either reads back at the origin's own
        // neighbourhood, not five metres out along X.
        for (var v = 0; v < 4; v++) {
          final rest = mesh.positionOf(v);
          expect(surface.positions[v * 3], closeTo(rest.x + 5, 1e-6));
          expect(surface.positions[v * 3 + 1], closeTo(rest.y, 1e-6));
          expect(surface.positions[v * 3 + 2], closeTo(rest.z, 1e-6));
        }
      },
    );

    test(
      'a vertex with no real weight at all poses at its own rest position',
      () {
        final mesh = _quad(joint: 0);
        // Forces vertex 0 to a real, stored empty weight list — `weightsOf`'s
        // own documented edge case, distinct from a mesh nobody has ever
        // skinned.
        mesh.beginStep();
        mesh.setSkin(
          0,
          VertexAttributes(joints: Vector4.zero(), weights: Vector4.zero()),
        );
        mesh.endStep();

        final joint = SceneNode(name: 'joint')..setPosition(9, 9, 9);
        final skeleton = Skeleton(
          joints: <SceneNode>[joint],
          inverseBindMatrices: <Matrix4>[Matrix4.identity()],
        );
        final projectSkeleton = ProjectSkeleton(
          joints: <int>[1],
          inverseBindMatrices: <Matrix4>[Matrix4.identity()],
        );

        final surface = buildPosedBrushSurface(
          mesh: mesh,
          skeleton: skeleton,
          projectSkeleton: projectSkeleton,
        );

        final rest = mesh.positionOf(0);
        expect(surface.positions[0], closeTo(rest.x, 1e-6));
        expect(surface.positions[1], closeTo(rest.y, 1e-6));
        expect(surface.positions[2], closeTo(rest.z, 1e-6));
      },
    );
  });

  group('nearestVertexOfTriangle', () {
    test(
      'answers whichever of the triangle\'s own three corners is closest',
      () {
        final positions = Float32List.fromList(<double>[
          0, 0, 0, //
          10, 0, 0, //
          0, 10, 0, //
        ]);
        final indices = Uint32List.fromList(<int>[0, 1, 2]);
        final surface = TriangleBvh.fromArrays(positions, indices);

        expect(nearestVertexOfTriangle(surface, 0, Vector3(9, 1, 0)), 1);
        expect(nearestVertexOfTriangle(surface, 0, Vector3(1, 9, 0)), 2);
        expect(nearestVertexOfTriangle(surface, 0, Vector3(0.1, 0.1, 0)), 0);
      },
    );
  });
}
