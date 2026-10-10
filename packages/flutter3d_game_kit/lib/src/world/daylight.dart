import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:vector_math/vector_math.dart';

/// The hour of a world's day, and everything that follows from it: where the
/// sun is, what light it and the moon give, and the sky they are seen
/// through.
///
/// **The sky is the air, not a colour.** [PhysicalSky] scatters the sun
/// wherever it stands, so the morning is pale, the evening is red towards the
/// sun and dark away from it, and the stars come out on their own once the
/// sun is far enough down — a game only moves the sun. The light on the world
/// is read off the same air: [PhysicalSky.sunlight] is what the air leaves of
/// the sun on its way down, white at noon, orange low, nothing once it has
/// set; and the renderer takes the ambient from the same sky.
///
/// **The moon is a game's moon.** It stands opposite the sun and lights the
/// world through the same air, but far brighter than the real one, which
/// gives about one four-hundred-thousandth of the sun's light: an eye adapts
/// to that over half an hour, and a frame at one exposure does not, so a
/// true moon is a black screen with stars over it. [moonShare] is how much of
/// the sun's light it gives instead, and is a choice about play: enough to
/// see what is in front of you, little enough that the night reads as night.
final class Daylight {
  /// A day at [hour], from nought to twenty-four.
  ///
  /// [noon] is where the sun stands at midday; the default is high and off
  /// to one side, so the sides of things turned to it are lit and the
  /// shadows fall across the ground rather than straight down.
  Daylight({
    double hour = morning,
    this.secondsPerHour = defaultSecondsPerHour,
    this.sunIntensity = defaultSunIntensity,
    this.moonShare = defaultMoonShare,
    this.air = earth,
    Vector3? noon,
  }) : _hour = hour % 24.0,
       _noon = (noon ?? Vector3(0.45, 1.0, 0.3)).normalized();

  /// The hour a new world starts at: the sun well up and still climbing. On
  /// the day's 24-hour scale.
  static const double morning = 9.0;

  /// A day of twenty minutes, so a sitting sees an evening without waiting
  /// for one. In real seconds per hour of the game's day.
  static const double defaultSecondsPerHour = 50.0;

  /// The sun at noon, in lux: about 15 000, the 2.6 of the renderer's own
  /// unit it was before 1.0 (times `Photometric.legacyUnit`). A real noon is
  /// nearer 100 000; this is the sun that reads as daylight under the
  /// reference camera without metering for it.
  static const double defaultSunIntensity = 2.6 * Photometric.legacyUnit;

  /// The moon's light as a share of the sun's; see the class comment.
  static const double defaultMoonShare = 0.12;

  /// The Earth's air, as the engine's defaults have it.
  static const PhysicalSky earth = PhysicalSky();

  /// Real seconds to one of the day's hours.
  final double secondsPerHour;

  /// How strongly the sun lights the world at noon, before the air takes its
  /// share, in lux.
  final double sunIntensity;

  /// The moon's light, as a share of the sun's.
  final double moonShare;

  /// The air the sun is seen through.
  final PhysicalSky air;

  final Vector3 _noon;
  double _hour;

  /// The hour, from nought to twenty-four; six is sunrise, eighteen sunset.
  /// On the day's 24-hour scale.
  double get hour => _hour;

  /// Moves the day on by [dt] real seconds.
  void advance(double dt) => _hour = (_hour + dt / secondsPerHour) % 24.0;

  /// The unit vector towards the sun: one great circle a day, through the
  /// horizon at six, noon's point at twelve, the opposite horizon at
  /// eighteen, and as far under the world at midnight as it was over it at
  /// noon.
  Vector3 get towardsSun {
    // Where the sun rises: on the horizon, a right angle round from noon.
    final rise = Vector3(-_noon.z, 0.0, _noon.x)..normalize();
    final angle = (_hour - 6.0) / 24.0 * 2.0 * math.pi;
    return (rise * math.cos(angle) + _noon * math.sin(angle))..normalize();
  }

  /// The sky to draw: the air, with the sun where [hour] puts it.
  SkySettings get sky =>
      SkySettings(enabled: true, physical: air, directionToSun: towardsSun);

  /// Points [sun] and [moon] along the hour and gives each the light the air
  /// leaves of it; one under the horizon gives none.
  ///
  /// **The one in the sky casts the shadows.** The renderer shadows the first
  /// directional light that asks, so each asks only while it is up: a sun
  /// that always asked would shadow the night from under the world, and the
  /// moon would light it with no shadow under anything.
  void light({required LightNode sun, required LightNode moon}) {
    final up = towardsSun;
    final day = up.y > 0.0;
    sun
      ..setLocalForward(-up)
      ..intensity = sunIntensity
      ..castsShadow = day
      ..color = air.sunlight(up).toLinearColor();
    moon
      ..setLocalForward(up)
      ..intensity = sunIntensity * moonShare
      ..castsShadow = !day
      ..color = air.sunlight(-up).toLinearColor();
  }
}
