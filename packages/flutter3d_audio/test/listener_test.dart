/// The listener's orientation, and the convention that was hiding in it.
library;

import 'dart:math' as math;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('aiming along a direction pans the same way aiming by yaw does', () {
    // The two must agree where they overlap, or the new method is a second
    // convention rather than an escape from the first. A first-person yaw of 0
    // looks along -Z, so that is the direction to hand the other one.
    final byYaw = AudioListener()..aimAt(Vector3.zero(), 0.0);
    final byDirection = AudioListener()
      ..aimAlong(Vector3.zero(), Vector3(0.0, 0.0, -1.0));

    expect(byDirection.forward.x, closeTo(byYaw.forward.x, 1e-9));
    expect(byDirection.forward.z, closeTo(byYaw.forward.z, 1e-9));
    expect(byDirection.right.x, closeTo(byYaw.right.x, 1e-9));
    expect(byDirection.right.z, closeTo(byYaw.right.z, 1e-9));
  });

  test('a third-person forward needs no half turn', () {
    // Mutation: implement `aimAlong` by calling `aimAt(at, atan2(...))`. It
    // comes back mirrored, which is the bug this method exists to make
    // impossible — a listener facing the other way pans every sound to the
    // wrong ear and nobody suspects the audio code.
    final camera = Vector3(math.sin(0.0), 0.0, math.cos(0.0));
    final ears = AudioListener()..aimAlong(Vector3.zero(), camera);

    expect(ears.forward.z, closeTo(1.0, 1e-9));
    // Something off to the world's -X is on the listener's right when facing
    // +Z, because right is `cross(forward, up)`.
    expect(ears.right.x, closeTo(-1.0, 1e-9));
  });

  test('a vertical direction does not produce a zero listener', () {
    // Looking straight down flattens to nothing. Falling back to a fixed
    // forward beats normalising a zero vector, which is how a footstep ends up
    // hard left for one frame.
    final ears = AudioListener()
      ..aimAlong(Vector3.zero(), Vector3(0.0, -1.0, 0.0));
    expect(ears.forward.length, closeTo(1.0, 1e-9));
  });
}
