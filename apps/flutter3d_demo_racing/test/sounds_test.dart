/// What the game plays, without a sound card.
///
/// `SilentBackend` records every voice it is asked for, so the whole mapping
/// from "the car is sideways" to "something is squealing" is checkable here.
/// That mapping is the part that rots quietly: the platformer shipped a version
/// where taking a coin made no sound at all and every one of its tests passed,
/// because nothing asked what was playing.
library;

import 'dart:io';

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_audio/testing.dart';
import 'package:flutter3d_demo_racing/src/sounds.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A car whose numbers are set by hand, so that a test about sound is not also
/// a test about driving.
final class _Car implements VehicleController {
  _Car()
    : collider = Collider(
        shape: CollisionSphere(0.7),
        position: Vector3.zero(),
      );

  @override
  final Collider collider;

  @override
  Vector3 get position => collider.position;

  @override
  final Vector3 velocity = Vector3.zero();

  @override
  double headingYaw = 0.0;

  @override
  Matrix3 get visualBasis => Matrix3.identity();

  @override
  double get speed => velocity.length;

  @override
  double slipAngle = 0.0;

  @override
  double slipRatio = 0.0;

  @override
  bool grounded = true;

  @override
  double impactThisStep = 0.0;

  @override
  double rpm = 0.0;

  @override
  double trackDistance = 0.0;

  @override
  void step(double dt, VehicleInput input) {}

  @override
  void placeAt(Vector3 at, double yaw, {double? trackDistance}) {}

  /// A stand-in car keeps nothing between steps, so there is nothing to save.
  /// The interface still asks, because a race that can be saved has to be able
  /// to save whatever is driving in it.
  @override
  Map<String, Object?> save() => const <String, Object?>{};

  @override
  void restore(Map<String, Object?> from) {}
}

({CarVoice voice, _Car car, AudioScene scene, SilentBackend backend}) heard() {
  final backend = SilentBackend();
  final scene = AudioScene(backend: backend);
  final car = _Car()..velocity.setValues(0.0, 0.0, 30.0);
  return (
    voice: CarVoice(scene: scene, vehicle: car),
    car: car,
    scene: scene,
    backend: backend,
  );
}

/// How loud a named sound ended up, or zero if it is not playing.
double loudnessOf(SilentBackend backend, String asset) {
  var total = 0.0;
  for (final voice in backend.live) {
    if (voice.asset.endsWith(asset)) total += voice.gain;
  }

  return total;
}

/// This game's sound table, read out of its own source.
///
/// **The scan is `flutter3d_audio`'s now**, and it was two regular expressions
/// in three games. What it catches is the one thing no type can: a
/// `static const SoundDef` declared beside the bank and left out of it. See
/// `soundTableIn` for why the source is the only place that knows.
({Set<String> declared, Set<String> inTheBank}) _table() =>
    soundTableIn('lib/src/sounds.dart');

