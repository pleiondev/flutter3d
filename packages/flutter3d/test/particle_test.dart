import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/src/engine/particles/particle.dart';
import 'package:flutter3d/src/engine/particles/particle_affector.dart';
import 'package:flutter3d/src/engine/particles/particle_emitter.dart';
import 'package:flutter3d/src/engine/particles/particle_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

ParticleEffect _effect({
  int count = 10,
  Range lifetime = const Range.exact(1.0),
  Range size = const Range.exact(0.5),
  List<ParticleAffector> affectors = const <ParticleAffector>[],
  ParticleEmitter? emitter,
}) =>
    ParticleEffect(
      count: count,
      emitter: emitter ?? const SphereEmitter(speed: Range.exact(1.0)),
      lifetime: lifetime,
      size: size,
      color: Vector4(1.0, 0.5, 0.2, 1.0),
      affectors: affectors,
    );

void main() {
  group('the pool', () {
    test('a burst emits what it asked for', () {
      final system = ParticleSystem(capacity: 64, random: math.Random(1));

      expect(system.burst(_effect(count: 10), Vector3.zero()), 10);
      expect(system.aliveCount, 10);
    });

    test('particles die at the end of their life', () {
      final system = ParticleSystem(capacity: 64, random: math.Random(1));
      system.burst(_effect(lifetime: const Range.exact(0.2)), Vector3.zero());

      // Comfortably past the lifetime: twelve steps of a sixtieth come to
      // 0.19999999999999998, which is not 0.2, and a test balanced on that is
      // a test that fails on a different machine.
      for (var i = 0; i < 20; i++) {
        system.step(_dt);
      }

      expect(system.aliveCount, 0);
    });

    test('a full pool drops the rest and counts them', () {
      final system = ParticleSystem(capacity: 8, random: math.Random(1));

      expect(system.burst(_effect(count: 20), Vector3.zero()), 8);
      expect(system.aliveCount, 8);
      expect(system.dropped, 12);
    });

    test('slots are reused once their particles are gone', () {
      final system = ParticleSystem(capacity: 8, random: math.Random(1));
      system.burst(
        _effect(count: 8, lifetime: const Range.exact(0.1)),
        Vector3.zero(),
      );
      for (var i = 0; i < 8; i++) {
        system.step(_dt);
      }

      expect(system.burst(_effect(count: 8), Vector3.zero()), 8);
      expect(system.dropped, 0);
    });

    test('two effects share one pool without disturbing each other', () {
      // The reason there is one system rather than one per effect: everything
      // additive shares a buffer, so an explosion and its smoke are one draw.
      final system = ParticleSystem(capacity: 64, random: math.Random(1));
      system.burst(
        _effect(count: 5, lifetime: const Range.exact(0.1)),
        Vector3.zero(),
      );
      system.burst(
        _effect(count: 5, lifetime: const Range.exact(5.0)),
        Vector3(10.0, 0.0, 0.0),
      );

      for (var i = 0; i < 10; i++) {
        system.step(_dt);
      }

      // The short-lived half is gone and the long-lived half is not.
      expect(system.aliveCount, 5);
    });

    test('a zero or negative step changes nothing', () {
      final system = ParticleSystem(capacity: 8, random: math.Random(1));
      system.burst(_effect(count: 4), Vector3.zero());

      system.step(0.0);
      system.step(-1.0);

      expect(system.aliveCount, 4);
    });
  });

  group('affectors compose', () {
    test('gravity pulls a particle down', () {
      final system = ParticleSystem(capacity: 4, random: math.Random(1));
      system.burst(
        _effect(
          count: 1,
          emitter: const SphereEmitter(speed: Range.exact(0.0)),
          affectors: const <ParticleAffector>[ParticleGravity(-10.0)],
          lifetime: const Range.exact(10.0),
        ),
        Vector3.zero(),
      );

      for (var i = 0; i < 60; i++) {
        system.step(_dt);
      }

      final vertices = Float32List(ParticleSystem.floatsPerParticle);
      final indices = Uint32List(6);
      system.writeQuads(
        Vector3(1.0, 0.0, 0.0),
        Vector3(0.0, 1.0, 0.0),
        vertices,
        indices,
      );

      // A second of ten metres per second squared is about five metres down.
      expect(vertices[1], lessThan(-3.0));
    });

    test('drag slows a particle without reversing it', () {
      // Linear drag reaches zero and then pushes backwards, which is a very
      // recognisable bug.
      final system = ParticleSystem(capacity: 4, random: math.Random(1));
      system.burst(
        _effect(
          count: 1,
          emitter: const SphereEmitter(speed: Range.exact(10.0)),
          affectors: const <ParticleAffector>[ParticleDrag(20.0)],
          lifetime: const Range.exact(10.0),
        ),
        Vector3.zero(),
      );

      final positions = <double>[];
      final vertices = Float32List(ParticleSystem.floatsPerParticle);
      final indices = Uint32List(6);
      for (var i = 0; i < 120; i++) {
        system.step(_dt);
        system.writeQuads(
          Vector3(1.0, 0.0, 0.0),
          Vector3(0.0, 1.0, 0.0),
          vertices,
          indices,
        );
        // The centre, from two opposite corners. Measuring a corner instead
        // adds a constant offset to a moving point, and the distance of that
        // from the origin is not monotonic even when the particle's is.
        final cx = (vertices[0] + vertices[18]) * 0.5;
        final cy = (vertices[1] + vertices[19]) * 0.5;
        final cz = (vertices[2] + vertices[20]) * 0.5;
        positions.add(math.sqrt(cx * cx + cy * cy + cz * cz));
      }

      // Monotonically further from where it started, and settling.
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i], greaterThanOrEqualTo(positions[i - 1] - 1e-6));
      }
      expect(
        positions.last - positions[positions.length - 20],
        lessThan(0.05),
      );
    });

    test('a fade reaches zero brightness and not before it should', () {
      final system = ParticleSystem(capacity: 4, random: math.Random(1));
      system.burst(
        _effect(
          count: 1,
          affectors: const <ParticleAffector>[ParticleFade(startsAt: 0.5)],
          lifetime: const Range.exact(1.0),
        ),
        Vector3.zero(),
      );

      final vertices = Float32List(ParticleSystem.floatsPerParticle);
      final indices = Uint32List(6);

      // A quarter of the way through: untouched.
      for (var i = 0; i < 15; i++) {
        system.step(_dt);
      }
      system.writeQuads(
        Vector3(1.0, 0.0, 0.0),
        Vector3(0.0, 1.0, 0.0),
        vertices,
        indices,
      );
      expect(vertices[6], closeTo(1.0, 1e-6));

      // Nearly over: almost gone.
      for (var i = 0; i < 43; i++) {
        system.step(_dt);
      }
      system.writeQuads(
        Vector3(1.0, 0.0, 0.0),
        Vector3(0.0, 1.0, 0.0),
        vertices,
        indices,
      );
      expect(vertices[6], lessThan(0.1));
    });

    test('a size ramp does not compound itself away', () {
      // Scaling the current size every step instead of the birth size shrinks a
      // particle meant to halve over a second to nothing in a tenth of one.
      final system = ParticleSystem(capacity: 4, random: math.Random(1));
      system.burst(
        _effect(
          count: 1,
          size: const Range.exact(2.0),
          affectors: const <ParticleAffector>[
            ParticleSizeOverLife(from: 1.0, to: 0.5),
          ],
          lifetime: const Range.exact(1.0),
        ),
        Vector3.zero(),
      );

      for (var i = 0; i < 30; i++) {
        system.step(_dt);
      }

      final vertices = Float32List(ParticleSystem.floatsPerParticle);
      final indices = Uint32List(6);
      system.writeQuads(
        Vector3(1.0, 0.0, 0.0),
        Vector3(0.0, 1.0, 0.0),
        vertices,
        indices,
      );
      // Halfway through, so three quarters of the original two metres, and the
      // quad spans that whole width.
      final width = vertices[9] - vertices[0];
      expect(width, closeTo(1.5, 0.1));
    });

    test('affectors run in the order they are listed', () {
      // A fade after a colour ramp dims the ramped colour; before it, the ramp
      // overwrites the fade. Both are legitimate, so the order has to be the
      // one the caller wrote.
      final system = ParticleSystem(capacity: 4, random: math.Random(1));
      system.burst(
        ParticleEffect(
          count: 1,
          emitter: const SphereEmitter(speed: Range.exact(0.0)),
          lifetime: const Range.exact(1.0),
          size: const Range.exact(1.0),
          color: Vector4(1.0, 1.0, 1.0, 1.0),
          affectors: <ParticleAffector>[
            ParticleColorOverLife(
              Vector4(1.0, 1.0, 1.0, 1.0),
              Vector4(1.0, 0.0, 0.0, 1.0),
            ),
            const ParticleFade(),
          ],
        ),
        Vector3.zero(),
      );

      for (var i = 0; i < 30; i++) {
        system.step(_dt);
      }

      final vertices = Float32List(ParticleSystem.floatsPerParticle);
      final indices = Uint32List(6);
      system.writeQuads(
        Vector3(1.0, 0.0, 0.0),
        Vector3(0.0, 1.0, 0.0),
        vertices,
        indices,
      );

      // Halfway: colour half towards red, brightness half gone. If the fade ran
      // first the ramp would have reset the alpha to one.
      expect(vertices[4], closeTo(0.5, 0.05));
      expect(vertices[6], closeTo(0.5, 0.05));
    });
  });

  group('emitters', () {
    test('a sphere throws particles in every direction', () {
      final system = ParticleSystem(capacity: 256, random: math.Random(7));
      system.burst(
        _effect(
          count: 200,
          emitter: const SphereEmitter(speed: Range.exact(5.0)),
          lifetime: const Range.exact(10.0),
        ),
        Vector3.zero(),
      );
      for (var i = 0; i < 30; i++) {
        system.step(_dt);
      }

      final vertices = Float32List(200 * ParticleSystem.floatsPerParticle);
      final indices = Uint32List(200 * 6);
      final written = system.writeQuads(
        Vector3(1.0, 0.0, 0.0),
        Vector3(0.0, 1.0, 0.0),
        vertices,
        indices,
      );

      var minX = double.infinity, maxX = -double.infinity;
      var minY = double.infinity, maxY = -double.infinity;
      var minZ = double.infinity, maxZ = -double.infinity;
      for (var i = 0; i < written; i++) {
        final at = i * ParticleSystem.floatsPerParticle;
        minX = math.min(minX, vertices[at]);
        maxX = math.max(maxX, vertices[at]);
        minY = math.min(minY, vertices[at + 1]);
        maxY = math.max(maxY, vertices[at + 1]);
        minZ = math.min(minZ, vertices[at + 2]);
        maxZ = math.max(maxZ, vertices[at + 2]);
      }

      // Spread on all three axes: a distribution built the naive way clumps.
      expect(maxX - minX, greaterThan(3.0));
      expect(maxY - minY, greaterThan(3.0));
      expect(maxZ - minZ, greaterThan(3.0));
    });

    test('a cone keeps its particles roughly on the axis it was given', () {
      final system = ParticleSystem(capacity: 128, random: math.Random(3));
      final axis = Vector3(0.0, 0.0, -1.0);
      system.burst(
        _effect(
          count: 100,
          emitter: const ConeEmitter(
            speed: Range.exact(5.0),
            halfAngleDegrees: 20.0,
          ),
          lifetime: const Range.exact(10.0),
        ),
        Vector3.zero(),
        direction: axis,
      );
      for (var i = 0; i < 30; i++) {
        system.step(_dt);
      }

      final vertices = Float32List(100 * ParticleSystem.floatsPerParticle);
      final indices = Uint32List(100 * 6);
      final written = system.writeQuads(
        Vector3(1.0, 0.0, 0.0),
        Vector3(0.0, 1.0, 0.0),
        vertices,
        indices,
      );

      for (var i = 0; i < written; i++) {
        final at = i * ParticleSystem.floatsPerParticle;
        // Every particle went the way the cone was pointed.
        expect(vertices[at + 2], lessThan(0.0));
      }
    });
  });

  group('writing quads', () {
    test('each particle becomes four vertices and two triangles', () {
      final system = ParticleSystem(capacity: 8, random: math.Random(1));
      system.burst(_effect(count: 3), Vector3.zero());

      final vertices = Float32List(8 * ParticleSystem.floatsPerParticle);
      final indices = Uint32List(8 * 6);
      final written = system.writeQuads(
        Vector3(1.0, 0.0, 0.0),
        Vector3(0.0, 1.0, 0.0),
        vertices,
        indices,
      );

      expect(written, 3);
      // The last quad's indices point at the last four vertices.
      expect(indices[12], 8);
      expect(indices[17], 11);
    });

    test('the quad faces the axes it is handed', () {
      final system = ParticleSystem(capacity: 4, random: math.Random(1));
      system.burst(
        _effect(
          count: 1,
          size: const Range.exact(2.0),
          emitter: const SphereEmitter(speed: Range.exact(0.0)),
        ),
        Vector3.zero(),
      );

      final vertices = Float32List(ParticleSystem.floatsPerParticle);
      final indices = Uint32List(6);
      // Right along Z, up along X: an unusual pair, so a hardcoded axis shows.
      system.writeQuads(
        Vector3(0.0, 0.0, 1.0),
        Vector3(1.0, 0.0, 0.0),
        vertices,
        indices,
      );

      // The corner at (-1, -1) sits one metre back along both.
      expect(vertices[0], closeTo(-1.0, 1e-6));
      expect(vertices[2], closeTo(-1.0, 1e-6));
      expect(vertices[1], closeTo(0.0, 1e-6));
    });

    test('a buffer too small stops rather than overruns', () {
      final system = ParticleSystem(capacity: 64, random: math.Random(1));
      system.burst(_effect(count: 40), Vector3.zero());

      final vertices = Float32List(5 * ParticleSystem.floatsPerParticle);
      final indices = Uint32List(5 * 6);

      expect(
        system.writeQuads(
          Vector3(1.0, 0.0, 0.0),
          Vector3(0.0, 1.0, 0.0),
          vertices,
          indices,
        ),
        5,
      );
    });

    test('nothing is written for an empty system', () {
      final system = ParticleSystem(capacity: 8, random: math.Random(1));
      final vertices = Float32List(8 * ParticleSystem.floatsPerParticle);
      final indices = Uint32List(8 * 6);

      expect(
        system.writeQuads(
          Vector3(1.0, 0.0, 0.0),
          Vector3(0.0, 1.0, 0.0),
          vertices,
          indices,
        ),
        0,
      );
    });
  });
}
