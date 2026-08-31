import 'dart:math' as math;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const SoundDef _step = SoundDef(
  name: 'step',
  asset: 'a/step.ogg',
  attenuation: InverseRolloff(reference: 1.0, maximum: 20.0),
);

const SoundDef _door = SoundDef(
  name: 'door',
  asset: 'a/door.ogg',
  priority: 10,
  attenuation: InverseRolloff(reference: 1.0, maximum: 20.0),
);

/// A listener at the origin looking down -Z, which is the engine's forward.
AudioListener _ears() => AudioListener()..aimAt(Vector3.zero(), 0.0);

void main() {
  group('play rate', _rateTests);

  group('attenuation', () {
    test('is full inside the reference radius', () {
      const model = InverseRolloff(reference: 2.0, maximum: 30.0);
      expect(model.gainAt(0.0), closeTo(1.0, 1e-9));
      expect(model.gainAt(1.5), closeTo(1.0, 1e-9));
      expect(model.gainAt(2.0), closeTo(1.0, 1e-9));
    });

    test('inverse halves at twice the reference distance', () {
      const model = InverseRolloff(reference: 1.0, maximum: 100.0);
      expect(model.gainAt(2.0), closeTo(0.5, 1e-9));
      expect(model.gainAt(3.0), closeTo(1.0 / 3.0, 1e-9));
    });

    test('linear reaches exactly zero at the maximum', () {
      // The reason a designer picks it: "audible within ten metres" means
      // within ten metres.
      const model = LinearRolloff(reference: 1.0, maximum: 11.0);
      expect(model.gainAt(6.0), closeTo(0.5, 1e-9));
      expect(model.gainAt(11.0), closeTo(0.0, 1e-9));
    });

    test('exponential is steeper near the source than inverse', () {
      const inverse = InverseRolloff(reference: 1.0, maximum: 100.0);
      const exponential = ExponentialRolloff(
        reference: 1.0,
        maximum: 100.0,
        factor: 2.0,
      );
      expect(exponential.gainAt(2.0), lessThan(inverse.gainAt(2.0)));
    });

    test('nothing carries past its maximum', () {
      const model = InverseRolloff(reference: 1.0, maximum: 12.0);
      expect(model.carriesTo(11.9), isTrue);
      expect(model.carriesTo(12.0), isFalse);
      expect(const NoAttenuation().carriesTo(1e9), isTrue);
    });

    test('no attenuation is exactly that', () {
      expect(const NoAttenuation().gainAt(500.0), 1.0);
    });
  });

  group('panning', () {
    test('a sound to the right pans right', () {
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend);
      final emitter = scene.play(_step, Vector3(3.0, 0.0, 0.0));

      scene.update(_ears());

      expect(emitter.pan, greaterThan(0.9));
    });

    test('and to the left, left', () {
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend);
      final emitter = scene.play(_step, Vector3(-3.0, 0.0, 0.0));

      scene.update(_ears());

      expect(emitter.pan, lessThan(-0.9));
    });

    test('straight ahead is centred', () {
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend);
      final emitter = scene.play(_step, Vector3(0.0, 0.0, -5.0));

      scene.update(_ears());

      expect(emitter.pan, closeTo(0.0, 1e-6));
    });

    test('turning the listener swings the sound across', () {
      // The whole reason the geometry is computed here rather than handed to
      // SoLoud, whose listener cannot be moved after the fact.
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend);
      final emitter = scene.play(_step, Vector3(3.0, 0.0, 0.0));
      final ears = _ears();

      scene.update(ears);
      expect(emitter.pan, greaterThan(0.9));

      // Half a turn: what was on the right is now on the left.
      ears.aimAt(Vector3.zero(), 3.14159265);
      scene.update(ears);
      expect(emitter.pan, lessThan(-0.9));
    });

    test('a sound on top of the listener is not panned anywhere', () {
      // Normalising a zero vector is how a footstep ends up hard left.
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend);
      final emitter = scene.play(_step, Vector3.zero());

      scene.update(_ears());

      expect(emitter.pan, 0.0);
      expect(emitter.audibleGain, greaterThan(0.0));
    });

    test('pitch does not swing the field', () {
      // Looking at the floor must not move a sound left or right.
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend);
      final emitter = scene.play(_step, Vector3(0.0, 6.0, -1.0));

      scene.update(_ears());

      expect(emitter.pan.abs(), lessThan(0.05));
    });
  });

  group('voices', () {
    test('a sound in range gets one, and out of range does not', () {
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend);
      scene.play(_step, Vector3(2.0, 0.0, 0.0));
      scene.play(_step, Vector3(500.0, 0.0, 0.0));

      scene.update(_ears());

      expect(backend.live, hasLength(1));
    });

    test('moving a source updates its voice rather than restarting it', () {
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend);
      final emitter = scene.play(
        const SoundDef(name: 'hum', asset: 'a/hum.ogg', loop: true),
        Vector3(2.0, 0.0, 0.0),
      );

      scene.update(_ears());
      expect(backend.started, hasLength(1));

      emitter.position.setValues(4.0, 0.0, 0.0);
      scene.update(_ears());

      expect(backend.started, hasLength(1), reason: 'restarted instead of updated');
      expect(backend.live.single.gain, lessThan(1.0));
    });

    test('the quietest are dropped when there are more than the limit', () {
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend, maxVoices: 3);
      for (var i = 1; i <= 6; i++) {
        scene.play(
          SoundDef(
            name: 'step$i',
            asset: 'a/step.ogg',
            attenuation: const InverseRolloff(reference: 1.0, maximum: 50.0),
          ),
          Vector3(i.toDouble(), 0.0, 0.0),
        );
      }

      scene.update(_ears());

      expect(backend.live, hasLength(3));
      // The three nearest, which are the three loudest.
      expect(scene.emitters.where((SoundEmitter e) => e.isAudible).length, 3);
    });

    test('priority outranks loudness', () {
      // A door closing matters more than the nearer footstep, and distance
      // alone gets that backwards.
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend, maxVoices: 1);
      scene.play(_step, Vector3(1.0, 0.0, 0.0));
      final door = scene.play(_door, Vector3(9.0, 0.0, 0.0));

      scene.update(_ears());

      expect(backend.live, hasLength(1));
      expect(backend.live.single.asset, door.sound.asset);
    });

    test('one sound cannot flood the mix', () {
      // Ten identical grunts on one frame are a click, not ten times as loud.
      const grunt = SoundDef(
        name: 'grunt',
        asset: 'a/grunt.ogg',
        maxInstances: 2,
        attenuation: InverseRolloff(reference: 1.0, maximum: 50.0),
      );
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend, maxVoices: 16);
      for (var i = 0; i < 10; i++) {
        scene.play(grunt, Vector3(1.0 + i, 0.0, 0.0));
      }

      scene.update(_ears());

      expect(backend.live, hasLength(2));
    });

    test('a finished one-shot is forgotten', () {
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend);
      scene.play(_step, Vector3(2.0, 0.0, 0.0));
      scene.update(_ears());
      expect(scene.emitters, hasLength(1));

      backend.finish(backend.started.single);
      scene.update(_ears());

      expect(scene.emitters, isEmpty);
    });

    test('stopping one by hand ends its voice', () {
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend);
      final emitter = scene.play(
        const SoundDef(name: 'hum', asset: 'a/hum.ogg', loop: true),
        Vector3(2.0, 0.0, 0.0),
      );
      scene.update(_ears());
      expect(backend.live, hasLength(1));

      emitter.stop();
      scene.update(_ears());

      expect(backend.live, isEmpty);
      expect(scene.emitters, isEmpty);
    });

    test('stopAll clears the scene', () {
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend);
      scene.play(_step, Vector3(1.0, 0.0, 0.0));
      scene.play(_step, Vector3(2.0, 0.0, 0.0));
      scene.update(_ears());

      scene.stopAll();

      expect(backend.live, isEmpty);
      expect(scene.emitters, isEmpty);
    });
  });

  group('occlusion', () {
    test('a wall between quietens without silencing the emitter', () {
      final backend = SilentBackend();
      final scene = AudioScene(
        backend: backend,
        occlusion: (Vector3 from, Vector3 to) => 0.25,
      );
      final blocked = scene.play(_step, Vector3(2.0, 0.0, 0.0));
      scene.update(_ears());

      // The same sound at the same distance with nothing in the way, so the
      // assertion is about the occlusion and not about the rolloff curve.
      final open = AudioScene(backend: SilentBackend());
      final clear = open.play(_step, Vector3(2.0, 0.0, 0.0));
      open.update(_ears());

      expect(blocked.audibleGain, closeTo(clear.audibleGain * 0.25, 1e-9));
      expect(blocked.isAudible, isTrue);
    });

    test('full occlusion drops the voice entirely', () {
      final backend = SilentBackend();
      final scene = AudioScene(
        backend: backend,
        occlusion: (Vector3 from, Vector3 to) => 0.0,
      );
      scene.play(_step, Vector3(2.0, 0.0, 0.0));

      scene.update(_ears());

      expect(backend.live, isEmpty);
    });
  });

  group('reporting', () {
    test('decibels line up with the usual figures', () {
      expect(gainToDecibels(1.0), closeTo(0.0, 1e-9));
      expect(gainToDecibels(0.5), closeTo(-6.02, 0.01));
      expect(gainToDecibels(0.0), double.negativeInfinity);
    });
  });
}

