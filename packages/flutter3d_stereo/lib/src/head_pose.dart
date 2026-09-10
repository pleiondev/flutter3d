import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Where the head is, in the space the scene is built in.
///
/// A rotation and a position rather than a matrix, because that is the shape
/// both sources hand over: Android's rotation vector is a quaternion, and
/// OpenXR's `XrPosef` is a quaternion and a vector. Turning either into a
/// matrix is what `SceneNode` already does.
final class HeadPose {
  const HeadPose({required this.rotation, required this.position});

  HeadPose.still() : rotation = Quaternion.identity(), position = Vector3.zero();

  final Quaternion rotation;

  /// Where the head is, in metres. A phone has no idea, so it stays at the
  /// origin and only the rotation moves — which is the honest version of
  /// three-degrees-of-freedom tracking rather than a guessed neck model.
  final Vector3 position;
}

/// Android's rotation vector, in the engine's frame.
///
/// **Two frames have to be reconciled and neither is the engine's.** The sensor
/// reports a rotation from the device's own axes into the world's — east, north
/// and up — while the engine has Y up and a camera looking down its own −Z. And
/// the device's axes are the ones the screen was manufactured with, so a phone
/// held in landscape is a quarter turn away from the frame the sensor is
/// talking about.
///
/// So: [rotationVector] is `(x, y, z)` with the scalar either supplied as a
/// fourth value or reconstructed from the other three — Android sends three on
/// older devices and four on newer ones, and the caller should not have to know
/// which. [displayRotationDegrees] is what `Display.getRotation` reports, in
/// degrees, and it turns the device's frame into the screen's.
///
/// The maths is here rather than in Kotlin for the reason `pad_input` gives for
/// its own split: everything that can be got wrong should be somewhere a test
/// can reach it, and the native side should forward numbers and nothing else.
///
/// **One trap worth naming, because it cost an afternoon.** In `vector_math`,
/// `Quaternion.rotate` applies the *transpose* of what `asRotationMatrix`
/// builds — and it is the matrix that `SceneNode` puts a camera through. A pose
/// checked with `rotate` and used through a node is checked backwards, and the
/// two mistakes cancel until something looks the wrong way. The quarter turn
/// below is written as a change of basis for the same reason: columns cannot be
/// read in two senses, an angle about an axis can.
Quaternion headRotationFromSensor(
  List<double> rotationVector, {
  int displayRotationDegrees = 0,
}) {
  if (rotationVector.length < 3) {
    throw ArgumentError(
      'A rotation vector is three values, or four with the scalar; got '
      '${rotationVector.length}.',
    );
  }
  final x = rotationVector[0];
  final y = rotationVector[1];
  final z = rotationVector[2];
  // The scalar Android leaves out when the device does not send it. Clamped
  // because the three components are floats and a unit vector's squares can sum
  // to a hair over one, which is a square root of a negative number.
  final w = rotationVector.length > 3
      ? rotationVector[3]
      : math.sqrt(math.max(0.0, 1.0 - x * x - y * y - z * z));

  final sensor = Quaternion(x, y, z, w)..normalize();

  // East-north-up into the engine's frame, written as where each of the
  // world's axes ends up rather than as an angle about one of them. It is a
  // quarter turn either way depending on which convention a library's
  // `axisAngle` follows, and the columns cannot be read two ways: east stays
  // to the right, north becomes the way the camera looks, up becomes up.
  final worldFix = Quaternion.fromRotation(
    Matrix3.columns(
      Vector3(1.0, 0.0, 0.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0),
    ),
  );

  // The screen against the device it is fitted to. A rotation of the display by
  // 90 degrees is the same picture as the head turning the other way.
  final screenFix = Quaternion.axisAngle(
    Vector3(0.0, 0.0, 1.0),
    -displayRotationDegrees * math.pi / 180.0,
  );

  return (worldFix * sensor * screenFix)..normalize();
}

/// The pose behind one sensor reading.
///
/// The payload the Android side sends, decoded in one place: the rotation
/// vector's three or four values, then the display rotation in degrees.
HeadPose decodeSensorEvent(List<double> event) {
  if (event.length < 4) {
    throw ArgumentError(
      'Expected at least three rotation values and a display rotation, got '
      '${event.length} numbers.',
    );
  }
  final displayRotation = event.last.round();
  final vector = event.sublist(0, event.length - 1);
  return HeadPose(
    rotation: headRotationFromSensor(
      vector,
      displayRotationDegrees: displayRotation,
    ),
    position: Vector3.zero(),
  );
}
