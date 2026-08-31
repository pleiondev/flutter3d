/// The lights a level owns, and the two claims their doc comments make.
///
/// Untested until now, and both claims are the kind that hold for a while and
/// then quietly stop: *"a value computed from the time is the same on every
/// machine and after every reload, which is what lets a golden hold still"*,
/// and — from the entity that spawns them — that the seed comes from the
/// position *"so a row of torches never pulses in unison"*.
///
/// A third is the interesting one at run time: a fixture whose light is
/// measured from its own particles must stop running its behaviour, because
/// two generators of one number disagree eventually and the disagreement reads
/// as a flame burning while its light is out.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('a flame', () {
    test('gives the same number for the same time, always', () {
      // Determinism is what the goldens rest on. Anything reaching for a random
      // number here makes a reference image that cannot be reproduced.
      const flame = FlameFlicker();
      for (final t in <double>[0.0, 0.37, 1.5, 96.25]) {
        expect(flame.at(t, 0.4), flame.at(t, 0.4));
      }
      // And a second instance agrees with the first: no hidden state.
      expect(const FlameFlicker().at(2.5, 0.4), flame.at(2.5, 0.4));
    });

    test('two seeds do not flicker in unison', () {
      // The tell this exists to avoid: a corridor of torches pulsing together,
      // which reads as the room breathing rather than as fire.
      const flame = FlameFlicker();
      var apart = 0;
      for (var i = 0; i < 120; i++) {
        final t = i / 60.0;
        if ((flame.at(t, 0.1) - flame.at(t, 0.8)).abs() > 0.01) apart++;
      }
      expect(apart, greaterThan(60),
          reason: 'the seed does not reach the phase, so every torch in the '
              'level flickers as one');
    });

    test('stays inside its stated depth', () {
      // `depth` is documented as how far it dips below full, from 0 to 1. A
      // wobble that overshoots makes a light brighter than the level asked for,
      // which is invisible until a bloom threshold turns it into a flare.
      const flame = FlameFlicker(depth: 0.3);
      for (var i = 0; i < 600; i++) {
        final value = flame.at(i / 60.0, 0.55);
        expect(value, lessThanOrEqualTo(1.0));
        expect(value, greaterThanOrEqualTo(0.7 - 1e-9));
      }
    });
  });

  group('a pulse', () {
    // **The behaviour no level could ask for.** `PulseLight` was written
    // alongside the other two and then had no property that reached it: the
    // lamp kind read `flicker` and nothing else, so a swell was expressible in
    // Dart and not in a document, which is the same as not existing.
    test('swells and dips rather than flickering', () {
      const pulse = PulseLight(period: 4.0);

      // A whole period apart is the same brightness; a half period apart is
      // not. That is what makes it a swell rather than noise.
      expect(pulse.at(0.0, 0.0), closeTo(pulse.at(4.0, 0.0), 1e-9));
      expect((pulse.at(1.0, 0.0) - pulse.at(3.0, 0.0)).abs(),
          greaterThan(0.1));
    });

    test('and never goes darker than its depth', () {
      // Mutation: drop the `1.0 -` and the light inverts — the lamp is dark
      // when it should be bright, which reads as a lamp that is broken rather
      // than a lamp that pulses.
      const pulse = PulseLight(depth: 0.4);
      for (var t = 0.0; t < 8.0; t += 0.05) {
        final at = pulse.at(t, 0.13);
        expect(at, lessThanOrEqualTo(1.0 + 1e-9));
        expect(at, greaterThanOrEqualTo(0.6 - 1e-9));
      }
    });

    test('a row of them does not pulse in unison', () {
      // The same claim the flame makes, and it has to hold for both or a
      // corridor of lamps becomes one big lamp.
      const pulse = PulseLight();
      expect(pulse.at(1.0, 0.0), isNot(closeTo(pulse.at(1.0, 0.5), 0.01)));
    });
  });

  group('a fixture', () {
    LightFixture make({LightBehaviour? behaviour, bool enabled = true}) =>
        LightFixture(
          light: 'torch_1',
          behaviour: behaviour ?? const FlameFlicker(),
          seed: 0.25,
          enabled: enabled,
        );

    test('follows its behaviour until something measures it', () {
      final fixture = make();
      expect(fixture.isMeasured, isFalse);

      fixture.step(1.0 / 60.0);
      final own = fixture.brightness;

      fixture.measure(0.5);
      expect(fixture.isMeasured, isTrue);
      expect(fixture.brightness, closeTo(0.5, 1e-9));

      // And the behaviour must not take it back on the next step. Two
      // generators of one number is the failure this guards.
      fixture.step(1.0 / 60.0);
      expect(fixture.brightness, closeTo(0.5, 1e-9),
          reason: 'the behaviour overwrote a measured brightness, so the light '
              'and the fire it comes from now disagree');
      expect(own, isNot(closeTo(0.5, 1e-9)),
          reason: 'the behaviour and the measurement happened to agree, so this '
              'test could not tell them apart');
    });

    test('a fixture that is off is dark, measured or not', () {
      final off = make(enabled: false);
      off.step(1.0 / 60.0);
      expect(off.brightness, 0.0);

      off.measure(1.0);
      expect(off.brightness, 0.0,
          reason: 'a switched-off torch lit itself by burning');
    });

    test('a measurement outside zero and one is clamped', () {
      final fixture = make();
      fixture.measure(4.0);
      expect(fixture.brightness, 1.0);
      fixture.measure(-1.0);
      expect(fixture.brightness, 0.0);
    });

    test('the measured position is copied, not held', () {
      // The caller's vector is a live buffer the particle system rewrites every
      // step. Holding it would make this fixture's idea of where its fire is
      // change underneath whoever reads it.
      final fixture = make();
      final live = Vector3(1.0, 2.0, 3.0);
      fixture.measure(0.5, at: live);

      live.setValues(90.0, 90.0, 90.0);

      expect(fixture.measuredAt!.x, 1.0,
          reason: 'the fixture kept the caller\'s vector rather than its value');
    });

    test('nothing measured means no position at all', () {
      expect(make().measuredAt, isNull);
    });
  });
}
