/// `anim-23`'s own golden: `modeler-autorig`, the app half's own frame — a
/// humanoid rig built from `startingMarkers`/`deriveMarkers` over a
/// cuboid's own bounds, skinned through `createRig`'s full pipeline
/// (`buildSkeleton` → `bindWeightsJobRequestFor` → `SetRig`, one journal
/// step), then drawn the same way `retarget_frame_test.dart`'s own
/// `modeler-retarget.png` is: `ModelerStage.fromProject`, ordinary lit
/// shading, no GPU.
///
///     flutter test test/autorig_frame_test.dart
///     flutter test test/autorig_frame_test.dart --update-goldens
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/autorig_markers.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a cuboid, auto-rigged and skinned, matches its reference', () async {
    final size = Vector3(0.6, 2.0, 0.4);
    final EditMesh mesh = ParametricCuboid(size: size).toEditMesh();
    final seed = ModelProject(
      objects: <ModelObject>[
        ModelObject(
          id: 1,
          name: 'figure',
          geometry: EditedGeometry(mesh),
          transform: Matrix4.identity(),
        ),
      ],
      nextId: 2,
    );

    final bounds = Aabb3.minMax(
      Vector3(-size.x / 2, -size.y / 2, -size.z / 2),
      Vector3(size.x / 2, size.y / 2, size.z / 2),
    );
    final markers = deriveMarkers(
      RigTemplate.humanoid,
      startingMarkers(RigTemplate.humanoid, bounds),
    );

    final history = ModelHistory(seed);
    final refused = await createRig(
      history: history,
      template: RigTemplate.humanoid,
      markers: markers,
      skinObjectId: 1,
      bind: (BindWeightsJobRequest request) => request.run(),
    );
    expect(refused, isNull, reason: refused);
    expect(history.canUndo, isTrue);
    expect(history.project.skeletons.single.jointCount, lessThanOrEqualTo(64));

    final rigged = history.project;
    final frame = await renderFrame(
      width: 240,
      height: 160,
      build: (FrameRequest request) {
        final stage = ModelerStage.fromProject(
          device: request.device,
          project: rigged,
        );
        stage.frameSubject();
        return (scene: stage.scene, camera: stage.camera);
      },
    );

    await expectMatchesGolden(frame, 'test/goldens/modeler-autorig.png');
  });
}
