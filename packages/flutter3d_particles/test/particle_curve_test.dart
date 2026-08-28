/// Curves, gradients, the flow field, and the box.
///
/// Each of these was written against a claim in a doc comment rather than
/// against the code as typed — the ease convention, the hold-rather-than-
/// extrapolate rule, the divergence of the flow field. A test that only
/// restates the implementation passes when the implementation is wrong.
library;

import 'dart:math' as math;

import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A particle placed where a test wants it, since nothing here needs a system.
Particle _at(Vector3 position) => Particle()..position.setFrom(position);

/// An effect whose particles outlive any test about emission, so `aliveCount`
/// counts what was emitted rather than what has not died yet.
ParticleEffect _steady() => ParticleEffect(
  count: 1,
  emitter: const SphereEmitter(speed: Range.exact(0.0)),
  lifetime: const Range.exact(1000.0),
  size: const Range.exact(0.5),
  color: Vector4(1.0, 1.0, 1.0, 1.0),
);

/// Advances [system] in 60 Hz frames, which is how a game calls it.
void _run(ParticleSystem system, double seconds, {void Function()? each}) {
  const frame = 1.0 / 60.0;
  for (var elapsed = 0.0; elapsed < seconds - 1e-9; elapsed += frame) {
    each?.call();
    system.advance(frame);
  }
}

