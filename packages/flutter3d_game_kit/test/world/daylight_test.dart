/// The hour of a world's day.
///
///     dart test test/daylight_test.dart
///
/// The sun goes round once a day, high at noon and as low at midnight; the
/// day moves at the rate a game set; the light is the air's, white at noon
/// and warm at evening; the one in the sky casts the shadows; and a game's
/// own noon and moon are its own.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game_kit/world.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('the sun is high at noon, on the horizon at six, under at midnight', () {
    expect(Daylight(hour: 12.0).towardsSun.y, greaterThan(0.8));
    // Mutation: start the circle at noon rather than at sunrise, and six in
    // the morning is the top of the sky.
    expect(Daylight(hour: 6.0).towardsSun.y, closeTo(0.0, 1e-9));
    expect(Daylight(hour: 18.0).towardsSun.y, closeTo(0.0, 1e-9));
    expect(Daylight(hour: 0.0).towardsSun.y, lessThan(-0.8));
  });

  test('the day moves at the rate the game set, and wraps', () {
    final day = Daylight(hour: 23.5)..advance(Daylight.defaultSecondsPerHour);
    // Mutation: forget the modulo, and the twenty-fifth hour is a sky the
    // circle has no place for.
    expect(day.hour, closeTo(0.5, 1e-9));
    final fast = Daylight(hour: 9.0, secondsPerHour: 1.0)..advance(3.0);
    expect(fast.hour, closeTo(12.0, 1e-9));
  });

  test('the one in the sky casts the shadows, in the air\'s light', () {
    final sun = LightNode(name: 'light');
    final moon = LightNode(name: 'light');
    Daylight(hour: 12.0).light(sun: sun, moon: moon);
    expect(sun.castsShadow, isTrue);
    expect(moon.castsShadow, isFalse);
    // Mutation: the default sun in the renderer's pre-1.0 unit, 2.6, which
    // since lights are in lux is a sun a two-thousandth of daylight.
    expect(sun.intensity, closeTo(2.6 * Photometric.legacyUnit, 1e-6));
    expect(
      moon.intensity,
      closeTo(sun.intensity * Daylight.defaultMoonShare, 1e-9),
    );
    final noon = sun.color.toVector3();

    Daylight(hour: 17.5).light(sun: sun, moon: moon);
    // Mutation: a fixed white sun, and the evening is as white as noon.
    expect(sun.color.b / sun.color.r, lessThan(noon.z / noon.x));

    Daylight(hour: 0.0).light(sun: sun, moon: moon);
    // Mutation: a sun that always asks for shadows shadows the night from
    // under the world.
    expect(sun.castsShadow, isFalse);
    expect(moon.castsShadow, isTrue);
  });

  test('the sky is the air with the sun where the hour puts it', () {
    final day = Daylight(hour: 15.0);
    final sky = day.sky;
    expect(sky.enabled, isTrue);
    expect(sky.directionToSun, day.towardsSun);
  });

  test('a game\'s own noon and moon', () {
    final overhead = Daylight(
      hour: 12.0,
      noon: Vector3(0.0, 1.0, 1.0),
      moonShare: 0.5,
    );
    // Mutation: ignore the noon given, and the sun stands where the default
    // puts it, higher than this one.
    expect(overhead.towardsSun.y, closeTo(0.7071, 1e-4));
    expect(overhead.towardsSun.z, closeTo(0.7071, 1e-4));
    final sun = LightNode(name: 'light');
    final moon = LightNode(name: 'light');
    overhead.light(sun: sun, moon: moon);
    expect(moon.intensity, closeTo(sun.intensity * 0.5, 1e-9));
  });
}
