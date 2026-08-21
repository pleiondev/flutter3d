/// The arithmetic of air, checked without a graphics device.
///
/// Everything here is a property rather than a number: a picture cannot be
/// asserted, but "the horizon and the fog are the same colour" can, and it is
/// the one that matters — if those two ever disagree the far side of the
/// circuit gets a visible seam where the ground stops, which is the single
/// ugliest thing an outdoor scene can do.
library;

import 'dart:math' as math;

import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

double _brightness(Vector3 colour) =>
    0.2126 * colour.x + 0.7152 * colour.y + 0.0722 * colour.z;

void main() {
  group('the sun', () {
    test('rises in the direction it was given', () {
      // Elevation and azimuth are what a person has an opinion about; a unit
      // vector is what the light wants. Getting the two swapped is a sun that
      // moves sideways as the hour changes.
      final low = SkyPreset.fromJson(<String, Object?>{
        'sunElevationDeg': 5.0,
        'sunAzimuthDeg': 90.0,
      });
      final high = SkyPreset.fromJson(<String, Object?>{
        'sunElevationDeg': 80.0,
        'sunAzimuthDeg': 90.0,
      });

      expect(high.directionToSun.y, greaterThan(low.directionToSun.y));
      // A loose tolerance because `Vector3` is single precision.
      expect(low.directionToSun.length, closeTo(1.0, 1e-6));
      // Ninety degrees of azimuth is due east in this frame.
      expect(low.directionToSun.x, greaterThan(0.9));
      expect(low.directionToSun.z, closeTo(0.0, 1e-6));
    });

    test('the light travels away from it', () {
      // Mutation: return `directionToSun` from `sunDirection`. Every shadow in
      // the game would fall on the wrong side of every object, and the sun
      // would light the underside of the track.
      for (final preset in SkyPresets.all) {
        expect(preset.sunDirection.dot(preset.directionToSun), lessThan(0.0),
            reason: preset.name);
      }
    });
  });

  group('the sky', () {
    test('is a colour in every direction, including straight up and down', () {
      // Mutation: divide by `direction.y` anywhere in `colourAt`. Both poles
      // are the cases a gradient written by hand tends to divide by zero at,
      // and the camera looks at both — down over the edge of an elevated
      // section, up over the crest of a hill.
      final preset = SkyPresets.golden;
      final directions = <Vector3>[
        Vector3(0.0, 1.0, 0.0),
        Vector3(0.0, -1.0, 0.0),
        Vector3.zero(),
        for (var i = 0; i < 64; i++)
          Vector3(
            math.cos(i * 0.31),
            math.sin(i * 0.7),
            math.sin(i * 0.31),
          ),
      ];

      for (final direction in directions) {
        final colour = preset.colourAt(direction);
        for (final component in <double>[colour.x, colour.y, colour.z]) {
          expect(component.isFinite, isTrue, reason: '$direction');
          expect(component, greaterThanOrEqualTo(0.0), reason: '$direction');
        }
      }
    });

    test('is brighter towards the sun than away from it', () {
      final preset = SkyPresets.golden;
      final toSun = preset.directionToSun;
      final away = Vector3(-toSun.x, toSun.y, -toSun.z);

      expect(_brightness(preset.colourAt(toSun)),
          greaterThan(_brightness(preset.colourAt(away))));
    });

    test('the zenith is the zenith and the horizon is the horizon', () {
      // With the sun well away from both, so the glow is not what is being
      // measured.
      final preset = SkyPreset.fromJson(<String, Object?>{
        'sunElevationDeg': 30.0,
        'sunAzimuthDeg': 0.0,
        'glowStrength': 0.0,
        'zenith': <double>[0.1, 0.2, 0.9],
        'horizon': <double>[0.8, 0.8, 0.8],
        'belowHorizon': <double>[0.0, 0.0, 0.0],
      });

      expect(preset.colourAt(Vector3(0.0, 1.0, 0.0)).z, closeTo(0.9, 1e-6));
      expect(preset.colourAt(Vector3(1.0, 0.0, 0.0)).x, closeTo(0.8, 1e-6));
      expect(preset.colourAt(Vector3(0.0, -1.0, 0.0)).x, closeTo(0.0, 1e-6));
    });

    test('a low sun is warm and a high one is not', () {
      // The one assertion here about what the presets are rather than about how
      // the arithmetic works: if `golden` ever stops being warm, somebody has
      // been editing numbers by feel with the game shut.
      final golden = SkyPresets.golden.horizon;
      expect(golden.x, greaterThan(golden.z), reason: 'golden hour is warm');

      final noon = SkyPresets.noon.horizon;
      expect(noon.z, greaterThan(noon.x), reason: 'midday is blue');
    });
  });

  group('the haze', () {
    test('is exactly the sky at the horizon', () {
      // The reason this file exists. The fog colour is not authored anywhere —
      // it is `colourAt` of a horizontal direction — so the ground can fade
      // into the sky and there is no number anybody can set that would put a
      // band between them.
      //
      // Mutation: give `horizonFogColour` a constant, or take the average of
      // zenith and horizon. Either way this fails, and either way the game gets
      // a visible line where the world ends.
      for (final preset in SkyPresets.all) {
        final toSun = preset.directionToSun;
        var across = Vector3(toSun.z, 0.0, -toSun.x);
        if (across.length2 < 1e-9) across = Vector3(1.0, 0.0, 0.0);

        final sky = preset.colourAt(across.normalized());
        final fog = preset.horizonFogColour;
        expect((sky - fog).length, lessThan(1e-6), reason: preset.name);
      }
    });

    test('is measured across the sun, not into it', () {
      // Mutation: take the horizon colour along `directionToSun` instead of
      // across it. The neutral haze would then carry the sun's own glow, every
      // distant object would be washed toward the sun's colour whichever way
      // the camera faced, and `inScatterAlong` would have nothing left to add.
      final preset = SkyPresets.golden;
      final toSun = preset.directionToSun;
      final flatToSun = Vector3(toSun.x, 0.0, toSun.z).normalized();

      expect(_brightness(preset.colourAt(flatToSun)),
          greaterThan(_brightness(preset.horizonFogColour)));
    });

    test('brightens into the sun and not away from it', () {
      // Mutation: return `horizonFogColour` from `inScatterAlong` and ignore
      // the view direction, which is what the engine's own fog does. The game
      // still runs and still looks fogged; it just has one grey for every
      // direction, which is the failure this whole file is here to avoid.
      final preset = SkyPresets.golden;
      final toSun = preset.directionToSun;
      final away = Vector3(-toSun.x, -toSun.y, -toSun.z);

      final into = _brightness(preset.inScatterAlong(toSun));
      final off = _brightness(preset.inScatterAlong(away));

      expect(into, greaterThan(off * 1.4));
      // Looking away from the sun is the neutral haze and nothing less: air
      // does not take light away.
      expect(off, closeTo(_brightness(preset.horizonFogColour), 1e-9));
    });

    test('a zero view direction is the neutral haze, not a crash', () {
      final preset = SkyPresets.morning;
      expect(preset.inScatterAlong(Vector3.zero()),
          preset.horizonFogColour);
    });

    test('asks for a ground the generator can afford to build', () {
      // The ground is a square of finite size, and past its edge there is
      // nothing at all. The generator sizes it from the haze — far enough that
      // `exp(-density * reach)` has fallen to a tenth or so and the seam is
      // gone — which means a preset with very clear air asks for a very large
      // ground, and a large ground is not free: `Scene.computeBounds` takes it,
      // the last shadow cascade is fitted to that, and its texels grow with it.
      //
      // So the contract runs the other way round from how it reads. A preset
      // may not be so clear that the ground it implies would blow out the
      // shadows, and may not be so thick that the circuit disappears. That
      // whole shape of the ground is checked against the real generated file in
      // `apps/racing/test/frame_test.dart`; here it is only the range.
      for (final preset in SkyPresets.all) {
        final reach = math.log(1.0 / 0.12) / preset.fogDensity;
        expect(reach, greaterThan(200.0),
            reason: '${preset.name} is pea soup: the far corners are gone');
        expect(reach, lessThan(760.0),
            reason: '${preset.name} needs a ground the shadows cannot afford');
      }
    });
  });

  group('the file', () {
    test('a track with no sky still has weather', () {
      // The same position taken about a car with no model: a fixture that only
      // cares about lap timing should not have to describe a sunset.
      final preset = SkyPreset.fromJson(const <String, Object?>{});
      expect(preset.name, SkyPresets.morning.name);
      expect(preset.fogDensity, SkyPresets.morning.fogDensity);
    });

    test('a sky block overrides field by field', () {
      final preset = SkyPreset.fromJson(<String, Object?>{
        'name': 'test',
        'fogDensity': 0.02,
      });
      expect(preset.name, 'test');
      expect(preset.fogDensity, 0.02);
      expect(preset.exposure, SkyPresets.morning.exposure);
    });

    test('every preset is reachable by the name it writes', () {
      // Mutation: rename a preset in Dart and not in `make_track.py`. The
      // generator writes a name into the track file and nothing else would
      // notice it had stopped meaning anything.
      for (final preset in SkyPresets.all) {
        expect(SkyPresets.byName(preset.name), same(preset));
      }
      expect(SkyPresets.byName('midnight'), isNull);
    });
  });
}
