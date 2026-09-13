/// `mat-20`'s own golden frame: `modifier-mirror-array` — a cube with a
/// mirror across X and then an array of three, applied through the same
/// `ApplyModifier` the panel's own "Применить" button runs, rendered
/// through `ModelerStage.fromProject` the way every other document-driven
/// frame test in this suite is.
///
///     flutter test test/modifier_mirror_array_frame_test.dart
///
/// **Applied, not previewed live.** `SceneSync`'s own `_dataOf` uploads
/// whatever `EditedGeometry` currently holds — a document's base mesh, not
/// a modifier stack folded over it on the fly — so a frame proving a
/// modifier's own visible effect needs the bake `ApplyModifier` already
/// does for the "Применить" button, not a second live-evaluation path this
/// application does not have.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A unit cube centred at [center] rather than at the origin — the mirror
/// plane below passes through the *mesh's own* local origin, so a cube
/// already straddling it would mirror onto itself and the modifier's own
/// effect would not show up in the picture at all.
EditMesh _offsetCuboid(Vector3 center) {
  final half = Vector3(0.5, 0.5, 0.5);
  Vector3 at(double sx, double sy, double sz) =>
      center + Vector3(sx * half.x, sy * half.y, sz * half.z);
  return EditMesh.fromFaces(
    <Vector3>[
      at(-1, -1, -1),
      at(1, -1, -1),
      at(1, 1, -1),
      at(-1, 1, -1),
      at(-1, -1, 1),
      at(1, -1, 1),
      at(1, 1, 1),
      at(-1, 1, 1),
    ],
    <List<int>>[
      <int>[4, 5, 6, 7],
      <int>[1, 0, 3, 2],
      <int>[5, 1, 2, 6],
      <int>[0, 4, 7, 3],
      <int>[3, 7, 6, 2],
      <int>[0, 1, 5, 4],
    ],
  );
}

void main() {
  group('modifier stack, drawn', () {
    test('a cube mirrored across X and arrayed three deep matches its reference', () async {
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'cube',
          geometry: EditedGeometry(_offsetCuboid(Vector3(1.2, 0, 0))),
          transform: Matrix4.identity(),
          modifiers: <ModifierSlot>[
            ModifierSlot(modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
            ModifierSlot(
              modifier: ArrayModifier(count: 3, offset: Vector3(0, 0, 2.2)),
            ),
          ],
        ),
      );

      final history = ModelHistory(project);
      // Bakes both slots (0..1) into the geometry and empties the stack —
      // the same "Применить" the panel's own button runs.
      expect(history.run(const ApplyModifier(id: 1, index: 1)), isNull);
      expect(history.project[1]!.modifiers, isEmpty);

      final frame = await renderFrame(
        // `mat-31`'s own size for the three material/scene goldens this
        // app's own tests keep in `test/goldens`.
        width: 320,
        height: 200,
        build: (FrameRequest request) {
          final stage = ModelerStage.fromProject(
            device: request.device,
            project: history.project,
          );
          // Wide enough to hold both mirrored halves (x spans roughly
          // [-1.7, 1.7]) across all three array copies (z spans roughly
          // [-0.5, 4.9]) — `ModelerStage.build`'s own 3.2 frames one cube,
          // not six spread this far apart. A shallower pitch than the
          // default 0.45 looks down the array's own Z axis rather than
          // across it, so all three copies read as separate cubes rather
          // than stacking behind one another.
          stage.orbit
            ..distance = 14.0
            ..pitch = 0.65
            ..yaw = 0.9
            ..apply();
          return (scene: stage.scene, camera: stage.camera);
        },
      );

      await expectMatchesGolden(frame, 'test/goldens/modifier-mirror-array.png');
    });
  });
}
