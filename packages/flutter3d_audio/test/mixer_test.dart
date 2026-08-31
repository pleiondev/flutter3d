/// Volume buses, and the one decision in them that is not obvious: a bus is
/// spent at the backend, not at the point where the mixer decides which sounds
/// get voices at all.
library;

import 'dart:convert';

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const SoundDef _track = SoundDef(
  name: 'theme',
  asset: 'music/theme.ogg',
  loop: true,
  bus: AudioBus.music,
  // Loud where it stands, so that losing its voice can only be the bus's doing.
  attenuation: NoAttenuation(),
);

const SoundDef _step = SoundDef(name: 'step', asset: 'sfx/step.ogg');

AudioListener _ears() => AudioListener()..position.setZero();

void main() {
  group('the table', () {
    test('an unset bus is full, not silent', () {
      // A settings file nobody has written yet must not mute the game.
      expect(Mixer().volumeOf(AudioBus.music), 1.0);
      expect(Mixer().gainFor(AudioBus.music), 1.0);
    });

    test('a bus is multiplied by master', () {
      final mixer = Mixer()
        ..setVolume(AudioBus.music, 0.5)
        ..setVolume(AudioBus.master, 0.5);

      expect(mixer.gainFor(AudioBus.music), 0.25);
      // Master is an ordinary bus that everything is also on, so asking for it
      // must not square it.
      expect(mixer.gainFor(AudioBus.master), 0.5);
    });

    test('volumes are clamped and round-trip through text', () {
      final mixer = Mixer()
        ..setVolume(AudioBus.music, 2.0)
        ..setVolume(AudioBus.sfx, -1.0);

      expect(mixer.volumeOf(AudioBus.music), 1.0);
      expect(mixer.volumeOf(AudioBus.sfx), 0.0);

      final read = Mixer.fromJson(
        jsonDecode(jsonEncode(mixer.toJson())) as Map<String, Object?>,
      );
      expect(read.volumeOf(AudioBus.sfx), 0.0);
      expect(read.volumeOf(AudioBus.music), 1.0);
    });
  });

  group('the scene', () {
    test('a bus turns a sound down without touching the others', () {
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend)
        ..play(_track, Vector3.zero())
        ..play(_step, Vector3.zero())
        ..update(_ears());

      final before = backend.live.map((SilentVoice v) => v.gain).toList();
      expect(before.every((double g) => g > 0.0), isTrue);

      scene.mixer.setVolume(AudioBus.music, 0.0);
      scene.update(_ears());

      final music =
          backend.started.firstWhere((SilentVoice v) => v.asset == _track.asset);
      final step =
          backend.started.firstWhere((SilentVoice v) => v.asset == _step.asset);
      expect(music.gain, 0.0);
      expect(step.gain, greaterThan(0.0));
    });

    test('a muted loop keeps its voice instead of being stopped', () {
      // Mutation: apply the bus inside `_measure` instead, so `audibleGain`
      // carries it. The music's gain reaches zero, the chooser drops it, the
      // backend is told to stop, and turning the slider back up restarts the
      // track from the beginning — which is what a player notices and what
      // this whole design decision is about.
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend)..play(_track, Vector3.zero());
      scene.update(_ears());

      final voice = backend.started.single;
      expect(voice.alive, isTrue);

      scene.mixer.setVolume(AudioBus.master, 0.0);
      scene.update(_ears());

      expect(voice.alive, isTrue, reason: 'silent, and still playing');
      expect(voice.gain, 0.0);
      expect(backend.started, hasLength(1), reason: 'and never restarted');

      scene.mixer.setVolume(AudioBus.master, 1.0);
      scene.update(_ears());

      expect(backend.started, hasLength(1), reason: 'it carried on in place');
      expect(voice.gain, greaterThan(0.0));
    });

    test('a sound with no bus named is an effect', () {
      final backend = SilentBackend();
      final scene = AudioScene(backend: backend)..play(_step, Vector3.zero());
      scene.mixer.setVolume(AudioBus.sfx, 0.0);
      scene.update(_ears());

      expect(backend.started.single.gain, 0.0);
    });
  });
}