void main() {
  group('a curve', () {
    test('holds its ends rather than extrapolating past them', () {
      // The rule the doc comment states, and the reason: a size curve that
      // kept falling past its last key would pass through zero and turn the
      // quad inside out.
      final curve = ParticleCurve(<CurveKey>[
        CurveKey(0.25, 2.0),
        CurveKey(0.75, 4.0),
      ]);
      expect(curve.sample(0.0), 2.0);
      expect(curve.sample(0.25), 2.0);
      expect(curve.sample(0.75), 4.0);
      expect(curve.sample(1.0), 4.0);
      // And the midpoint really is interpolated, so the test above is not
      // passing because everything returns an end value.
      expect(curve.sample(0.5), closeTo(3.0, 1e-12));
    });

    test('the ease belongs to the key the value leaves', () {
      // The off-by-one the library comment is about. With `step` on the FIRST
      // key, the value holds 1.0 across the whole segment and jumps at the
      // end. Under the other convention it would hold 5.0 instead, so this
      // fails loudly if the convention is ever flipped.
      final curve = ParticleCurve(<CurveKey>[
        const CurveKey(0.0, 1.0, ease: KeyEase.step),
        const CurveKey(1.0, 5.0),
      ]);
      expect(curve.sample(0.01), 1.0);
      expect(curve.sample(0.5), 1.0);
      expect(curve.sample(0.99), 1.0);
      expect(curve.sample(1.0), 5.0);
    });

    test('a smooth segment leaves and arrives at rest', () {
      final curve = ParticleCurve(<CurveKey>[
        const CurveKey(0.0, 0.0, ease: KeyEase.smooth),
        const CurveKey(1.0, 1.0),
      ]);
      // Same endpoints and midpoint as linear — which is why the endpoints
      // alone cannot tell the two apart.
      expect(curve.sample(0.0), 0.0);
      expect(curve.sample(0.5), closeTo(0.5, 1e-12));
      expect(curve.sample(1.0), 1.0);
      // The difference is in the slope. Near the ends a smooth segment moves
      // less than a straight line would; in the middle it moves more.
      expect(curve.sample(0.1), lessThan(0.1));
      expect(curve.sample(0.9), greaterThan(0.9));
      expect(curve.sample(0.4), lessThan(0.4));
    });

    test('two keys at the same point are a hard edge, not a NaN', () {
      final curve = ParticleCurve(<CurveKey>[
        const CurveKey(0.0, 1.0),
        const CurveKey(0.5, 1.0),
        const CurveKey(0.5, 9.0),
        const CurveKey(1.0, 9.0),
      ]);
      expect(curve.sample(0.25), 1.0);
      expect(curve.sample(0.75), 9.0);
      expect(
        curve.sample(0.5).isNaN,
        isFalse,
        reason:
            'a zero-width span divided through would poison everything '
            'downstream and never say where it came from',
      );
    });

    test('one key is a constant', () {
      final curve = ParticleCurve.constant(3.0);
      expect(curve.sample(0.0), 3.0);
      expect(curve.sample(1.0), 3.0);
    });

    test('unsorted keys are refused rather than sampled wrong', () {
      expect(
        () => ParticleCurve(<CurveKey>[
          const CurveKey(1.0, 0.0),
          const CurveKey(0.0, 1.0),
        ]),
        throwsA(isA<AssertionError>()),
      );
      expect(() => ParticleCurve(<CurveKey>[]), throwsA(isA<AssertionError>()));
    });
  });

  group('a gradient', () {
    test('interpolates every channel together', () {
      final gradient = ParticleGradient.linear(
        Vector4(0.0, 1.0, 0.0, 1.0),
        Vector4(1.0, 0.0, 1.0, 0.0),
      );
      final out = Vector4.zero();
      gradient.sampleInto(out, 0.5);
      expect(out.x, closeTo(0.5, 1e-12));
      expect(out.y, closeTo(0.5, 1e-12));
      expect(out.z, closeTo(0.5, 1e-12));
      expect(out.w, closeTo(0.5, 1e-12));
    });

    test('writes into the vector it was given rather than replacing it', () {
      // The allocation-free contract. If `sampleInto` ever starts returning a
      // fresh vector, the caller's colour stops changing and every particle
      // renders at its birth colour — which looks like the gradient being
      // ignored rather than like an aliasing mistake.
      final gradient = ParticleGradient.constant(Vector4(1.0, 2.0, 3.0, 4.0));
      final out = Vector4.zero();
      final same = out;
      gradient.sampleInto(out, 0.5);
      expect(identical(out, same), isTrue);
      expect(same.x, 1.0);
      expect(same.w, 4.0);
    });
  });

  group('the size curve affector', () {
    test('scales the birth size rather than the current one', () {
      // Pins the compounding bug the original size affector had: multiplying
      // the live size every step shrank a particle meant to halve over a
      // second to nothing in a tenth of one.
      final sized = ParticleSizeCurve(ParticleCurve.linear(1.0, 0.5));
      final particle = Particle()
        ..birthSize = 2.0
        ..size = 2.0
        ..lifetime = 1.0;

      particle.age = 0.5;
      sized.apply(particle, 1.0 / 60.0);
      expect(particle.size, closeTo(1.5, 1e-12));

      // Applied a second time at the same age it must give the same answer.
      sized.apply(particle, 1.0 / 60.0);
      expect(
        particle.size,
        closeTo(1.5, 1e-12),
        reason: 'the curve reads birthSize, so applying twice is idempotent',
      );
    });
  });

  group('the flow field', () {
    test('is divergence-free, which is the whole reason for choosing it', () {
      // The property the comment claims, checked numerically rather than
      // asserted. A field with divergence bunches particles into clumps and
      // leaves holes; that reads as a broken emitter, and it is the failure
      // sampling noise directly would produce.
      //
      // Divergence is measured by pushing a particle from six neighbouring
      // points and differencing the velocity the field gave each one.
      const field = ParticleTurbulence(strength: 1.0, scale: 1.0);
      const h = 1e-4;
      const dt = 1.0;

      double component(Vector3 at, int axis) {
        final particle = _at(at);
        field.apply(particle, dt);
        return particle.velocity[axis];
      }

      for (final origin in <Vector3>[
        Vector3(0.0, 0.0, 0.0),
        Vector3(1.3, -0.7, 2.1),
        Vector3(-4.0, 5.5, 0.25),
      ]) {
        var divergence = 0.0;
        for (var axis = 0; axis < 3; axis++) {
          final plus = origin.clone()..[axis] += h;
          final minus = origin.clone()..[axis] -= h;
          divergence +=
              (component(plus, axis) - component(minus, axis)) / (2.0 * h);
        }
        expect(
          divergence.abs(),
          lessThan(1e-6),
          reason: 'divergence at $origin was $divergence',
        );
      }
    });

    test(
      'actually moves a particle, so the test above is not trivially true',
      () {
        // A field of all zeroes is also divergence-free. This is what separates
        // "the property holds" from "there is no field".
        const field = ParticleTurbulence(strength: 2.0, scale: 1.0);
        final particle = _at(Vector3(1.0, 2.0, 3.0));
        field.apply(particle, 1.0 / 60.0);
        expect(particle.velocity.length, greaterThan(1e-3));
      },
    );

    test('scales with dt, so the frame rate does not change the motion', () {
      const field = ParticleTurbulence(strength: 1.0, scale: 1.0);
      final once = _at(Vector3(0.5, 0.5, 0.5));
      field.apply(once, 1.0 / 30.0);

      final twice = _at(Vector3(0.5, 0.5, 0.5));
      field.apply(twice, 1.0 / 60.0);
      field.apply(twice, 1.0 / 60.0);

      // Not exactly equal — the second half-step reads the field at the same
      // position, because this affector does not move the particle — but the
      // accumulated velocity must match.
      expect(twice.velocity.x, closeTo(once.velocity.x, 1e-12));
      expect(twice.velocity.y, closeTo(once.velocity.y, 1e-12));
      expect(twice.velocity.z, closeTo(once.velocity.z, 1e-12));
    });
  });

  group('a timed emission', () {
    test('stops itself, and a standing one does not', () {
      final timed = ParticleSystem(capacity: 4096, seed: 1);
      timed.emitTimed(
        'plume',
        _steady(),
        Vector3.zero(),
        perSecond: 100.0,
        seconds: 0.5,
      );
      _run(timed, 2.0);
      // Half a second at a hundred a second, and then nothing.
      expect(timed.aliveCount, closeTo(50, 2));

      final standing = ParticleSystem(capacity: 4096, seed: 1);
      standing.emit('torch', _steady(), Vector3.zero(), perSecond: 100.0);
      _run(standing, 2.0);
      expect(
        standing.aliveCount,
        greaterThan(150),
        reason: 'an emission with no duration runs until it is stopped',
      );
    });

    test('emits for the fraction of a sub-step it is alive for', () {
      // A duration shorter than one sub-step must not round up to a whole one.
      // At 120 Hz a sub-step is 8.3 ms, so a 4 ms emission at a thousand a
      // second is four particles and not eight.
      final system = ParticleSystem(capacity: 4096, seed: 1);
      system.emitTimed(
        'spark',
        _steady(),
        Vector3.zero(),
        perSecond: 1000.0,
        seconds: 0.004,
      );
      _run(system, 0.5);
      expect(system.aliveCount, closeTo(4, 1));
    });

    test('restarting it is a second call, and that is deliberate', () {
      // Documented behaviour rather than an accident: re-firing a rocket
      // should restart its trail. It is also why this is not a `duration`
      // argument on `emit` — that one *is* called every frame, and a countdown
      // reset every frame never reaches zero.
      final system = ParticleSystem(capacity: 4096, seed: 1);
      final effect = _steady();
      system.emitTimed(
        'plume',
        effect,
        Vector3.zero(),
        perSecond: 100.0,
        seconds: 0.5,
      );
      _run(system, 1.0);
      final first = system.aliveCount;

      system.emitTimed(
        'plume',
        effect,
        Vector3.zero(),
        perSecond: 100.0,
        seconds: 0.5,
      );
      _run(system, 1.0);
      expect(system.aliveCount, greaterThan(first + 40));
    });

    test('stopEmitting cuts it short', () {
      final system = ParticleSystem(capacity: 4096, seed: 1);
      system.emitTimed(
        'plume',
        _steady(),
        Vector3.zero(),
        perSecond: 100.0,
        seconds: 10.0,
      );
      _run(system, 0.2);
      final cut = system.aliveCount;
      system.stopEmitting('plume');
      _run(system, 1.0);
      expect(system.aliveCount, cut);
    });
  });

  group('the box emitter', () {
    test('places particles inside the box and nowhere else', () {
      final emitter = BoxEmitter(
        halfExtents: Vector3(2.0, 0.5, 3.0),
        along: Vector3(0.0, -1.0, 0.0),
        speed: const Range.exact(4.0),
      );
      final random = math.Random(7);
      final origin = Vector3(10.0, 20.0, 30.0);

      var sawSpread = false;
      for (var i = 0; i < 500; i++) {
        final particle = Particle();
        emitter.emit(particle, origin, Vector3(1.0, 0.0, 0.0), random);
        expect((particle.position.x - origin.x).abs(), lessThanOrEqualTo(2.0));
        expect((particle.position.y - origin.y).abs(), lessThanOrEqualTo(0.5));
        expect((particle.position.z - origin.z).abs(), lessThanOrEqualTo(3.0));
        if ((particle.position.x - origin.x).abs() > 1.5) sawSpread = true;
      }
      expect(
        sawSpread,
        isTrue,
        reason: 'every particle at the origin would satisfy the bounds too',
      );
    });

    test('uses its own direction rather than the burst direction', () {
      // The reason a box takes one: rain falls down, it does not fall outwards.
      final emitter = BoxEmitter(
        halfExtents: Vector3(1.0, 1.0, 1.0),
        along: Vector3(0.0, -1.0, 0.0),
        speed: const Range.exact(3.0),
      );
      final particle = Particle();
      emitter.emit(
        particle,
        Vector3.zero(),
        Vector3(1.0, 0.0, 0.0),
        math.Random(1),
      );
      expect(particle.velocity.x, 0.0);
      expect(particle.velocity.y, -3.0);
    });

    test('falls back to the burst direction when given none', () {
      final emitter = BoxEmitter(
        halfExtents: Vector3(1.0, 1.0, 1.0),
        speed: const Range.exact(2.0),
      );
      final particle = Particle();
      emitter.emit(
        particle,
        Vector3.zero(),
        Vector3(0.0, 0.0, 1.0),
        math.Random(1),
      );
      expect(particle.velocity.z, 2.0);
    });
  });
}
