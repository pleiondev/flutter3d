/// The crypt's photo mode — `N8`: which keys it takes, and which it leaves
/// to the camera it flies.
///
///     flutter test test/photo_mode_test.dart
library;

import 'package:flutter/material.dart' show KeyEventResult;
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_demo_dungeon/src/photo_mode.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart'
    show ShooterActions;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

KeyDownEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: key,
  timeStamp: Duration.zero,
);

PhotoMode _open() => cryptPhotoMode()
  ..enter(
    world: CollisionWorld()..update(),
    eye: Vector3(0.0, 2.0, 5.0),
    target: Vector3.zero(),
    fieldOfView: 1.05,
  );

void main() {
  // Enter asks the keyboard whether Shift is held.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('brackets step through the filters, and Enter asks for a 2x '
      'picture', () {
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
  });

  test('a closed photo mode takes no keys, and a busy one takes them all', () {
    // Mutation: a closed photo mode answers `handled` — Enter and the
    // brackets are taken from the game while nobody is taking a picture.
    expect(
      cryptPhotoMode().key(_down(LogicalKeyboardKey.enter), onCapture: (_) {}),
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

  test('jump flies the camera up and crouch flies it down', () {
    final mode = _open();
    final node = CameraNode();
    final input = InputState()..press(ShooterActions.crouch);
    for (var i = 0; i < 30; i++) {
      mode.fly(1 / 60, input: input, look: Vector2.zero());
    }
    mode.applyTo(node);
    // Mutation: the down axis read from `moveBack` — crouch does nothing,
    // and nothing else this game binds goes down.
    expect(node.readPosition().y, lessThan(2.0));
  });
}
