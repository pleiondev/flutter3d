/// What a pause of the speakers holds, and what it leaves to the mix.
///
///     flutter test test/speakers_test.dart
///
/// The speakers over a silent backend, which records what a device would
/// have been told: the same `Speakers` a game gets from `openSpeakers`, with
/// the device swapped for one a test can read.
library;

import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const SoundDef _torch = SoundDef(
  name: 'torch',
  asset: 'a/torch.ogg',
  loop: true,
  attenuation: InverseRolloff(reference: 1.0, maximum: 40.0),
);

const SoundDef _door = SoundDef(
  name: 'door',
  asset: 'a/door.ogg',
  attenuation: InverseRolloff(reference: 1.0, maximum: 40.0),
);

Speakers _speakers(SilentBackend backend) => Speakers(
  backend: backend,
  scene: AudioScene(backend: backend),
);

void main() {
  test('a pause holds the voices playing and the ones started under it', () {
    final backend = SilentBackend();
    final speakers = _speakers(backend);
    final ears = AudioListener();
    speakers.scene.play(_torch, Vector3(0.0, 0.0, -3.0));
    speakers.scene.update(ears);

    speakers.pause();
    speakers.scene.play(_door, Vector3(2.0, 0.0, -2.0));
    speakers.scene.update(ears);

    expect(backend.isPaused, isTrue);
    expect(backend.live, hasLength(2));
    expect(
      backend.live.every((SilentVoice voice) => voice.isPaused),
      isTrue,
      reason: 'the door played under the pause menu waits for the resume',
    );

    speakers.resume();
    expect(backend.live.any((SilentVoice voice) => voice.isPaused), isFalse);
  });

  test('the mix goes on under a pause, so a resume hears it as it is', () {
    final backend = SilentBackend();
    final speakers = _speakers(backend);
    final ears = AudioListener();
    final torch = speakers.scene.play(_torch, Vector3(0.0, 0.0, -3.0));
    speakers.scene.update(ears);
    final before = backend.live.single.gain;

    speakers.pause();
    torch.position.setValues(0.0, 0.0, -12.0);
    speakers.scene.update(ears);

    expect(backend.live.single.isPaused, isTrue);
    expect(backend.live.single.gain, lessThan(before));
    speakers.resume();
    expect(backend.live.single.gain, lessThan(before));
  });

  test('twice is once, and a resume without a pause changes nothing', () {
    final backend = SilentBackend();
    final speakers = _speakers(backend);
    speakers.scene.play(_torch, Vector3(0.0, 0.0, -3.0));
    speakers.scene.update(AudioListener());

    speakers.resume();
    speakers.pause();
    speakers.pause();
    expect(backend.live.single.isPaused, isTrue);
    speakers.resume();
    expect(backend.live.single.isPaused, isFalse);
    expect(backend.isDisposed, isFalse, reason: 'a pause releases nothing');
  });
}