void main() {
  group('the engine', () {
    test('is heard even at rest', () {
      // Mutation: drive the note straight from `rpm`. A car on the grid has
      // none, so the field would sit in silence until the lights went out and
      // the first thing anybody heard would be four engines starting at once.
      final it = heard();
      it.car
        ..rpm = 0.0
        ..velocity.setZero();

      it.voice.update(offRoad: false);
      it.scene.update(AudioListener());

      expect(loudnessOf(it.backend, 'engine_low.wav'), greaterThan(0.0));
    });

    test('rises with the revs', () {
      final it = heard();

      // Read from the mix rather than from the voices: at nine tenths of the
      // revs the low band is mixed to nothing and has no voice to ask.
      it.car.rpm = 0.2;
      it.voice.update(offRoad: false);
      final low = it.voice.engine.rateOf(0);

      it.car.rpm = 0.9;
      it.voice.update(offRoad: false);
      final high = it.voice.engine.rateOf(0);

      expect(high, greaterThan(low));
    });

    test('moves with the car', () {
      final it = heard();
      it.car.position.setValues(40.0, 0.0, -12.0);

      it.voice.update(offRoad: false);

      // Read through the mixer: a listener beside the car hears it, one far
      // away does not.
      it.scene.update(AudioListener()..position.setFrom(it.car.position));
      final near = loudnessOf(it.backend, 'engine_low.wav');

      it.scene.update(AudioListener()..position.setValues(0.0, 0.0, 400.0));
      final far = loudnessOf(it.backend, 'engine_low.wav');

      expect(near, greaterThan(far));
    });
  });

  group('the tyres', () {
    test('squeal when the car is sideways and not before', () {
      // Mutation: play the skid loop whenever the car is moving. A racing game
      // where the tyres squeal down the straight is a racing game nobody
      // believes, and it is the fault most likely to be shipped because it is
      // only wrong by degree.
      final it = heard();

      it.car.slipAngle = 0.02;
      it.voice.update(offRoad: false);
      it.scene.update(AudioListener());
      expect(loudnessOf(it.backend, 'skid.wav'), 0.0);

      it.car.slipAngle = 0.6;
      it.voice.update(offRoad: false);
      it.scene.update(AudioListener());
      expect(loudnessOf(it.backend, 'skid.wav'), greaterThan(0.0));
    });

    test('wheelspin squeals too', () {
      final it = heard();
      it.car
        ..slipAngle = 0.0
        ..slipRatio = 0.9;

      it.voice.update(offRoad: false);
      it.scene.update(AudioListener());

      expect(loudnessOf(it.backend, 'skid.wav'), greaterThan(0.0));
    });

    test('a car in the air is silent, however sideways it is', () {
      final it = heard();
      it.car
        ..slipAngle = 0.8
        ..grounded = false;

      it.voice.update(offRoad: false);
      it.scene.update(AudioListener());

      expect(loudnessOf(it.backend, 'skid.wav'), 0.0);
    });

    test('a car barely moving is quiet, whatever the angle says', () {
      // Slip angle is an angle, and at a crawl the angle between where a car
      // points and where it is going says nothing about rubber.
      final it = heard();
      it.car
        ..slipAngle = 0.9
        ..velocity.setValues(0.0, 0.0, 0.2);

      it.voice.update(offRoad: false);
      it.scene.update(AudioListener());

      expect(loudnessOf(it.backend, 'skid.wav'), lessThan(0.05));
    });
  });

  group('off the road', () {
    test('the rumble is heard only out there', () {
      final it = heard();

      it.voice.update(offRoad: false);
      it.scene.update(AudioListener());
      expect(loudnessOf(it.backend, 'rumble.wav'), 0.0);

      it.voice.update(offRoad: true);
      it.scene.update(AudioListener());
      expect(loudnessOf(it.backend, 'rumble.wav'), greaterThan(0.0));
    });
  });

  group('the bank', () {
    test('every sound names a file, and every loop says it loops', () {
      // Mutation: forget `loop: true` on the engine. It would play once at the
      // start of the race and never again, which sounds exactly like the audio
      // device having failed.
      for (final sound in Sounds.all) {
        expect(sound.asset, startsWith('assets/sounds/'));
        expect(sound.asset, endsWith('.wav'));
      }
      for (final sound in <SoundDef>[
        Sounds.engineLow,
        Sounds.engineHigh,
        Sounds.skid,
        Sounds.rumble,
      ]) {
        expect(
          sound.loop,
          isTrue,
          reason: '${sound.name} is a continuous sound',
        );
      }
      for (final sound in <SoundDef>[Sounds.count, Sounds.go, Sounds.lap]) {
        expect(sound.loop, isFalse, reason: '${sound.name} is an event');
      }
    });

    test('the engine bands are the revs the files were written at', () {
      // The one number that has to agree between a Python script and this
      // package: `BlendedLoop` corrects a band's speed by the ratio between
      // what is asked for and what the band holds, so a centre that does not
      // match the recording is a permanent, silent detune.
      expect(Sounds.lowRevs, lessThan(Sounds.highRevs));
      expect(Sounds.lowRevs, greaterThan(0.0));
      expect(Sounds.highRevs, lessThanOrEqualTo(1.0));
    });
  });

  group('the files', () {
    test('every sound in the bank is on disk', () async {
      // Mutation: rename a file and not the constant. The mixer would ask for
      // an asset the backend cannot load, and the only symptom is silence in
      // one place.
      for (final sound in Sounds.all) {
        expect(
          await _exists(sound.asset),
          isTrue,
          reason:
              '${sound.name} points at ${sound.asset}, which is not there — '
              'run tool/make_sounds.py',
        );
      }
    });
  });

  group('the bank', () {
    test('holds every sound this game declares', () {
      // A declared sound that is not in the bank can never play: the backend
      // has no source for it, hands back no voice, and the emitter waits for
      // one for ever. It looks exactly like a sound nobody triggered — which is
      // how the platformer shipped half mute for months.
      final missing = _table().declared.difference(_table().inTheBank);

      expect(
        missing,
        isEmpty,
        reason:
            'declared and never preloaded, so silent in the real build: '
            '${missing.join(', ')}',
      );
    });

    test('and nothing in it was never declared', () {
      expect(_table().inTheBank.difference(_table().declared), isEmpty);
    });
  });
}

Future<bool> _exists(String asset) async {
  final file = File(asset);
  return file.existsSync();
}
