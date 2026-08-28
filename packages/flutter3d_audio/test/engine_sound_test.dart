import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const SoundDef _low = SoundDef(
  name: 'engine-low',
  asset: 'engine_low.wav',
  loop: true,
  attenuation: NoAttenuation(),
);

const SoundDef _high = SoundDef(
  name: 'engine-high',
  asset: 'engine_high.wav',
  loop: true,
  attenuation: NoAttenuation(),
);

({BlendedLoop loop, AudioScene scene, SilentBackend backend}) engine({
  List<LoopBand>? bands,
}) {
  final backend = SilentBackend();
  final scene = AudioScene(backend: backend);
  return (
    loop: BlendedLoop(
      scene: scene,
      bands:
          bands ??
          const <LoopBand>[
            LoopBand(sound: _low, centre: 0.3, width: 0.45),
            LoopBand(sound: _high, centre: 0.8, width: 0.45),
          ],
    ),
    scene: scene,
    backend: backend,
  );
}

/// What the blend decided each band is worth at [value].
///
/// Read from the blend rather than from the backend's voices: a band mixed down
/// to nothing never gets a voice, so counting voices would report a set of two
/// as a set of one everywhere except the middle of the crossfade.
List<double> gainsAt(
  ({BlendedLoop loop, AudioScene scene, SilentBackend backend}) it,
  double value,
) {
  it.loop.update(value);
  return <double>[
    for (var i = 0; i < it.loop.bands.length; i++) it.loop.gainOf(i),
  ];
}

void main() {
  group('crossfading', () {
    test('each band is loudest where it was recorded', () {
      // Mutation: weight by the value itself rather than by the distance from
      // the band's centre. The set would then always favour the same end and
      // the other recordings would be decoration.
      final it = engine();

      final low = gainsAt(it, 0.3);
      final high = gainsAt(it, 0.8);

      expect(low[0], greaterThan(low[1]));
      expect(high[1], greaterThan(high[0]));
    });

    test('the total is the same all the way across', () {
      // Mutation: drop the normalisation. The middle of a crossfade, where two
      // bands are each at half, comes out quieter than either end — an engine
      // with a hole in the middle of its rev range, which reads as the sound
      // cutting out on every gear change.
      final it = engine();

      for (var value = 0.05; value < 1.2; value += 0.05) {
        final gains = gainsAt(it, value);
        final total = gains.fold<double>(0.0, (double a, double b) => a + b);
        expect(total, closeTo(1.0, 1e-6), reason: 'at $value');
      }
    });

    test('the engine plays faster as the value rises', () {
      // The whole point of a rate on a live voice: one recording of an engine,
      // run faster. Mutation: leave the rate at one — the car drones on a
      // single tone from the grid to the flag.
      final it = engine();

      it.loop.update(0.3);
      final slow = <double>[
        for (var i = 0; i < it.loop.bands.length; i++) it.loop.rateOf(i),
      ];

      it.loop.update(0.9);
      final fast = <double>[
        for (var i = 0; i < it.loop.bands.length; i++) it.loop.rateOf(i),
      ];

      for (var i = 0; i < slow.length; i++) {
        expect(fast[i], greaterThan(slow[i]));
      }
    });

    test('a band asked for its own value plays at its own speed', () {
      final it = engine(
        bands: const <LoopBand>[LoopBand(sound: _low, centre: 0.5)],
      );

      it.loop.update(0.5);

      expect(it.loop.rateOf(0), closeTo(1.0, 1e-9));
    });

    test('the speed reaches an actual voice, not only the mixer', () {
      // The reason `AudioBackend.update` grew a rate at all: a loop already
      // playing has to change speed, and before this it could only be set once.
      final it = engine(
        bands: const <LoopBand>[LoopBand(sound: _low, centre: 0.5)],
      );

      it.loop.update(0.5);
      it.scene.update(AudioListener());
      final atRest = it.backend.live.single.rate;

      it.loop.update(1.0);
      it.scene.update(AudioListener());

      expect(it.backend.live.single.rate, greaterThan(atRest));
    });

    test('past the last band the nearest one carries it alone', () {
      // Mutation: let the weights fall to nothing outside every band. An
      // over-rev, or a value the bands do not cover, would be silence — and
      // silence from an engine reads as the game having crashed.
      final it = engine();

      final gains = gainsAt(it, 3.0);
      final total = gains.fold<double>(0.0, (double a, double b) => a + b);

      expect(total, closeTo(1.0, 1e-6));
    });

    test('volume scales the whole set, not one band', () {
      final it = engine();

      it.loop.update(0.5, volume: 0.25);
      final total = <double>[
        for (var i = 0; i < it.loop.bands.length; i++) it.loop.gainOf(i),
      ].fold<double>(0.0, (double a, double b) => a + b);

      expect(total, closeTo(0.25, 1e-6));
    });
  });

  group('where it comes from', () {
    test('every band moves with the car', () {
      final it = engine();

      it.loop.update(0.5, at: Vector3(10.0, 0.0, -4.0));

      expect(it.loop.position.x, 10.0);
      expect(it.loop.position.z, -4.0);
    });

    test('stopping ends every band', () {
      final it = engine();
      it.loop.update(0.5);
      it.scene.update(AudioListener());
      expect(it.backend.live, isNotEmpty);

      it.loop.stop();
      it.scene.update(AudioListener());

      expect(it.backend.live, isEmpty);
    });
  });
}
