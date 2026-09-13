/// `mat-04a-n`'s own golden frame: `mesh-material-colour` — the cube in
/// `#5FD4E4` `mat-04`'s own row already names as its acceptance's hex value,
/// bound through `bindSurfaceMaterial` — the one real conversion from a
/// document's `SurfaceMaterial` to a drawable `Material` every decoder and
/// `MaterialPool` itself goes through — and rendered through `staging.dart`,
/// same as every other frame test in this suite.
///
///     flutter test test/mesh_material_colour_frame_test.dart
///
/// **`ModelerStage.build`, not `.fromProject`.** `.fromProject` paints
/// through `MaterialPool`, whose own `refresh` is asynchronous because it
/// may have to decode a texture — a device `renderFrame` has not created yet
/// when a test builds its project. This material has no texture at all, so
/// there is nothing for that machinery to earn here: `bindSurfaceMaterial`
/// is awaited directly, before `renderFrame` runs, and the `Material` it
/// hands back replaces `.build`'s own default clay on the one node the stage
/// already has.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('material colour, drawn', () {
    test('the base colour a person types as #5FD4E4 renders as itself', () async {
      // `material_panel_test.dart`'s own "the base colour field edits
      // baseColor" already pins this conversion at the widget level
      // (`closeTo(0.373, 0.001)` on the red channel); this is the same
      // number carried all the way to a rendered picture.
      final surface = SurfaceMaterial(
        baseColor: Vector4(0.373, 0.831, 0.894, 1.0),
        roughness: 0.6,
      );
      final material = await bindSurfaceMaterial(
        surface,
        textureFor: (int index, TextureSampling sampling) async {
          throw StateError(
            'this material declares no texture slot; nothing should ask for one',
          );
        },
      );

      final frame = await renderFrame(
        width: 240,
        height: 160,
        build: (FrameRequest request) {
          final stage = ModelerStage.build(device: request.device);
          (stage.subject as MeshNode).material = material;
          return (scene: stage.scene, camera: stage.camera);
        },
      );

      await expectMatchesGolden(frame, 'test/goldens/mesh-material-colour.png');
    });
  });
}
