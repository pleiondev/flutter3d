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
  test('walking forward goes where it is facing', () {
    final camera = FlyCamera(at: Vector3.zero(), pitch: 0.0);
    final input = InputState()..press(_forward);

    _fly(camera, input);

    expect(camera.position.z, closeTo(-camera.speed, 1e-6),
        reason: 'a camera at rest looks down -Z, as every node here does');
    expect(camera.position.x, closeTo(0.0, 1e-6));
  });

  test('and looking at the floor does not walk into it', () {
    // **The complaint this is a fix for, in one sentence**: "I am looking at
    // the floor and W flies me through it". A camera that moves where it looks
    // is unusable in a corridor, because looking at a thing and walking past
    // another thing are two different directions — and the one edit somebody
    // makes most is to a floor, which they have to look down at to see.
    final camera = FlyCamera(at: Vector3(0.0, 5.0, 0.0), pitch: -1.2);
    final input = InputState()..press(_forward);

    _fly(camera, input);

    expect(camera.position.y, closeTo(5.0, 1e-6),
        reason: 'it walked into the floor');
    expect(camera.position.z, lessThan(-1.0),
        reason: 'it went nowhere: looking down took all the movement');
  });

  test('and looking at the ceiling does not fly off into the sky', () {
    final camera = FlyCamera(at: Vector3(0.0, 5.0, 0.0), pitch: 1.4);
    final input = InputState()..press(_forward);

    _fly(camera, input);

    expect(camera.position.y, closeTo(5.0, 1e-6));
  });

  test('and straight up still leaves a direction to walk in', () {
    // The degenerate case: with the view exactly vertical there is no
    // horizontal part of it to walk along, and the answer comes from the
    // heading instead of from nothing.
    final camera = FlyCamera(at: Vector3.zero(), yaw: 0.0, pitch: 0.0);
    camera.look(Vector2(0.0, -100000.0));
    final input = InputState()..press(_forward);

    _fly(camera, input);

    expect(camera.position.length, greaterThan(1.0),
        reason: 'it stood still because it was looking up');
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

  test('and right is to the right, which nothing here used to check', () {
    // **The bug this is written for.** `right` was `up × forward` rather than
    // `forward × up` — a camera whose right is left. Strafing went the wrong
    // way, and because `up` is built from `right`, a click ray came out rotated
    // a half turn: pointing at a wall selected whatever was behind you.
    //
    // Every test in this file passed with it, because each asked about a
    // property the mirrored vectors also have — the horizon stays level, the
    // length is one, strafing does not change height. None of them asked which
    // way.
    final camera = FlyCamera(at: Vector3.zero(), pitch: 0.0);
    final input = InputState()..press(_right);

    _fly(camera, input);

    // Facing -Z with Y up, right is +X. That is the whole assertion.
    expect(camera.position.x, closeTo(camera.speed, 1e-6));
  });

  test('and up is up, not down', () {
    final camera = FlyCamera(at: Vector3.zero(), pitch: 0.0);
    camera.look(Vector2.zero());

    expect(camera.up.y, closeTo(1.0, 1e-6));
  });

  test('and the three axes are a right-handed set', () {
    // Said once, generally: whatever the yaw and the pitch, `right` is
    // `forward × up` — which is the sentence the bug above breaks and the one
    // a reader can check.
    final camera = FlyCamera(at: Vector3.zero(), yaw: 0.9, pitch: -0.4);
    camera.look(Vector2.zero());

    final expected = camera.forward.cross(Vector3(0.0, 1.0, 0.0))..normalize();

    expect(camera.right.x, closeTo(expected.x, 1e-6));
    expect(camera.right.z, closeTo(expected.z, 1e-6));
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
