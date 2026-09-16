/// The two things the viewport learnt to do with a pointer that is not
/// dragging a tool: `ux-04`'s free-look on the right button, and `ux-11`'s
/// transform driven by a pointer with nothing held.
///
///     flutter test test/viewport_look_and_modal_test.dart
///
/// Through the real widget rather than through `OrbitGestures` alone: what
/// these rows changed is which pointer event means what, and that decision is
/// made in the widget.
library;

import 'package:flutter/gestures.dart' hide Matrix4;
import 'package:flutter/material.dart' hide Material, Matrix4;
import 'package:flutter/services.dart' hide Matrix4;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/element_picking.dart';
import 'package:flutter3d_modeler/src/modeler_viewport.dart';
import 'package:flutter3d_modeler/src/settings.dart' show NavigationScheme;
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

ModelProject oneCube() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'cube',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: Matrix4.identity(),
  ),
);

/// Rebuilds the viewport when it changes — what the real screen's own frame
/// loop does sixty times a second, and what a test has to do by hand for
/// anything the viewport reads per frame (`ux-04`'s walk keys).
final ValueNotifier<int> repaint = ValueNotifier<int>(0);

/// One frame of the application: the widget rebuilt, and time moved on.
Future<void> frame(WidgetTester tester) async {
  repaint.value++;
  await tester.pump(const Duration(milliseconds: 16));
}

/// A viewport in a window, with whatever the test is asking about wired.
Future<ModelerStage> pumpViewport(
  WidgetTester tester, {
  NavigationScheme navigation = NavigationScheme.leftDragOrbit,
  bool toolFollowsPointer = false,
  void Function(Offset delta, Offset at)? onDragTool,
  VoidCallback? onToolConfirm,
  VoidCallback? onToolCancel,
}) async {
  repaint.value = 0;
  final it = cpuTestDevice(width: 64, height: 64);
  final ModelerStage stage = ModelerStage.fromProject(
    device: it.device,
    project: oneCube(),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: ValueListenableBuilder<int>(
            valueListenable: repaint,
            builder: (BuildContext context, int _, Widget? _) =>
                ModelerViewport(
                  renderer: Renderer.create(device: it.device),
                  stage: stage,
                  onFrame: () {},
                  navigation: navigation,
                  toolFollowsPointer: toolFollowsPointer,
                  onToolConfirm: onToolConfirm,
                  onToolCancel: onToolCancel,
                  onDragTool: onDragTool == null
                      ? null
                      : (Offset delta, double _, PickingView _, Offset at) =>
                            onDragTool(delta, at),
                ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return stage;
}

/// Where the camera stands, read off the node the controller drove.
Vector3 eyeOf(ModelerStage stage) => stage.camera.readWorldPosition();

void main() {
  group('ux-04: the right button is free-look', () {
    testWidgets('it turns the head and leaves the camera where it stands', (
      WidgetTester tester,
    ) async {
      final ModelerStage stage = await pumpViewport(tester);
      final Vector3 before = eyeOf(stage).clone();
      final Vector3 targetBefore = stage.orbit.target.clone();

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(ModelerViewport)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // Mutation: answer a right drag with an orbit. The camera swings round
      // the model instead of turning where it is, which is the thing the
      // other buttons already do.
      expect((eyeOf(stage) - before).length, lessThan(1e-4));
      expect((stage.orbit.target - targetBefore).length, greaterThan(0.1));
    });

    testWidgets('and the walk keys move the camera while it is held', (
      WidgetTester tester,
    ) async {
      final ModelerStage stage = await pumpViewport(tester);
      final Vector3 before = eyeOf(stage).clone();

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(ModelerViewport)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await simulateKeyDownEvent(LogicalKeyboardKey.keyW);
      // Several frames: the first has no interval behind it to walk through,
      // and the rest are each worth the time since the one before.
      for (var step = 0; step < 6; step++) {
        await frame(tester);
      }
      await simulateKeyUpEvent(LogicalKeyboardKey.keyW);
      await gesture.up();
      await tester.pump();

      // Mutation: read the keys as key events rather than per frame. A key
      // held then walks once per repeat — at whatever rate the person's own
      // machine repeats at — instead of continuously.
      expect((eyeOf(stage) - before).length, greaterThan(0.05));
    });

    testWidgets('and stops the moment the button comes up', (
      WidgetTester tester,
    ) async {
      final ModelerStage stage = await pumpViewport(tester);

      await simulateKeyDownEvent(LogicalKeyboardKey.keyW);
      await frame(tester);
      final Vector3 before = eyeOf(stage).clone();
      for (var step = 0; step < 6; step++) {
        await frame(tester);
      }
      await simulateKeyUpEvent(LogicalKeyboardKey.keyW);

      // Nothing is holding free-look open, so `W` is the application's own
      // key and the camera is not walking.
      expect((eyeOf(stage) - before).length, lessThan(1e-9));
    });

    testWidgets('and under the other scheme it moves nothing', (
      WidgetTester tester,
    ) async {
      final ModelerStage stage = await pumpViewport(
        tester,
        navigation: NavigationScheme.middleMouseOrbit,
      );
      final Vector3 before = eyeOf(stage).clone();
      final Vector3 targetBefore = stage.orbit.target.clone();

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(ModelerViewport)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // There the right button is the context menu's: the left belongs to the
      // tools and the middle to the camera, so this is the only button left
      // for a menu and a second camera must not take it.
      expect((eyeOf(stage) - before).length, lessThan(1e-9));
      expect((stage.orbit.target - targetBefore).length, lessThan(1e-9));
    });
  });

  group('ux-11: a transform the pointer drives with nothing held', () {
    testWidgets('a hover is the drag', (WidgetTester tester) async {
      final drags = <Offset>[];
      await pumpViewport(
        tester,
        toolFollowsPointer: true,
        onDragTool: (Offset delta, Offset _) => drags.add(delta),
      );

      final TestGesture pointer = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await pointer.addPointer(
        location: tester.getCenter(find.byType(ModelerViewport)),
      );
      addTearDown(pointer.removePointer);
      await tester.pump();
      await pointer.moveBy(const Offset(25, 0));
      await tester.pump();

      // Mutation: report a drag only while a button is held, which is what
      // this did. A transform started from `G` then waits for a click before
      // anything moves, which is not the flow the key belongs to.
      expect(drags, isNotEmpty);
      expect(
        drags.fold<double>(0, (double sum, Offset it) => sum + it.dx),
        closeTo(25, 0.5),
      );
    });

    testWidgets('the left button accepts and the right throws away', (
      WidgetTester tester,
    ) async {
      var confirmed = 0;
      var cancelled = 0;
      await pumpViewport(
        tester,
        toolFollowsPointer: true,
        onToolConfirm: () => confirmed++,
        onToolCancel: () => cancelled++,
      );
      final Offset middle = tester.getCenter(find.byType(ModelerViewport));

      await tester.tapAt(middle);
      await tester.pump();
      expect(confirmed, 1);
      expect(cancelled, 0);

      final TestGesture right = await tester.startGesture(
        middle,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await right.up();
      await tester.pump();

      // Mutation: leave the buttons to the camera and the picker. A press
      // then orbits, or picks something else, in the middle of a transform
      // somebody is aiming.
      expect(cancelled, 1);
      expect(confirmed, 1);
    });
  });
}
