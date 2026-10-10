/// The speed a Doppler shift is reckoned against follows the world's air.
///
///     dart test test/speed_of_sound_test.dart
library;

import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart'
    show WorldProperties, speedOfSoundAt;
import 'package:test/test.dart';

void main() {
  test("a room's air is the standard speed, to the bit", () {
    expect(
      EqualPowerPanner.inWorld(WorldProperties.standard).speedOfSound,
      speedOfSoundInAir,
    );
  });

  test('cold air carries sound slower, warm air faster', () {
    // Mutation: read the standard speed whatever the air and all three agree.
    final freezing = EqualPowerPanner.inWorld(
      WorldProperties(airTemperature: 273.15),
    ).speedOfSound;
    final desert = EqualPowerPanner.inWorld(
      WorldProperties(airTemperature: 318.15),
    ).speedOfSound;
    // 343 m/s at 20 °C scaled by √T: 331.1 at 0 °C. The textbook's 331.3
    // goes with 343.2 at 20 °C, which the standard rounds to 343.
    expect(freezing, closeTo(331.1, 0.05));
    expect(desert, closeTo(speedOfSoundAt(318.15), 1e-12));
    expect(desert, greaterThan(speedOfSoundInAir));
  });

  test('the Doppler factor is kept', () {
    expect(
      EqualPowerPanner.inWorld(
        WorldProperties.standard,
        dopplerFactor: 0.5,
      ).dopplerFactor,
      0.5,
    );
  });
}
