/// The speed a Doppler shift is reckoned against follows the world's air.
///
///     dart test test/speed_of_sound_test.dart
library;

import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart'
    show WorldProperties, speedOfSoundAt;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const SoundDef _hum = SoundDef(
  name: 'hum',
  asset: 'a/hum.ogg',
  loop: true,
  attenuation: InverseRolloff(reference: 1.0, maximum: 100.0),
);

/// The rate a car ten metres ahead is heard at, coming closer at a tenth of
/// the standard speed of sound.
double _approaching(AudioScene scene) {
  final car = scene.play(_hum, Vector3(0.0, 0.0, -10.0));
  car.velocity.setValues(0.0, 0.0, 34.3);
  scene.update(AudioListener());
  final rate = car.spatial.rate;
  car.stop();
  scene.update(AudioListener());
  return rate;
}

/// The same shift reckoned by hand against [c], m/s, for the float32 34.3
/// the emitter's velocity holds.
double _shift(double c) {
  final toward = Vector3(0.0, 0.0, 34.3).z;
  return c / (c - toward);
}

void main() {
  group('a scene', () {
    test("hears a Doppler shift against its world's air", () {
      // Mutation: the panner reckons against the standard speed whatever
      // the scene's world: the cold scene shifts as a room's would.
      final cold = WorldProperties(airTemperature: 273.15);
      final scene = AudioScene(
        backend: SilentBackend(),
        world: cold,
        spatial: const EqualPowerPanner(dopplerFactor: 1.0),
      );

      expect(_approaching(scene), closeTo(_shift(cold.speedOfSound), 1e-12));
      expect(
        _approaching(scene),
        greaterThan(_shift(speedOfSoundInAir)),
        reason: 'slower sound, a larger shift',
      );
    });

    test('given no world mixes in the standard one, to the bit', () {
      // Only where the number comes from moved: a scene that names no world
      // is heard exactly as it was when the panner held the constant.
      final scene = AudioScene(
        backend: SilentBackend(),
        spatial: const EqualPowerPanner(dopplerFactor: 1.0),
      );
      final pinned = AudioScene(
        backend: SilentBackend(),
        spatial: const EqualPowerPanner(
          dopplerFactor: 1.0,
          speedOfSound: speedOfSoundInAir,
        ),
      );

      expect(scene.world, same(WorldProperties.standard));
      expect(_approaching(scene), _approaching(pinned));
    });

    test('pans by default with a panner that reads the world', () {
      final scene = AudioScene(backend: SilentBackend());

      final panner = scene.spatial as EqualPowerPanner;
      expect(panner.speedOfSound, isNull);
      expect(panner.speedOfSoundIn(scene.world), speedOfSoundInAir);
    });

    test('hears a world set later from the next mix on', () {
      // A level that brings its own air: the scene outlives it, the world
      // is swapped under it.
      final scene = AudioScene(
        backend: SilentBackend(),
        spatial: const EqualPowerPanner(dopplerFactor: 1.0),
      );
      final room = _approaching(scene);

      final desert = WorldProperties(airTemperature: 318.15);
      scene.world = desert;

      expect(_approaching(scene), closeTo(_shift(desert.speedOfSound), 1e-12));
      expect(_approaching(scene), lessThan(room));
    });

    test("keeps a panner made for a world to that world's air", () {
      final desert = WorldProperties(airTemperature: 318.15);
      final scene = AudioScene(
        backend: SilentBackend(),
        world: WorldProperties(airTemperature: 273.15),
        spatial: EqualPowerPanner.inWorld(desert, dopplerFactor: 1.0),
      );

      expect(_approaching(scene), closeTo(_shift(desert.speedOfSound), 1e-12));
    });
  });

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
