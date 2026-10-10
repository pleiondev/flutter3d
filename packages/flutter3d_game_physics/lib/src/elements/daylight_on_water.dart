import 'package:flutter3d_effects/flutter3d_effects.dart' show Elements;
import 'package:flutter3d_game_kit/world.dart' show Daylight;
import 'package:vector_math/vector_math.dart';

/// The day of `flutter3d_game_kit`'s `world.dart`, lighting the water of
/// `flutter3d_effects`.
///
/// **An extension here rather than a method of [Daylight]**, so the world's
/// day and horizon carry no dependency on the elements, and through them on
/// the native physics core: a game that has a sky but no water compiles no C
/// for it.
extension DaylightOnWater on Daylight {
  /// Lights [water] as the world is lit: by the sun's light as the air
  /// leaves it, and mirroring the sky straight up and along the horizon.
  ///
  /// The moon is left out of it: the water's look takes one sun, and a
  /// moon's glint on a pond at night is a picture the night does without.
  void lightWater(Elements water) {
    final up = towardsSun;
    final seen = sky;
    water
      ..sun(along: -up, light: air.sunlight(up)..scale(sunIntensity))
      ..sky(
        zenith: seen.sample(Vector3(0.0, 1.0, 0.0)),
        horizon: seen.sample(Vector3(1.0, 0.02, 0.0)),
      );
  }
}
