/// The 1.0 audio model: the listener and emitters as components that follow
/// nodes, the spatial renderer, the bus tree, snapshots, ducking, the
/// backends that opt into more, and the plugin that runs the mix in the
/// loop's `audio` phase.
///
///     flutter test test/audio_model_test.dart
///
/// Each test names the mutation it was written against: the change to the
/// package that would let it pass while the package was wrong.
library;

import 'dart:math' as math;

import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const SoundDef _hum = SoundDef(name: 'hum', asset: 'a/hum.wav', loop: true);

const SoundDef _music = SoundDef(
  name: 'music',
  asset: 'a/music.ogg',
  loop: true,
  bus: AudioBus.music,
  attenuation: NoAttenuation(),
);

const AudioBus _dialogue = AudioBus('dialogue');

const SoundDef _line = SoundDef(
  name: 'line',
  asset: 'a/line.wav',
  loop: true,
  bus: _dialogue,
  attenuation: NoAttenuation(),
);

Matrix4 _at(double x, double y, double z, {double yaw = 0.0}) =>
    Matrix4.compose(
      Vector3(x, y, z),
      Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), yaw),
      Vector3(1.0, 1.0, 1.0),
    );

/// A backend that also mixes buses and places voices, recording both.
final class _Opted extends AudioBackend
    implements MixingBackend, DirectionalBackend {
  final SilentBackend inner = SilentBackend();
  final Map<VoiceId, AudioBus> routed = <VoiceId, AudioBus>{};
  final Map<AudioBus, double> busGains = <AudioBus, double>{};
  final Map<AudioBus, List<BusEffect>> busEffects =
      <AudioBus, List<BusEffect>>{};
  final Map<AudioBus, AudioBus?> parents = <AudioBus, AudioBus?>{};
  final Map<VoiceId, double> azimuths = <VoiceId, double>{};

  @override
  Future<void> preload(String asset) => inner.preload(asset);

  @override
  VoiceId? start(
    String asset, {
    required double gain,
    required double pan,
    required double rate,
    required bool loop,
    double muffle = 0.0,
  }) => inner.start(
    asset,
    gain: gain,
    pan: pan,
    rate: rate,
    loop: loop,
    muffle: muffle,
  );

  @override
  void update(
    VoiceId voice, {
    required double gain,
    required double pan,
    required double rate,
    double muffle = 0.0,
  }) => inner.update(voice, gain: gain, pan: pan, rate: rate, muffle: muffle);

  @override
  void stop(VoiceId voice) => inner.stop(voice);

  @override
  bool isAlive(VoiceId voice) => inner.isAlive(voice);

  @override
  void routeVoice(VoiceId voice, AudioBus bus) => routed[voice] = bus;

  @override
  void mixBus(
    AudioBus bus, {
    required AudioBus? parent,
    required double gain,
    required List<BusEffect> effects,
  }) {
    busGains[bus] = gain;
    busEffects[bus] = effects;
    parents[bus] = parent;
  }

  @override
  void placeVoice(VoiceId voice, SpatialResult spatial) =>
      azimuths[voice] = spatial.azimuth;
}

