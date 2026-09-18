/// `mat-24`'s own golden frame: `scene-lit` — a project's own multi-light
/// `SceneLighting` pushed onto the stage through `LightingSync`, the same
/// seam `light_gizmos_test.dart`'s own end-to-end case already exercises as
/// a diff, held here instead to a recorded reference the way every other
/// picture in this suite is.
///
///     flutter test test/scene_frame_test.dart
///
/// **Through `staging.dart`, same as every other frame test.** `ModelerStage
/// .build`'s own cube and its two fixed key/fill lights are the world; what
/// this adds on top is `mat-24`'s own subject — three more lights a project
/// carries in its document, synced onto the identical scene the way the
/// application would once scene mode is wired into `main.dart`. `sync.apply`
/// turns `RenderSettings.debug.lightGizmos` on the moment the lighting has
/// any light in it, so the picture also carries the marker/arrow/cone gizmo
/// `mat-25` already built — a scene with lights but no way to see where they
/// are would not be what "источники как пикаемые маркеры" is asking for.
// Draws real pixels: a scene through the software rasteriser, a reference
// picture, or both. Tagged so a run that only wants the logic skips the whole
// slow class at once:
//
//     very_good test -x golden
//
// Not optional in CI, which runs the suite without the flag.
@Tags(<String>['golden'])
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('scene mode, drawn', () {
    test('a project with several lights matches its reference', () async {
      final sync = LightingSync();
      final lighting = SceneLighting(
        lights: <ProjectLight>[
          ProjectLight(
            type: ProjectLightType.point,
            color: Vector3(1.0, 0.35, 0.3),
            intensity: 5.0,
            range: 8.0,
          ),
          ProjectLight(
            type: ProjectLightType.point,
            color: Vector3(0.3, 0.4, 1.0),
            intensity: 5.0,
            range: 8.0,
          ),
          ProjectLight(
            type: ProjectLightType.spot,
            intensity: 4.0,
            outerConeAngle: 0.5,
          ),
        ],
        exposure: 1.4,
      );

      final frame = await renderFrame(
        // `mat-31`'s own size for the three material/scene goldens this
        // app's own tests keep in `test/goldens`.
        width: 320,
        height: 200,
        settings: sync.apply(const RenderSettings(), lighting),
        build: (FrameRequest request) {
          final stage = ModelerStage.build(device: request.device);
          stage.frameSubject();
          // The application's own seam: `mat-23`'s row names `LightingSync
          // → LightNode/RenderSettings` and this is that call, made against
          // the identical stage a real window would build.
          sync.sync(stage.scene, lighting);
          return (scene: stage.scene, camera: stage.camera);
        },
      );

      await expectMatchesGolden(frame, 'test/goldens/scene-lit.png');
    });
  });
}
