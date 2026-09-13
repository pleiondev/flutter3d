/// `edu-02`: the button on [LessonView] actually drives the camera and the
/// caption — not just wired to a callback that compiles, but proven to move
/// a real (headless) scene, the same [CpuDevice]
/// `flutter3d_stereo/test/lesson_stereo_view_test.dart` already uses to
/// avoid a GPU. That file is this one's template, `StereoSurface`/
/// `StereoRig` swapped for `SceneSurface`/`CameraNode`.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_lesson_viewer/src/lesson_view.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

GraphicsDevice _device() =>
    CpuDevice(width: 16, height: 8, shaders: CpuShaderLibrary(builtinCpuShaders()));

List<EntityDef> _steps() => <EntityDef>[
  EntityDef(
    type: 'edu_step',
    name: 'step-1',
    position: Vector3(0.0, 1.6, 3.0),
    properties: <String, Object?>{
      'caption': 'First',
      'visible': <String>['part'],
    },
  ),
  EntityDef(
    type: 'edu_step',
    name: 'step-2',
    position: Vector3(1.0, 1.6, 3.0),
    properties: <String, Object?>{
      'caption': 'Second',
      'hidden': <String>['part'],
    },
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `main.dart`'s `LessonReady` branch returns this widget with no
  // `Scaffold` around it — found live, not by any of the tests above, none
  // of whose fixture steps carry a `check`. `MaterialApp(home: LessonView(...))`
  // here is that same bare tree, on purpose, not `Scaffold(body: ...)`.
  testWidgets(
    "a step with a check renders without needing a caller-supplied Material "
    '(main.dart provides none)',
    (tester) async {
      final device = _device();
      final renderer = Renderer.create(device: device);
      final scene = Scene();
      final camera = CameraNode(name: 'eye');
      scene.add(camera);
      final player = LessonPlayer(<EntityDef>[
        EntityDef(
          type: 'edu_step',
          name: 'quiz',
          position: Vector3(0.0, 1.6, 3.0),
          properties: <String, Object?>{
            'caption': 'Quiz',
            'check': <String, Object?>{
              'question': 'Q',
              'answers': <String>['a'],
              'attempts': 2,
            },
          },
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: LessonView(renderer: renderer, scene: scene, camera: camera, player: player),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'a');
      await tester.tap(find.byTooltip('Submit answer'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Верно.'), findsOneWidget);
    },
  );

  testWidgets('tapping Next moves the camera, hides the part step-2 hides, '
      'and swaps the caption', (tester) async {
    final device = _device();
    final renderer = Renderer.create(device: device);
    final scene = Scene();
    final camera = CameraNode(name: 'eye');
    scene.add(camera);
    final part = SceneNode(name: 'part');
    scene.add(part);
    final player = LessonPlayer(_steps());

    await tester.pumpWidget(
      MaterialApp(
        home: LessonView(
          renderer: renderer,
          scene: scene,
          camera: camera,
          player: player,
          nodes: <String, SceneNode>{'part': part},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('First'), findsOneWidget);
    expect(part.visible, isTrue, reason: 'step-1 shows it');
    final beforeX = camera.readWorldPosition().x;

    await tester.tap(find.byTooltip('Next step'));
    await tester.pump();

    expect(find.text('Second'), findsOneWidget);
    expect(part.visible, isFalse, reason: 'step-2 hides it');
    final afterX = camera.readWorldPosition().x;
    expect(afterX - beforeX, closeTo(1.0, 1e-6));
  });

  testWidgets(
    'a one-finger drag orbits the camera, and a later frame does not snap '
    'it back to the step',
    (tester) async {
      final device = _device();
      final renderer = Renderer.create(device: device);
      final scene = Scene();
      final camera = CameraNode(name: 'eye');
      scene.add(camera);
      final player = LessonPlayer(_steps());

      await tester.pumpWidget(
        MaterialApp(
          home: LessonView(renderer: renderer, scene: scene, camera: camera, player: player),
        ),
      );
      await tester.pump();

      final stepPosition = camera.readWorldPosition().clone();

      // `warnIfMissed: false`: the finder's own render box sits under several
      // semantics/opacity layers `flutter_test` cannot see through, but the
      // hit test at that point does reach this widget's `Listener` ancestor
      // — confirmed by the assertion below actually passing, not asserted.
      await tester.drag(
        find.byType(SceneSurface),
        const Offset(120.0, 0.0),
        warnIfMissed: false,
      );
      await tester.pump();
      // A second frame with nothing touching the camera again — the
      // regression this guards: `onBeforeFrame` used to re-run
      // `LessonPlayer.applyCurrent` every frame, which undid a drag before
      // its next paint landed.
      await tester.pump();

      final draggedPosition = camera.readWorldPosition();
      expect((draggedPosition - stepPosition).length, greaterThan(0.01));
    },
  );

  testWidgets(
    'a trackpad pinch (PointerScaleEvent) zooms the camera — the actual '
    'event a real trackpad sends, found only by instrumenting a live '
    'browser: not a PointerScrollEvent and not a PointerPanZoomUpdateEvent',
    (tester) async {
      final device = _device();
      final renderer = Renderer.create(device: device);
      final scene = Scene();
      final camera = CameraNode(name: 'eye');
      scene.add(camera);
      final player = LessonPlayer(_steps());

      await tester.pumpWidget(
        MaterialApp(
          home: LessonView(renderer: renderer, scene: scene, camera: camera, player: player),
        ),
      );
      await tester.pump();

      final before = camera.readWorldPosition().clone();
      final center = tester.getCenter(find.byType(SceneSurface));

      GestureBinding.instance.handlePointerEvent(
        PointerScaleEvent(position: center, scale: 1.2),
      );
      await tester.pump();

      expect((camera.readWorldPosition() - before).length, greaterThan(0.001));
    },
  );

  testWidgets('the Previous button is disabled on the first step', (
    tester,
  ) async {
    final device = _device();
    final renderer = Renderer.create(device: device);
    final scene = Scene();
    final camera = CameraNode(name: 'eye');
    scene.add(camera);

    await tester.pumpWidget(
      MaterialApp(
        home: LessonView(
          renderer: renderer,
          scene: scene,
          camera: camera,
          player: LessonPlayer(_steps()),
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_back),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('the Next button is disabled on the last step', (tester) async {
    final device = _device();
    final renderer = Renderer.create(device: device);
    final scene = Scene();
    final camera = CameraNode(name: 'eye');
    scene.add(camera);

    await tester.pumpWidget(
      MaterialApp(
        home: LessonView(
          renderer: renderer,
          scene: scene,
          camera: camera,
          player: LessonPlayer(_steps(), start: 1),
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_forward),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('an empty lesson shows no caption and both buttons disabled', (
    tester,
  ) async {
    final device = _device();
    final renderer = Renderer.create(device: device);
    final scene = Scene();
    final camera = CameraNode(name: 'eye');
    scene.add(camera);

    await tester.pumpWidget(
      MaterialApp(
        home: LessonView(
          renderer: renderer,
          scene: scene,
          camera: camera,
          player: LessonPlayer(const <EntityDef>[]),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Text), findsNothing);
    final back = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_back),
    );
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_forward),
    );
    expect(back.onPressed, isNull);
    expect(next.onPressed, isNull);
  });
}
