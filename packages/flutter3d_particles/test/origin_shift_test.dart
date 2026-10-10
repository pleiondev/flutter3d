/// Particles in scene space follow the scene's origin, once a shift however
/// many owners ask.
///
///     dart test test/origin_shift_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart' show Scene;
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show WorldPosition;
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a system followed twice on one scene moves once a shift, until the '
      'last holder lets go', () {
    final particles = ParticleSystem(capacity: 2)
      ..burst(
        ParticleEffect(
          count: 1,
          emitter: const SphereEmitter(speed: Range.exact(0.0)),
          lifetime: const Range.exact(5.0),
          size: const Range.exact(1.0),
          color: Vector4(1.0, 1.0, 1.0, 1.0),
        ),
        Vector3(1.0, 0.0, 0.0),
      );
    double x() {
      final out = Float32List(2 * ParticleSystem.floatsPerInstance);
      particles.writeInstances(out);
      return out[0];
    }

    final scene = Scene();
    final drawn = particles.followOrigin(scene);
    final burstInto = particles.followOrigin(scene);

    // Mutation: a handler per `followOrigin` call. The two owners' handlers
    // both run, and a ten-metre shift moves the particle twenty.
    scene.shiftOrigin(const WorldPosition(10.0, 0.0, 0.0));
    expect(x(), closeTo(-9.0, 1e-4));

    // Mutation: cancel the shared handler with the first holder. The second
    // owner still wants it followed, and the particle would stay behind.
    drawn.cancel();
    drawn.cancel();
    scene.shiftOrigin(WorldPosition.origin);
    expect(x(), closeTo(1.0, 1e-4));

    burstInto.cancel();
    scene.shiftOrigin(const WorldPosition(10.0, 0.0, 0.0));
    expect(x(), closeTo(1.0, 1e-4), reason: 'nobody follows it now');
  });
}