/// What speed a sound is played at, and how much that varies.
///
/// The other half of `maxInstances`: identical repeats read as a machine even
/// when they are far enough apart not to click.
void _rateTests() {
  SoundDef coin({double variance = 0.0, double rate = 1.0}) => SoundDef(
        name: 'coin',
        asset: 'coin.wav',
        rate: rate,
        rateVariance: variance,
      );

  ({AudioScene scene, SilentBackend backend}) sceneWith({int seed = 3}) {
    final backend = SilentBackend();
    return (
      scene: AudioScene(backend: backend, random: math.Random(seed)),
      backend: backend,
    );
  }

  test('no variance plays at exactly the rate asked for', () {
    // Mutation: `1.0 + random.nextDouble() * variance` with a non-zero default
    // — every sound in every game drifts sharp.
    final it = sceneWith();
    it.scene
      ..play(coin(), Vector3.zero())
      ..update(AudioListener());

    expect(it.backend.started.single.rate, 1.0);
  });

  test('variance makes two plays of one sound differ', () {
    // Mutation: draw the rate once at `SoundDef` construction. Every coin in
    // the level is the same coin again, which is the thing this is for.
    final it = sceneWith();
    final sound = coin(variance: 0.15);
    for (var i = 0; i < 6; i++) {
      it.scene
        ..play(sound, Vector3(i * 0.1, 0.0, 0.0))
        ..update(AudioListener());
    }

    final rates = it.backend.started.map((SilentVoice v) => v.rate).toSet();
    expect(rates.length, greaterThan(1), reason: 'every play was identical');
    for (final rate in rates) {
      expect(rate, inInclusiveRange(0.85, 1.15));
    }
  });

  test('the variance is two-sided, so nothing drifts sharp', () {
    // Mutation: `1.0 + r * variance`. The mean climbs by half the variance and
    // a hundred coins later the level sounds like a cartoon.
    final it = sceneWith(seed: 11);
    final sound = coin(variance: 0.2);
    for (var i = 0; i < 400; i++) {
      it.scene
        ..play(sound, Vector3(i * 0.01, 0.0, 0.0))
        ..update(AudioListener());
    }

    final rates = it.backend.started.map((SilentVoice v) => v.rate);
    final mean = rates.reduce((double a, double b) => a + b) / rates.length;
    expect(mean, closeTo(1.0, 0.02));
  });

  test('the same seed gives the same sounds', () {
    // Mutation: use `math.Random()` inside the scene. Every snapshot test that
    // happens to play a sound stops being reproducible, and the failure looks
    // like the physics diverging.
    List<double> run() {
      final it = sceneWith(seed: 5);
      final sound = coin(variance: 0.1);
      for (var i = 0; i < 8; i++) {
        it.scene
          ..play(sound, Vector3(i.toDouble(), 0.0, 0.0))
          ..update(AudioListener());
      }
      return it.backend.started.map((SilentVoice v) => v.rate).toList();
    }

    expect(run(), run());
  });
}
