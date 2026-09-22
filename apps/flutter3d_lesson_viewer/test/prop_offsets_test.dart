/// `edu-07`: `LessonView` actually moves a real (headless) `prop` node
/// between steps, through the same `nodes`/`restPositions` `main.dart`
/// builds from `PropVisuals` — `lesson_view_test.dart`'s own "tapping Next
/// moves the camera" proof, extended to the layered-teardown half of
/// `edu-00` §6 that no lesson before this one exercised end to end.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_lesson_viewer/src/lesson_player.dart';
import 'package:flutter3d_lesson_viewer/src/lesson_view.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
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
    'tapping Next applies step-2\'s offsets to the real prop node, and '
    'tapping Previous puts it back at rest',
    (tester) async {
      final device = _device();
      final renderer = Renderer.create(device: device);
      final scene = Scene();
      final camera = CameraNode(name: 'eye');
      scene.add(camera);

      final level = Level(
        entities: <EntityDef>[
          EntityDef(
            type: 'prop',
            name: 'engine-body#valve_cover',
            position: Vector3(0.0, 0.6, 0.0),
          ),
        ],
      );
      final props = PropVisuals(scene, device: device, level: level);
      for (final entity in level.entities) {
        props.add(entity);
      }

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
              'engine-body#valve_cover': <double>[0.0, 0.6, 0.0],
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
            nodes: props.nodes,
            restPositions: props.restPositions,
          ),
        ),
      );
      await tester.pump();

      final cover = props.nodes['engine-body#valve_cover']!;
      expect(
        cover.readWorldPosition().y,
        closeTo(0.6, 1e-6),
        reason: 'step-1 names no offset for it: rest position',
      );

      await tester.tap(find.byTooltip('Next step'));
      await tester.pump();

      expect(
        cover.readWorldPosition().y,
        closeTo(1.2, 1e-6),
        reason: 'step-2: rest 0.6 + offset 0.6',
      );

      await tester.tap(find.byTooltip('Previous step'));
      await tester.pump();

      expect(
        cover.readWorldPosition().y,
        closeTo(0.6, 1e-6),
        reason:
            'back at step-1, so back at rest — offsets is full state, '
            'not a diff that stays applied',
      );
    },
  );
}