void main() {
  group('units', () {
    test('decibels become gain once, and nought is exactly one', () {
      // Mutation: `pow(10, db / 10)`, the power ratio. −6 dB would be a
      // quarter of the amplitude instead of a half.
      expect(decibelsToGain(0.0), 1.0);
      expect(decibelsToGain(-6.0206), closeTo(0.5, 1e-4));
      expect(decibelsToGain(20.0), closeTo(10.0, 1e-9));
      expect(decibelsToGain(silenceDecibels), 0.0);
      expect(gainToDecibels(decibelsToGain(-12.0)), closeTo(-12.0, 1e-9));
    });

    test('inverse rolloff loses 6 dB for each doubling of metres', () {
      // Mutation: a squared distance in the curve. The doubling would cost
      // 12 dB, which is the power law and not the amplitude one.
      const curve = InverseRolloff(maximum: 100.0);
      expect(
        gainToDecibels(curve.gainAt(8.0)) - gainToDecibels(curve.gainAt(4.0)),
        closeTo(-6.0206, 1e-3),
      );
    });
  });

  group('the default renderer', () {
    test('is the mix it always was: inverse distance and a pan', () {
      // Mutation: apply the bus inside the renderer. The voice would be
      // turned down twice and a muted bus would cost the sound its voice.
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend)
        ..mixer.setVolume(AudioBus.sfx, 0.5);
      final emitter = scene.play(_hum, Vector3(2.0, 0.0, 0.0));
      scene.update(AudioListener());
      expect(emitter.audibleGain, closeTo(0.5, 1e-12));
      expect(emitter.pan, 1.0);
      expect(emitter.muffle, 0.0);
      expect(emitter.spatial.distance, closeTo(2.0, 1e-12));
      final voice = backend.live.single;
      expect(voice.gain, closeTo(0.25, 1e-12));
      // Doppler is off, so its share of the rate is exactly one.
      expect(voice.rate, 1.0);
    });

    test('says where a sound is in the listener frame, in radians', () {
      // Mutation: atan2 with its arguments swapped. A sound to the right
      // would read as straight ahead.
      final scene = AudioScene(backend: SilentBackend());
      final right = scene.play(_hum, Vector3(3.0, 0.0, 0.0));
      final above = scene.play(_hum, Vector3(0.0, 3.0, 0.0));
      final behind = scene.play(_hum, Vector3(0.0, 0.0, 3.0));
      scene.update(AudioListener());
      expect(right.spatial.azimuth, closeTo(math.pi / 2.0, 1e-9));
      expect(above.spatial.elevation, closeTo(math.pi / 2.0, 1e-9));
      expect(behind.spatial.azimuth.abs(), closeTo(math.pi, 1e-9));
    });

    test('pans by the equal-power law', () {
      // Mutation: a linear law, `(1 - pan) / 2`. The middle of the field
      // would be 3 dB quieter than either side.
      for (final pan in <double>[-1.0, -0.3, 0.0, 0.6, 1.0]) {
        final g = EqualPowerPanner.gains(pan);
        expect(g.left * g.left + g.right * g.right, closeTo(1.0, 1e-12));
      }
      expect(EqualPowerPanner.gains(0.0).left, closeTo(math.sqrt1_2, 1e-12));
      expect(EqualPowerPanner.gains(1.0).left, closeTo(0.0, 1e-12));
    });

    test('shifts the rate by motion when doppler is asked for', () {
      // Mutation: the sign of the source's speed. A car coming closer would
      // drop in pitch.
      final backend = SilentBackend();
      final scene = AudioScene(
        backend: backend,
        spatial: const EqualPowerPanner(dopplerFactor: 1.0),
      );
      final car = scene.play(_hum, Vector3(0.0, 0.0, -10.0));
      car.velocity.setValues(0.0, 0.0, 34.3); // toward the listener
      scene.update(AudioListener());
      // The velocity is a float32 `Vector3`, which holds 34.3 as
      // 34.2999992…: the rate is that close, not the double's.
      expect(car.spatial.rate, closeTo(343.0 / (343.0 - 34.3), 1e-7));
      expect(backend.live.single.rate, closeTo(car.spatial.rate, 1e-12));

      car.velocity.setValues(0.0, 0.0, -34.3); // away
      scene.update(AudioListener());
      expect(car.spatial.rate, lessThan(1.0));
    });

    test('a renderer of its own replaces the spatialisation entirely', () {
      // Mutation: keep measuring in the scene and ignore `spatial`. A
      // binaural renderer handed in would never be asked.
      final scene = AudioScene(backend: SilentBackend(), spatial: _Centre());
      final far = scene.play(_hum, Vector3(30.0, 0.0, 0.0));
      scene.update(AudioListener());
      expect(far.audibleGain, 0.25);
      expect(far.pan, 0.0);
    });
  });

  group('components that follow nodes', () {
    test('the listener reads a camera node, pitch and all', () {
      // Mutation: read +Z as forward. Every sound would pan to the other ear.
      final node = _at(1.0, 2.0, 3.0, yaw: math.pi / 2.0);
      final listener = AudioListener()..follow(() => node);
      listener.syncPose(0.0);
      expect(listener.position, Vector3(1.0, 2.0, 3.0));
      // Turned a quarter left about Y, −Z becomes −X.
      expect(listener.forward.x, closeTo(-1.0, 1e-9));
      expect(listener.right.z, closeTo(-1.0, 1e-9));
      expect(listener.up.y, closeTo(1.0, 1e-9));
    });

    test('a followed node moving gives a velocity in metres per second', () {
      // Mutation: divide by the frame count instead of the seconds. Half a
      // metre in a tenth of a second would read as half a metre per second.
      var node = _at(0.0, 0.0, 0.0);
      final listener = AudioListener()..follow(() => node);
      listener.syncPose(0.1);
      // The first read places; there is nothing yet to measure from.
      expect(listener.velocity.length, 0.0);
      node = _at(0.5, 0.0, 0.0);
      listener.syncPose(0.1);
      expect(listener.velocity.x, closeTo(5.0, 1e-9));
    });

    test('an attached emitter is placed at once and follows its node', () {
      // Mutation: read the node only from the next mix. A sound attached
      // and mixed in the same frame would start at the origin.
      var torch = _at(4.0, 0.0, 0.0);
      final scene = AudioScene(backend: SilentBackend());
      final hum = scene.attach(_hum, () => torch);
      expect(hum.position.x, 4.0);
      expect(hum.following, isNotNull);

      torch = _at(6.0, 0.0, 0.0);
      scene.update(AudioListener(), dt: 0.5);
      expect(hum.position.x, 6.0);
      expect(hum.velocity.x, closeTo(4.0, 1e-9));
    });
  });

  group('velocity from placements by hand', () {
    final ahead = Vector3(0.0, 0.0, -1.0);

    test('a listener placed each mix moves at the difference over dt', () {
      // Mutation: leave the velocity as it was, as `placeAt` used to. A
      // listener driven by `onListenerMoved` would never hear doppler.
      final listener = AudioListener()
        ..placeAt(
          const WorldPosition(0.0, 0.0, 0.0),
          ahead,
          origin: WorldPosition.origin,
        );
      final scene = AudioScene(backend: SilentBackend())
        ..update(listener, dt: 0.1);
      // The first placement measures nothing.
      expect(listener.velocity.length, 0.0);
      listener.placeAt(
        const WorldPosition(0.5, 0.0, 0.0),
        ahead,
        origin: WorldPosition.origin,
      );
      scene.update(listener, dt: 0.1);
      expect(listener.velocity.x, closeTo(5.0, 1e-9));
    });

    test('several placements between two mixes count as one move', () {
      // Mutation: measure each call against the one before. Two calls a
      // mix would read half the distance over the whole mix's seconds.
      final listener = AudioListener()
        ..placeAt(
          const WorldPosition(0.0, 0.0, 0.0),
          ahead,
          origin: WorldPosition.origin,
        );
      final scene = AudioScene(backend: SilentBackend())
        ..update(listener, dt: 0.5);
      listener
        ..placeAt(
          const WorldPosition(0.5, 0.0, 0.0),
          ahead,
          origin: WorldPosition.origin,
        )
        ..placeAt(
          const WorldPosition(1.0, 0.0, 0.0),
          ahead,
          origin: WorldPosition.origin,
        );
      scene.update(listener, dt: 0.5);
      expect(listener.velocity.x, closeTo(2.0, 1e-9));
    });

    test('a teleport is not heard as speed, and measuring starts again', () {
      // Mutation: ignore `teleport`. A respawn a hundred metres away in one
      // frame would be a thousand metres per second, a shriek of doppler.
      final listener = AudioListener()
        ..placeAt(
          const WorldPosition(0.0, 0.0, 0.0),
          ahead,
          origin: WorldPosition.origin,
        );
      final scene = AudioScene(backend: SilentBackend())
        ..update(listener, dt: 0.1);
      listener.placeAt(
        const WorldPosition(100.0, 0.0, 0.0),
        ahead,
        origin: WorldPosition.origin,
        teleport: true,
      );
      scene.update(listener, dt: 0.1);
      expect(listener.velocity.length, 0.0);
      listener.placeAt(
        const WorldPosition(100.2, 0.0, 0.0),
        ahead,
        origin: WorldPosition.origin,
      );
      scene.update(listener, dt: 0.1);
      // The position is float32: 100.2 is 100.1999969… there, a hundred
      // metres from the origin, and the difference over a tenth of a second
      // carries that.
      expect(listener.velocity.x, closeTo(2.0, 1e-4));
    });

    test('a velocity given outright wins over the difference', () {
      // Mutation: overwrite it with the measured one at the mix.
      final listener = AudioListener()
        ..placeAt(
          const WorldPosition(0.0, 0.0, 0.0),
          ahead,
          origin: WorldPosition.origin,
        );
      final scene = AudioScene(backend: SilentBackend())
        ..update(listener, dt: 0.1);
      listener.placeAt(
        const WorldPosition(1.0, 0.0, 0.0),
        ahead,
        origin: WorldPosition.origin,
        velocity: Vector3(0.0, 0.0, -3.0),
      );
      scene.update(listener, dt: 0.1);
      expect(listener.velocity, Vector3(0.0, 0.0, -3.0));
    });

    test('one not placed again before a mix has stood still', () {
      // Mutation: keep the last measured velocity. A car that parked would
      // keep its doppler shift for ever.
      final listener = AudioListener()
        ..placeAt(
          const WorldPosition(0.0, 0.0, 0.0),
          ahead,
          origin: WorldPosition.origin,
        );
      final scene = AudioScene(backend: SilentBackend())
        ..update(listener, dt: 0.1);
      listener.placeAt(
        const WorldPosition(1.0, 0.0, 0.0),
        ahead,
        origin: WorldPosition.origin,
      );
      scene.update(listener, dt: 0.1);
      expect(listener.velocity.x, closeTo(10.0, 1e-9));
      scene.update(listener, dt: 0.1);
      expect(listener.velocity.length, 0.0);
    });

    test('an emitter placed by hand feeds the doppler shift', () {
      // Mutation: derive only the listener's. A car moved by `placeAt`
      // would pass at one pitch.
      final backend = SilentBackend();
      final scene = AudioScene(
        backend: backend,
        spatial: const EqualPowerPanner(dopplerFactor: 1.0),
      );
      final listener = AudioListener();
      final car = scene.play(_hum, Vector3(0.0, 0.0, -10.0))
        ..placeAt(
          const WorldPosition(0.0, 0.0, -10.0),
          origin: WorldPosition.origin,
        );
      scene.update(listener, dt: 0.1);
      expect(car.spatial.rate, 1.0);
      // 3.43 metres closer in a tenth of a second: 34.3 m/s toward the ears.
      car.placeAt(
        const WorldPosition(0.0, 0.0, -6.57),
        origin: WorldPosition.origin,
      );
      scene.update(listener, dt: 0.1);
      expect(car.velocity.z, closeTo(34.3, 1e-4));
      expect(car.spatial.rate, closeTo(343.0 / (343.0 - 34.3), 1e-4));
    });
  });

  group('a paused backend', () {
    test('holds a sound started during the pause until it resumes', () {
      // Mutation: start the voice playing whatever the pause says. A shot
      // fired the frame a pause menu opened would ring out over it.
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend);
      final before = scene.play(_hum, Vector3(1.0, 0.0, 0.0));
      scene.update(AudioListener());
      backend.pause();
      scene
        ..play(_hum, Vector3(-1.0, 0.0, 0.0))
        ..update(AudioListener());
      expect(before.isAudible, isTrue);
      expect(backend.live, hasLength(2));
      expect(backend.live.every((SilentVoice v) => v.isPaused), isTrue);

      backend.resume();
      expect(backend.live.any((SilentVoice v) => v.isPaused), isFalse);
    });

    test('a voice started after resume plays at once', () {
      // Mutation: latch the pause into every later voice.
      final backend = SilentBackend()
        ..pause()
        ..resume();
      final scene = AudioScene(backend: backend)
        ..play(_hum, Vector3.zero())
        ..update(AudioListener());
      expect(scene.voiceCount, 1);
      expect(backend.live.single.isPaused, isFalse);
    });
  });

  group('the bus tree', () {
    test('a bus routed under another is turned down by it', () {
      // Mutation: multiply only bus and master. Turning effects down would
      // leave the dialogue routed under it as loud as before.
      final mixer = Mixer()
        ..setParent(_dialogue, AudioBus.sfx)
        ..setVolume(AudioBus.sfx, 0.5)
        ..setVolume(AudioBus.master, 0.5);
      expect(mixer.parentOf(_dialogue), AudioBus.sfx);
      expect(mixer.parentOf(AudioBus.master), isNull);
      expect(mixer.gainFor(_dialogue), closeTo(0.25, 1e-12));
      expect(mixer.routesThrough(_dialogue, AudioBus.master), isTrue);
    });

    test('a route that loops, or one from the master, is refused', () {
      // Mutation: drop the walk up the tree. `gainFor` would never return.
      final mixer = Mixer()..setParent(_dialogue, AudioBus.sfx);
      expect(
        () => mixer.setParent(AudioBus.sfx, _dialogue),
        throwsArgumentError,
      );
      expect(
        () => mixer.setParent(AudioBus.master, AudioBus.sfx),
        throwsArgumentError,
      );
    });

    test('effect slots hold a game\'s effects, and a low-pass muffles', () {
      // Mutation: `muffleFor` reads only the bus itself. A low-pass on the
      // master would not reach the effects routed into it.
      final mixer = Mixer()
        ..setEffect(AudioBus.master, 0, const LowPassEffect(600.0));
      expect(mixer.effectIn(AudioBus.master, 0), const LowPassEffect(600.0));
      expect(mixer.muffleFor(AudioBus.sfx), 1.0);
      expect(
        () => mixer.setEffect(AudioBus.sfx, Mixer.effectSlots, null),
        throwsRangeError,
      );
      expect(const LowPassEffect(LowPassEffect.openHz).muffle, 0.0);
      final half = math.sqrt(LowPassEffect.openHz * LowPassEffect.wallHz);
      expect(LowPassEffect(half).muffle, closeTo(0.5, 1e-12));
    });
  });

  group('snapshots', () {
    final underWater = MixSnapshot(
      'under water',
      levels: <AudioBus, double>{AudioBus.sfx: -20.0},
      effects: <AudioBus, List<BusEffect>>{
        AudioBus.sfx: const <BusEffect>[LowPassEffect(600.0)],
      },
      blendInSeconds: 1.0,
      blendOutSeconds: 0.0,
    );

    test('blend in over their seconds and out at once when told', () {
      // Mutation: blend in gain rather than in decibels. Half way in would
      // be about −6 dB, not −10.
      final mixer = Mixer()..enterSnapshot(underWater);
      expect(mixer.snapshotWeight('under water'), 0.0);
      mixer.advance(0.5);
      expect(mixer.levelOf(AudioBus.sfx), closeTo(-10.0, 1e-12));
      expect(
        mixer.gainFor(AudioBus.sfx),
        closeTo(decibelsToGain(-10.0), 1e-12),
      );
      expect(mixer.muffleFor(AudioBus.sfx), closeTo(0.5, 1e-12));
      mixer.advance(0.75);
      expect(mixer.snapshotWeight('under water'), 1.0);
      expect(mixer.levelOf(AudioBus.sfx), -20.0);

      mixer.leaveSnapshot('under water');
      expect(mixer.snapshots, isEmpty);
      expect(mixer.gainFor(AudioBus.sfx), 1.0);
      expect(mixer.muffleFor(AudioBus.sfx), 0.0);
    });

    test('add to each other, and never move a slider', () {
      // Mutation: a snapshot that sets volumes. A pause menu would save the
      // player's music at a level they never chose.
      final mixer = Mixer()
        ..setVolume(AudioBus.music, 0.8)
        ..enterSnapshot(
          MixSnapshot(
            'paused',
            levels: <AudioBus, double>{AudioBus.music: -6.0},
            blendInSeconds: 0.0,
          ),
        )
        ..enterSnapshot(
          MixSnapshot(
            'boss',
            levels: <AudioBus, double>{AudioBus.music: 3.0},
            blendInSeconds: 0.0,
          ),
        );
      expect(mixer.levelOf(AudioBus.music), closeTo(-3.0, 1e-12));
      expect(mixer.volumeOf(AudioBus.music), 0.8);
      expect(mixer.toJson(), <String, Object?>{'music': 0.8});
    });

    test('reach the voices of a scene: quieter and duller', () {
      // Mutation: leave the bus's low-pass out of the voice's muffle. Under
      // water would only be quieter.
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend)
        ..play(_hum, Vector3(1.0, 0, 0));
      scene.mixer.enterSnapshot(underWater);
      scene.update(AudioListener(), dt: 1.0);
      final voice = backend.live.single;
      expect(voice.gain, closeTo(decibelsToGain(-20.0), 1e-12));
      expect(voice.muffle, 1.0);
    });
  });

  group('ducking', () {
    test('the music goes down under a line and comes back after it', () {
      // Mutation: measure the trigger after its slider. A player who turned
      // the dialogue down would stop it ducking the music.
      const rule = DuckRule(
        trigger: _dialogue,
        target: AudioBus.music,
        depthDecibels: -12.0,
        attackSeconds: 0.1,
        releaseSeconds: 0.5,
      );
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend)
        ..mixer.addDucking(rule)
        ..mixer.setVolume(_dialogue, 0.0);
      final music = scene.play(_music, Vector3.zero());
      final line = scene.play(_line, Vector3.zero());
      final ears = AudioListener();

      scene.update(ears, dt: 0.1); // the line is heard
      scene.update(ears, dt: 0.1); // and the music ducks under it
      expect(scene.mixer.duckingOf(rule), 1.0);
      expect(scene.mixer.levelOf(AudioBus.music), -12.0);
      final voice = backend.live.firstWhere((v) => v.asset == _music.asset);
      expect(voice.gain, closeTo(decibelsToGain(-12.0), 1e-12));

      line.stop();
      scene
        ..update(ears, dt: 0.1)
        ..update(ears, dt: 0.25);
      expect(scene.mixer.duckingOf(rule), closeTo(0.5, 1e-12));
      scene.update(ears, dt: 0.25);
      expect(scene.mixer.levelOf(AudioBus.music), 0.0);
      expect(music.isStopped, isFalse);
    });
  });

  group('backends that opt into more', () {
    test('a mixing backend gets the buses and voices without them', () {
      // Mutation: fold the bus into the voice for a mixing backend too. It
      // would apply the bus a second time.
      final backend = _Opted();
      final scene = AudioScene(backend: backend)
        ..mixer.setVolume(AudioBus.music, 0.5)
        ..mixer.setEffect(AudioBus.music, 1, const ReverbEffect())
        ..play(_music, Vector3.zero());
      scene.update(AudioListener());
      final voice = backend.inner.live.single;
      expect(voice.gain, 1.0);
      expect(backend.routed[voice], AudioBus.music);
      expect(backend.busGains[AudioBus.music], 0.5);
      expect(backend.busEffects[AudioBus.music], <BusEffect>[
        const ReverbEffect(),
      ]);
      expect(backend.parents[AudioBus.music], AudioBus.master);
      expect(backend.busGains[AudioBus.master], 1.0);
    });

    test('a directional backend is handed where each voice is', () {
      // Mutation: place only on start. A voice that moved would keep the
      // direction it began with.
      final backend = _Opted();
      final scene = AudioScene(backend: backend);
      final hum = scene.play(_hum, Vector3(2.0, 0.0, 0.0));
      scene.update(AudioListener());
      hum.position.setValues(-2.0, 0.0, 0.0);
      scene.update(AudioListener());
      expect(
        backend.azimuths[backend.inner.live.single],
        closeTo(-math.pi / 2.0, 1e-9),
      );
    });
  });

  group('buses for what plays through them', () {
    test('held voices play on the bus they are given', () {
      // Mutation: ignore the bus and play on the sound's own. An ambience
      // routed under "world" would escape a snapshot on it.
      const world = AudioBus('world');
      final scene = AudioScene(backend: SilentBackend());
      HeldVoices(
        _hum,
        bus: world,
      ).hold(scene, <Held>[(key: 1, at: Vector3.zero(), gain: 1.0, rate: 1.0)]);
      expect(scene.emitters.single.bus, world);
      HeldVoices(
        _hum,
      ).hold(scene, <Held>[(key: 1, at: Vector3.zero(), gain: 1.0, rate: 1.0)]);
      expect(scene.emitters.last.bus, AudioBus.sfx);
    });

    test('a bank lists the buses its sounds play on, once each', () {
      // Mutation: a list rather than a set. A bank of twenty effects would
      // list the effects bus twenty times.
      final bank = SoundBank(<SoundDef>[_hum, _music, _line, _hum.copyAs('x')]);
      expect(bank.buses, <AudioBus>[AudioBus.sfx, AudioBus.music, _dialogue]);
    });
  });

  group('the plugin', () {
    test('mixes once a frame in the loop\'s audio phase', () {
      // Mutation: register in a step phase. A paused game would never mix,
      // and a view plugin would be refused at install.
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend)
        ..play(_hum, Vector3(1.0, 0, 0));
      const rule = DuckRule(trigger: _dialogue, target: AudioBus.music);
      final plugin = AudioPlugin(
        scene: () => scene,
        listener: AudioListener(),
        ducking: <DuckRule>[rule],
      );
      expect(plugin.manifest.touches, PluginTouches.view);
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[plugin],
      );
      expect(backend.live, isEmpty);
      loop.frame(1.0 / 60.0);
      expect(backend.live, hasLength(1));
      expect(scene.mixer.duckings, <DuckRule>[rule]);

      // Paused, the frame phases still run, and so does the mix.
      loop.isPaused = true;
      scene.mixer.enterSnapshot(
        MixSnapshot(
          'paused',
          levels: <AudioBus, double>{AudioBus.sfx: -12.0},
          blendInSeconds: 0.1,
        ),
      );
      loop.frame(0.05);
      expect(scene.mixer.snapshotWeight('paused'), closeTo(0.5, 1e-9));
    });
  });
}

/// A renderer that hears everything from the middle at a quarter.
final class _Centre extends SpatialRenderer {
  @override
  void render(SpatialQuery query, SpatialResult out) {
    out
      ..gain = 0.25
      ..pan = 0.0
      ..muffle = 0.0;
  }
}

extension on SoundDef {
  SoundDef copyAs(String name) =>
      SoundDef(name: name, asset: asset, loop: loop, bus: bus);
}
