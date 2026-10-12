import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('an effect is const, its colour a LinearColor', () {
    const effect = ParticleEffect(
      count: 1,
      emitter: SphereEmitter(speed: Range.exact(0.0)),
      lifetime: Range.exact(1.0),
      size: Range.exact(1.0),
      color: LinearColor(1.0, 0.5, 0.25, 0.8),
    );
    expect(effect.color, const LinearColor(1.0, 0.5, 0.25, 0.8));
  });

  test('a gradient blends LinearColor keys in linear light', () {
    final out = Vector4.zero();
    ParticleGradient.linear(
      const LinearColor(0.0, 0.0, 0.0, 1.0),
      const LinearColor(1.0, 0.5, 0.25, 0.0),
    ).sampleInto(out, 0.5);
    expect(out.x, closeTo(0.5, 1e-6));
    expect(out.y, closeTo(0.25, 1e-6));
    expect(out.z, closeTo(0.125, 1e-6));
    expect(out.w, closeTo(0.5, 1e-6));

    ParticleGradient.constant(
      const LinearColor(0.2, 0.3, 0.4),
    ).sampleInto(out, 0.7);
    expect(out.w, 1.0);
    expect(
      const GradientKey(0.5, LinearColor(1.0, 1.0, 1.0)).color,
      LinearColor.white,
    );
  });

  test('a colour over life runs from one LinearColor to another', () {
    final particle = Particle()
      ..age = 0.25
      ..lifetime = 1.0;
    ParticleColorOverLife(
      const LinearColor(0.0, 0.0, 0.0, 1.0),
      const LinearColor(1.0, 1.0, 1.0, 1.0),
    ).apply(ParticleStep(particle: particle, dt: 1.0 / 60.0));
    expect(particle.color.x, closeTo(0.25, 1e-6));
    expect(particle.color.w, closeTo(1.0, 1e-6));
  });
}
