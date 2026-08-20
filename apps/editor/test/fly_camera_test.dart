/// A camera that goes where it is told and stops for nothing.
///
///     flutter test test/fly_camera_test.dart
library;

import 'dart:math' as math;

import 'package:editor/src/fly_camera.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const GameAction _forward = GameAction('flyForward');
const GameAction _back = GameAction('flyBack');
const GameAction _left = GameAction('flyLeft');
const GameAction _right = GameAction('flyRight');
const GameAction _down = GameAction('flyDown');
const GameAction _up = GameAction('flyUp');
const GameAction _fast = GameAction('flyFast');

void _fly(FlyCamera camera, InputState input, {double seconds = 1.0}) =>
    camera.step(
      seconds,
      input,
      forward: _forward,
      back: _back,
      left: _left,
      right: _right,
      down: _down,
      up: _up,
      fast: _fast,
    );

void main() {
  test('flying forward goes where it is looking', () {
    final camera = FlyCamera(at: Vector3.zero(), pitch: 0.0);
    final input = InputState()..press(_forward);

    _fly(camera, input);

    expect(camera.position.z, closeTo(-camera.speed, 1e-6),
        reason: 'a camera at rest looks down -Z, as every node here does');
    expect(camera.position.x, closeTo(0.0, 1e-6));
  });

  test('and turning ninety degrees turns what forward means', () {
    final camera = FlyCamera(at: Vector3.zero(), yaw: math.pi / 2, pitch: 0.0);
    final input = InputState()..press(_forward);

    _fly(camera, input);

    expect(camera.position.x, closeTo(camera.speed, 1e-5));
    expect(camera.position.z, closeTo(0.0, 1e-5));
  });

  test('and up is up whatever it is looking at', () {
    // An editor flying to the top of a tower wants to go up, not forwards while
    // pointing up — which is what a camera-relative rise gives you and is
    // unusable the moment the camera is tilted at all.
    final camera = FlyCamera(at: Vector3.zero(), pitch: -1.2);
    final input = InputState()..press(_up);

    _fly(camera, input);

    expect(camera.position.y, closeTo(camera.speed, 1e-6));
    expect(camera.position.z, closeTo(0.0, 1e-6));
  });

  test('and shift is the difference between a level and a brush', () {
    // A level is a hundred metres across and a brush is two, so one speed is
    // either a crawl across the level or an overshoot at the brush.
    final slow = FlyCamera(at: Vector3.zero(), pitch: 0.0);
    _fly(slow, InputState()..press(_forward));

    final fast = FlyCamera(at: Vector3.zero(), pitch: 0.0);
    _fly(
      fast,
      InputState()
        ..press(_forward)
        ..press(_fast),
    );

    expect(fast.position.length, greaterThan(slow.position.length * 2.0));
  });

  test('and looking up stops short of straight up', () {
    // At exactly vertical the horizontal direction stops existing and the view
    // rolls, which is a camera nobody can aim.
    final camera = FlyCamera(pitch: 0.0);

    camera.look(Vector2(0.0, -100000.0));

    expect(camera.pitch, lessThan(math.pi / 2));
    expect(camera.forward.length, closeTo(1.0, 1e-6));
    expect(camera.right.y, closeTo(0.0, 1e-9),
        reason: 'the horizon is rolling');
  });

  test('and the horizon stays level however far it is tilted', () {
    // The right vector is built across the world's up rather than the camera's,
    // and this is what that buys: a view that does not roll as it tilts.
    final camera = FlyCamera(at: Vector3.zero(), pitch: -0.9, yaw: 2.1);

    camera.look(Vector2.zero());
    final input = InputState()..press(_right);
    _fly(camera, input);

    expect(camera.position.y, closeTo(0.0, 1e-6),
        reason: 'strafing sideways changed the height');
  });
}
