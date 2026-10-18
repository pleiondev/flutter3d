/// The platformer's photo mode — `N8`: which keys it takes, and which it
/// leaves to the camera it flies.
///
///     flutter test test/photo_mode_test.dart
library;

import 'package:flutter/material.dart' show KeyEventResult;
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_demo_platformer/src/photo_mode.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

KeyDownEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: key,
  timeStamp: Duration.zero,
);

PhotoMode _open() => runnerPhotoMode()
  ..enter(
    world: CollisionWorld()..update(),
    eye: Vector3(0.0, 2.0, 5.0),
    target: Vector3.zero(),
    anchor: Vector3(0.0, 1.0, 3.0),
    fieldOfView: 1.05,
  );

void main() {
  // Enter asks the keyboard whether Shift is held.
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'brackets step through the filters, and Enter asks for a 2x picture',
    () {
      final mode = _open();
      final asked = <int>[];
      void capture(int scale) => asked.add(scale);

      mode.key(_down(LogicalKeyboardKey.bracketRight), onCapture: capture);
      expect(mode.filter, PhotoFilter.all[1]);
      mode.key(_down(LogicalKeyboardKey.bracketLeft), onCapture: capture);
      mode.key(_down(LogicalKeyboardKey.bracketLeft), onCapture: capture);
      expect(mode.filter, PhotoFilter.all.last, reason: 'and wraps round');

      mode.key(_down(LogicalKeyboardKey.enter), onCapture: capture);
      expect(asked, <int>[2]);
    },
  );

  test('the arrows are left to fly the camera', () {
    // Mutation: put the filters back on the arrows. The arrows are bound to
    // moving left and right, and in photo mode they stop flying the camera
    // and flick through filters instead.
    final mode = _open();
    expect(
      mode.key(_down(LogicalKeyboardKey.arrowLeft), onCapture: (_) {}),
      isNull,
    );
    expect(mode.filter, PhotoFilter.none);
  });

  test('a closed photo mode takes no keys, and a busy one takes them all', () {
    final closed = runnerPhotoMode();
    expect(
      closed.key(_down(LogicalKeyboardKey.enter), onCapture: (_) {}),
      isNull,
    );
    // Mutation: drop the `busy` check. A second Enter while a 4x picture is
    // drawing starts another capture on the same renderer.
    final asked = <int>[];
    final busy = _open()..isBusy = true;
    expect(
      busy.key(_down(LogicalKeyboardKey.enter), onCapture: asked.add),
      KeyEventResult.handled,
    );
    expect(asked, isEmpty);
  });

  test('the held run keys fly the camera, and the node follows it', () {
    final mode = _open();
    final input = InputState()..press(GameAction.moveForward);
    final node = CameraNode(projection: const PerspectiveProjection());
    mode
      ..fly(0.5, input: input, look: Vector2.zero())
      ..applyTo(node);
    // Two metres along the view, which looks from (0, 2, 5) at the origin.
    expect(node.readPosition().z, lessThan(5.0 - 1.0));
    expect(node.readPosition().y, lessThan(2.0));
  });
}
