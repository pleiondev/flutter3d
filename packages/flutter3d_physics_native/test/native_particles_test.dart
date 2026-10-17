// Particles on the CPU — P9, phase 10: the core's own. On a GPU they are
// held to these in `flutter3d_effects/test/visual_workloads_test.dart`.
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A thousand particles thrown every way from a grid above a floor.
List<NativeParticle> _spray() => <NativeParticle>[
  for (var i = 0; i < 1000; i++)
    NativeParticle(
      position: Vector3(
        (i % 10).toDouble(),
        1.0 + (i % 7) * 0.1,
        (i ~/ 100).toDouble(),
      ),
      velocity: Vector3(
        ((i * 37) % 11) - 5.0,
        ((i * 13) % 9).toDouble(),
        ((i * 7) % 5) - 2.0,
      ),
      life: 0.5 + (i % 30) * 0.1,
    ),
];

final ParticleForces _weather = ParticleForces(
  wind: Vector3(2.0, 0.0, 1.0),
  drag: 0.5,
  floorY: 0.0,
  restitution: 0.6,
  friction: 0.2,
);

void main() {
  test('a spark flies as semi-implicit Euler sums, and dies', () {
    final p = NativeParticles(2);
    addTearDown(p.dispose);
    p.emit(<NativeParticle>[
      NativeParticle(
        position: Vector3.zero(),
        velocity: Vector3(3.0, 4.0, 0.0),
        life: 0.49,
      ),
    ]);
    // It lives thirty steps of a sixtieth, then stays where it died.
    p.step(ParticleCloudStep(forces: ParticleForces(), dt: 1 / 60, steps: 60));
    final out = p.read();
    const h = 1 / 60;
    expect(out[0], closeTo(3.0 * 30 * h, 1e-5));
    expect(out[1], closeTo(4.0 * 30 * h - 9.81 * h * h * 30 * 31 / 2, 1e-5));
    expect(out[3], closeTo(0.49 - 30 * h, 1e-5));
    // The second slot was never alive.
    expect(out[4], 0.0);
    expect(p.capacity, 2);
  });

  test('a floor turns a fall back, and the spray settles on it', () {
    final p = NativeParticles(1000);
    addTearDown(p.dispose);
    p.emit(_spray());
    p.step(ParticleCloudStep(forces: _weather, dt: 1 / 60, steps: 120));
    final out = p.read();
    for (var i = 0; i < 1000; i++) {
      expect(out[i * 4 + 1], greaterThanOrEqualTo(0.0), reason: 'particle $i');
    }
  });

  test('a disposed set says so', () {
    final p = NativeParticles(4)..dispose();
    expect(() => p.read(), throwsStateError);
    p.dispose();
    expect(() => NativeParticles(0), throwsArgumentError);
  });
}
