/// The one piece of arithmetic between a phone's sensor and the engine.
///
///     flutter test test/head_pose_test.dart
///
/// **Three frames meet here and none of them is the engine's**, which is why
/// this file exists at all: Android reports a rotation into east-north-up, the
/// engine has Y up and looks down its own −Z, and the screen is a quarter turn
/// from the device the moment the phone is held sideways. Every wrong answer in
/// that reconciliation still produces a picture — one that pitches when it
/// should roll, or turns the wrong way — so the checks below are stated as
/// where the camera ends up looking rather than as quaternion components.
library;

import 'dart:math' as math;

import 'package:flutter3d_stereo/flutter3d_stereo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Where a camera with this rotation looks, in world space.
///
/// **Through the rotation matrix, and not through `Quaternion.rotate`.** The
/// two disagree: in `vector_math`, `rotate` applies the transpose of what
/// `asRotationMatrix` builds, and it is the matrix that a `SceneNode` puts a
/// camera through. A check written with `rotate` passes on a pose that would
/// point the camera the other way, which is a test that agrees with itself and
/// with nothing else.
Vector3 forwardOf(Quaternion rotation) =>
    rotation.asRotationMatrix().transformed(Vector3(0.0, 0.0, -1.0))
      ..normalize();

/// Which way is up for a camera with this rotation.
Vector3 upOf(Quaternion rotation) =>
    rotation.asRotationMatrix().transformed(Vector3(0.0, 1.0, 0.0))
      ..normalize();

void expectVector(Vector3 actual, Vector3 expected, {String? reason}) {
  expect(actual.x, closeTo(expected.x, 1e-6), reason: reason);
  expect(actual.y, closeTo(expected.y, 1e-6), reason: reason);
  expect(actual.z, closeTo(expected.z, 1e-6), reason: reason);
}

/// The sensor's own reading for a device whose axes sit like this in the world.
List<double> sensorFrom(Quaternion rotation) =>
    <double>[rotation.x, rotation.y, rotation.z, rotation.w];

void main() {
  group('a phone lying flat on a table, screen up', () {
    // The sensor's identity: device X east, device Y north, device Z up. The
    // camera looks out of the *back* of the phone, so it looks at the table.
    final rotation = headRotationFromSensor(<double>[0.0, 0.0, 0.0, 1.0]);

    test('looks straight down', () {
      expectVector(forwardOf(rotation), Vector3(0.0, -1.0, 0.0));
    });

    test('has the top of the phone pointing the way the world faces', () {
      // North is the engine's forward, so a phone whose top points north has
      // its up-on-screen pointing along −Z.
      expectVector(upOf(rotation), Vector3(0.0, 0.0, -1.0));
    });
  });

  group('a phone held upright, screen towards the face', () {
    // Device X still east, the top of the phone up, the back of it north.
    final sensor = Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2);
    final rotation = headRotationFromSensor(sensorFrom(sensor));

    test('looks where the back of the phone points', () {
      expectVector(forwardOf(rotation), Vector3(0.0, 0.0, -1.0));
    });

    test('and keeps up where up is', () {
      expectVector(upOf(rotation), Vector3(0.0, 1.0, 0.0));
    });

    test('turning on the spot turns the view by the same angle', () {
      // A quarter turn to the left about the world's vertical — which for the
      // sensor is east-north-*up*, so about Z.
      final turned =
          Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), math.pi / 2) * sensor;
      final looked = forwardOf(headRotationFromSensor(sensorFrom(turned)));
      // North was −Z; a quarter turn to the left faces west, which is −X.
      expectVector(looked, Vector3(-1.0, 0.0, 0.0));
    });
  });

  group('the display being turned is not the head turning', () {
    final sensor = Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2);

    test('landscape rolls the picture and leaves the gaze alone', () {
      final rotation = headRotationFromSensor(
        sensorFrom(sensor),
        displayRotationDegrees: 90,
      );
      expectVector(
        forwardOf(rotation),
        Vector3(0.0, 0.0, -1.0),
        reason: 'the phone points where it pointed',
      );
      expectVector(
        upOf(rotation),
        Vector3(1.0, 0.0, 0.0),
        reason: 'what was up the screen now runs across the world',
      );
    });

    test('a full turn of the display is the same picture', () {
      final noTurn = headRotationFromSensor(sensorFrom(sensor));
      final fullTurn = headRotationFromSensor(
        sensorFrom(sensor),
        displayRotationDegrees: 360,
      );
      expectVector(forwardOf(fullTurn), forwardOf(noTurn));
      expectVector(upOf(fullTurn), upOf(noTurn));
    });
  });

  group('the reading as it arrives', () {
    test('a three-value vector gets its scalar back', () {
      final sensor = Quaternion.axisAngle(
        Vector3(0.0, 1.0, 0.0),
        0.7,
      )..normalize();
      final withScalar = headRotationFromSensor(sensorFrom(sensor));
      final without = headRotationFromSensor(<double>[
        sensor.x,
        sensor.y,
        sensor.z,
      ]);
      // Android leaves the scalar out on older devices; it is a square root
      // away, and dropping it silently would tilt everything by a little.
      expectVector(forwardOf(without), forwardOf(withScalar));
    });

    test('a vector rounded past one is still a rotation', () {
      // Three floats whose squares sum to a hair over one: the naive square
      // root is of a negative number, and NaN propagates all the way to a
      // camera that draws nothing.
      final rotation = headRotationFromSensor(<double>[
        0.5773503,
        0.5773503,
        0.5773503,
      ]);
      expect(forwardOf(rotation).length, closeTo(1.0, 1e-6));
    });

    test('the payload is the vector then the display rotation', () {
      final pose = decodeSensorEvent(<double>[0.0, 0.0, 0.0, 1.0, 0.0]);
      expectVector(forwardOf(pose.rotation), Vector3(0.0, -1.0, 0.0));
      expect(pose.position, Vector3.zero());
    });

    test('a three-value payload is four numbers, not five', () {
      final pose = decodeSensorEvent(<double>[0.0, 0.0, 0.0, 90.0]);
      // Scalar reconstructed as one, so this is the flat-on-the-table case
      // again, rolled by the display.
      expectVector(forwardOf(pose.rotation), Vector3(0.0, -1.0, 0.0));
    });

    test('too few numbers is refused rather than guessed at', () {
      expect(
        () => decodeSensorEvent(<double>[0.0, 0.0, 0.0]),
        throwsArgumentError,
      );
      expect(
        () => headRotationFromSensor(<double>[0.0, 0.0]),
        throwsArgumentError,
      );
    });
  });
}
