/// `edu-07b`: `LessonView` actually moves a real, decoded glTF model
/// between steps, through the same `nodes`/`restPositions` `main.dart`
/// builds from `ModelVisuals` — `prop_offsets_test.dart`'s own proof,
/// extended from a procedural box to a real file read off disk, decoded on
/// a background isolate and uploaded, the same as any shipping level's
/// `type: "model"` entity.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_lesson_viewer/src/lesson_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

GraphicsDevice _device() => CpuDevice(
  width: 16,
  height: 8,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    "tapping Next applies step-2's offsets to a real, decoded model's "
    'root, and tapping Previous puts it back at rest',
    (tester) async {
      final device = _device();
      final renderer = Renderer.create(device: device);
      final scene = Scene();
      final camera = CameraNode(name: 'eye');
      scene.add(camera);

      final models = ModelVisuals(
        scene,
        device: device,
        source: FileAssetSource.new,
      );
      addTearDown(models.dispose);
      // `tester.runAsync`, not a bare `await`: `decodeModelInIsolate` spawns
      // a real isolate and waits on a real `ReceivePort`, and the automated
      // test binding's fake clock never services that on its own —
      // `widget_surface_visuals_test.dart`'s own `tickAll` proof already
      // needed the same wrapper for the same reason.
      await tester.runAsync(
        () => models.add(
          EntityDef(
            type: 'model',
            name: 'crate',
            position: Vector3(0.0, 0.6, 0.0),
            properties: const <String, Object?>{
              'asset': '../../packages/flutter3d_samples/assets/Box.glb',
            },
          ),
        ),
      );

      final player = LessonPlayer(<EntityDef>[
        EntityDef(
          type: 'edu_step',
          name: 'step-1',
          position: Vector3(2.5, 1.6, 2.5),
          properties: const <String, Object?>{'caption': 'Whole engine'},
        ),
        EntityDef(
          type: 'edu_step',
          name: 'step-2',
          position: Vector3(1.6, 1.8, -0.6),
          properties: <String, Object?>{
            'caption': 'Cover removed',
            'offsets': <String, Object?>{
              'crate': <double>[0.0, 0.6, 0.0],
            },
          },
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: LessonView(
            renderer: renderer,
            scene: scene,
            camera: camera,
            player: player,
            nodes: models.nodes,
            restPositions: models.restPositions,
          ),
        ),
      );
      await tester.pump();

      final crate = models.nodes['crate']!;
      expect(
        crate.readWorldPosition().y,
        closeTo(0.6, 1e-6),
        reason: 'step-1 names no offset for it: rest position',
      );

      await tester.tap(find.byTooltip('Next step'));
      await tester.pump();

      expect(
        crate.readWorldPosition().y,
        closeTo(1.2, 1e-6),
        reason: 'step-2: rest 0.6 + offset 0.6',
      );

      await tester.tap(find.byTooltip('Previous step'));
      await tester.pump();

      expect(
        crate.readWorldPosition().y,
        closeTo(0.6, 1e-6),
        reason:
            'back at step-1, so back at rest — offsets is full state, '
            'not a diff that stays applied',
      );
    },
  );
}
