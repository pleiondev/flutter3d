import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

ParticleEffect _effect({
  int count = 10,
  Range lifetime = const Range.exact(1.0),
  Range size = const Range.exact(0.5),
  List<ParticleAffector> affectors = const <ParticleAffector>[],
  ParticleEmitter? emitter,
}) => ParticleEffect(
  count: count,
  emitter: emitter ?? const SphereEmitter(speed: Range.exact(1.0)),
  lifetime: lifetime,
  size: size,
  color: Vector4(1.0, 0.5, 0.2, 1.0),
  affectors: affectors,
);

void main() {
  _glowCentreTests();

  group('the pool', () {
    test('a burst does not inherit the previous occupant of its slot', () {
      // The bug this pins: `_initialise` set every field a particle is born
      // with *except* `source`, and `burst` calls only `_initialise`. So a slot
      // vacated by a torch's flame handed its `LightEmitter` to whatever landed
      // there next, and `step` accumulated the newcomer into that torch's glow.
      // In the dungeon a rocket detonating near a wall brightened the torch on
      // it, which reads as the explosion lighting the room — plausible, and
      // nothing to do with the light that was actually cast.
      final system = ParticleSystem(capacity: 4, random: math.Random(1));
      final torch = _Torch();

      // Fill every slot from the torch, then let them all die.
      system.emitFor(
        torch,
        _effect(count: 1, lifetime: const Range.exact(0.1)),
        Vector3.zero(),
        1.0,
        perSecond: 40.0,
      );
      expect(system.aliveCount, 4, reason: 'the pool should be full');
      system.step(0.2);
      expect(system.aliveCount, 0);

      // A burst now reuses those slots. Nothing it emits belongs to the torch.
      system.burst(
        _effect(count: 4, lifetime: const Range.exact(1.0)),
        Vector3.zero(),
      );
      torch.glow.beginStep();
      system.step(1 / 60);
      expect(
        torch.glow.count,
        0,
        reason:
            'the burst was accumulated into the torch that used to own '
            'those slots',
      );
    });

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

  group('a fixed step makes the frame rate stop mattering', () {
    /// Emits at [perSecond] for one simulated second at [hz], and reports where
    /// the particles ended up.
    List<double> runAt(double hz, {double perSecond = 30.0}) {
      final system = ParticleSystem(capacity: 512, random: math.Random(5));
      const key = _Torchless();
      final effect = _effect(
        count: 1,
        lifetime: const Range.exact(10.0),
        emitter: const SphereEmitter(speed: Range.exact(1.0)),
        affectors: const <ParticleAffector>[ParticleGravity(-10.0)],
      );
      system.emit(key, effect, Vector3.zero(), perSecond: perSecond);
      final dt = 1.0 / hz;
      for (var i = 0; i < hz.round(); i++) {
        system.advance(dt);
      }

      final vertices = Float32List(
        system.aliveCount * ParticleSystem.floatsPerParticle,
      );
      final indices = Uint32List(system.aliveCount * 6);
      final written = system.writeQuads(
        Vector3(1.0, 0.0, 0.0),
        Vector3(0.0, 1.0, 0.0),
        vertices,
        indices,
      );
      // The height of each particle's first corner, sorted, so two runs can be
      // compared without depending on emission order.
      final ys = <double>[
        for (var i = 0; i < written; i++)
          vertices[i * ParticleSystem.floatsPerParticle + 1],
      ]..sort();
      return ys;
    }

    test('the same number of particles, whatever the frame rate', () {
      // The count was already frame-rate independent — the fractional
      // remainder saw to that. This is the half that worked.
      expect(runAt(30).length, closeTo(runAt(120).length, 1));
      expect(runAt(60).length, closeTo(runAt(120).length, 1));
    });

    test('and they are spread the same way, which is the half that did not', () {
      // A frame's worth of particles used to be born at the instant the frame
      // began, so at 30 Hz they arrived in four fat clumps a second and at
      // 120 Hz in sixteen thin ones. Under gravity that shows as the spread of
      // heights: the clumps land in bands.
      final slow = runAt(30);
      final fast = runAt(120);

      double spread(List<double> ys) => ys.last - ys.first;
      expect(
        spread(slow),
        closeTo(spread(fast), 0.05),
        reason:
            'the particles occupy a different depth of column at 30 Hz '
            'than at 120, which is emission clumping',
      );
    });

    test('a stopped emitter stops', () {
      final system = ParticleSystem(capacity: 64, random: math.Random(5));
      const key = _Torchless();
      system.emit(
        key,
        _effect(count: 1, lifetime: const Range.exact(10.0)),
        Vector3.zero(),
        perSecond: 60.0,
      );
      system.advance(0.5);
      final lit = system.aliveCount;
      expect(lit, greaterThan(0));

      system.stopEmitting(key);
      system.advance(0.5);
      expect(
        system.aliveCount,
        lit,
        reason: 'nothing new should have been emitted',
      );
    });

    test('a stalled frame does not try to catch up for ever', () {
      // A debugger pause hands this several seconds. Simulating all of it takes
      // longer than the stall did and never finishes.
      final system = ParticleSystem(capacity: 4096, random: math.Random(5));
      system.emit(
        const _Torchless(),
        _effect(count: 1, lifetime: const Range.exact(10.0)),
        Vector3.zero(),
        perSecond: 600.0,
      );

      final watch = Stopwatch()..start();
      system.advance(30.0);
      watch.stop();

      expect(
        system.aliveCount,
        lessThan(200),
        reason:
            'thirty seconds of emission were simulated rather than '
            'dropped',
      );
    });
  });

  group('randomness belongs to the particle', () {
    List<double> quadsOf(ParticleSystem system) {
      final vertices = Float32List(
        system.aliveCount * ParticleSystem.floatsPerParticle,
      );
      final indices = Uint32List(system.aliveCount * 6);
      final written = system.writeQuads(
        Vector3(1.0, 0.0, 0.0),
        Vector3(0.0, 1.0, 0.0),
        vertices,
        indices,
      );
      return vertices.sublist(0, written * ParticleSystem.floatsPerParticle);
    }

    test('the same seed and steps give byte-identical particles', () {
      // What a golden of a burning torch needs, and what the wall-clock
      // `emitFor` could never provide.
      List<double> run() {
        final system = ParticleSystem(capacity: 128, seed: 4242);
        system.emit(
          const _Torchless(),
          _effect(count: 1, lifetime: const Range.exact(2.0)),
          Vector3.zero(),
          perSecond: 40.0,
        );
        for (var i = 0; i < 30; i++) {
          system.advance(1 / 60);
        }
        return quadsOf(system);
      }

      expect(run(), run());
    });

    test('two seeds do not', () {
      List<double> run(int seed) {
        final system = ParticleSystem(capacity: 128, seed: seed);
        system.burst(_effect(count: 20), Vector3.zero());
        // Stepped, or every particle sits on the origin and the only thing
        // the seed decided — its direction — has not moved it anywhere yet.
        system.step(1 / 60);
        return quadsOf(system);
      }

      expect(run(1), isNot(run(2)));
    });

    test('drawing one more number moves one particle, not all of them', () {
      // The property the per-particle streams exist for. With one shared
      // generator, an emitter taking an extra draw shifted every particle born
      // after it — so adding a feature moved every golden with particles in
      // it, for a reason unrelated to the feature.
      // A *sampled* size, not an exact one: with `Range.exact` nothing is
      // drawn for it and the comparison below would hold however the streams
      // were arranged. The first version of this test made exactly that
      // mistake and passed against a single shared generator.
      const spread = Range(0.2, 0.9);

      final plain = ParticleSystem(capacity: 64, seed: 7);
      plain.burst(
        _effect(
          count: 8,
          size: spread,
          emitter: const SphereEmitter(speed: Range.exact(1.0)),
        ),
        Vector3.zero(),
      );

      final greedy = ParticleSystem(capacity: 64, seed: 7);
      greedy.burst(
        _effect(count: 8, size: spread, emitter: const _GreedyEmitter()),
        Vector3.zero(),
      );

      plain.step(1 / 60);
      greedy.step(1 / 60);
      final a = quadsOf(plain);
      final b = quadsOf(greedy);
      expect(a, hasLength(b.length));

      // Every particle's *lifetime and size* come from the birth stream, which
      // the emitter's extra draw must not have touched. Sizes are the quad's
      // half-extent, readable as the spread between two opposite corners.
      const floats = ParticleSystem.floatsPerParticle;
      for (var i = 0; i < a.length ~/ floats; i++) {
        final sizeA = (a[i * floats + 18] - a[i * floats]).abs();
        final sizeB = (b[i * floats + 18] - b[i * floats]).abs();
        expect(
          sizeB,
          closeTo(sizeA, 1e-6),
          reason:
              'particle \$i changed size because the *emitter* took an '
              'extra random number',
        );
      }
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
      expect(positions.last - positions[positions.length - 20], lessThan(0.05));
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

/// A stand-in for something whose particles are its light, like a torch.
/// Where a glow says its fire is, and when it is entitled to say so.
///
/// Split out because `centre` was computed every step for months and read by
/// nobody, so nothing would have noticed if it had been wrong — and the value
/// it holds before the first particle exists is the world origin, which is the
/// one value that must never reach a light.
void _glowCentreTests() {
  group('a glow', () {
    test('does not claim a position before it has seen a particle', () {
      final system = ParticleSystem(capacity: 64, seed: 3);
      final torch = _Torch();
      expect(torch.glow.located, isFalse);

      // A step with nothing emitted must not promote the origin into an
      // answer. This is the whole guard: a light following an unlocated glow
      // sits at (0, 0, 0), which in a level is inside something.
      system.advance(1.0 / 60.0);
      expect(torch.glow.located, isFalse);
    });

    test(
      'jumps to the first measurement rather than easing in from nowhere',
      () {
        final system = ParticleSystem(capacity: 64, seed: 3);
        final torch = _Torch();
        final origin = Vector3(12.0, 3.0, -7.0);
        system.emit(torch, _effect(count: 1), origin, perSecond: 240.0);
        system.advance(1.0 / 60.0);

        expect(torch.glow.located, isTrue);
        // Within the burst's own spread of the emitter, not a tenth of the way
        // there from the origin — which is what an exponential ease from zero
        // would give on the first step, and would drag the light across the
        // level over the following tenth of a second.
        expect(
          (torch.glow.centre - origin).length,
          lessThan(1.0),
          reason: 'the first measurement is taken, not blended with (0, 0, 0)',
        );
      },
    );

    test('a torch that is put out stops casting light', () {
      // The bug: `stopEmitting` removed the emitter from the measured set, so
      // nothing called `beginStep` on its glow again and the glow froze at
      // whatever it last read. The flame died on screen and the light it cast
      // stayed at full — a room lit by a torch that is visibly out.
      //
      // Found by a test written for something else entirely, which reported a
      // count of 22 live particles for a system in which everything had died.
      final system = ParticleSystem(capacity: 256, seed: 11);
      final torch = _Torch();
      system.emit(
        torch,
        _effect(count: 1, lifetime: const Range.exact(0.1)),
        Vector3(4.0, 1.0, 0.0),
        perSecond: 300.0,
      );
      system.advance(0.5);
      expect(torch.glow.power, greaterThan(0.0), reason: 'it should be lit');

      system.stopEmitting(torch);
      for (var i = 0; i < 60; i++) {
        system.advance(1.0 / 60.0);
      }
      expect(torch.glow.count, 0);
      expect(
        torch.glow.power,
        lessThan(1e-4),
        reason: 'the light outlived the fire that was measured to produce it',
      );
    });

    test('keeps its last position through a gap with no particles', () {
      // `count` drops to zero whenever a step catches a gap between particles.
      // A light that read `count` instead of `located` would snap back to the
      // origin on those steps and strobe.
      final system = ParticleSystem(capacity: 64, seed: 3);
      final torch = _Torch();
      final origin = Vector3(12.0, 3.0, -7.0);
      system.emit(
        torch,
        _effect(count: 1, lifetime: const Range.exact(0.05)),
        origin,
        perSecond: 240.0,
      );
      system.advance(1.0 / 60.0);
      final settled = torch.glow.centre.clone();

      system.stopEmitting(torch);
      for (var i = 0; i < 30; i++) {
        system.advance(1.0 / 60.0);
      }
      expect(torch.glow.count, 0, reason: 'everything should have died');
      expect(torch.glow.located, isTrue);
      // Near where it was, and nowhere near the origin. Not exactly where it
      // was: the last particles kept moving under their own velocity for the
      // few steps it took them to die, and the centre followed them, which is
      // correct. The failure being guarded against is a snap back to (0, 0, 0),
      // which from here would be a jump of fourteen metres.
      expect((torch.glow.centre - settled).length, lessThan(0.5));
      expect(
        torch.glow.centre.length,
        greaterThan(10.0),
        reason: 'the centre fell back to the world origin',
      );
    });
  });
}

class _Torch with LightEmitter {}

/// A source that is not a light, for keying a standing emission.
final class _Torchless {
  const _Torchless();
}

/// An emitter that draws one more number than [SphereEmitter] does.
///
/// Stands in for adding a feature: with one shared generator this shifted every
/// particle born after it.
final class _GreedyEmitter extends ParticleEmitter {
  const _GreedyEmitter();

  @override
  void emit(
    Particle particle,
    Vector3 origin,
    Vector3 direction,
    math.Random random,
  ) {
    random.nextDouble(); // the extra draw
    randomDirection(particle.velocity, random);
    particle.velocity.scale(1.0);
    particle.position.setFrom(origin);
  }
}
