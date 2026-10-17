import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const SoundDef _crackle = SoundDef(
  name: 'crackle',
  asset: 'a/crackle.ogg',
  loop: true,
  attenuation: InverseRolloff(reference: 1.0, maximum: 50.0),
);

Held _at(int key, double x, {double gain = 1.0}) =>
    (key: key, at: Vector3(x, 0.0, 0.0), gain: gain, rate: 1.0);

void main() {
  test('a voice a key, held while heard and stopped when not', () {
    final scene = AudioScene(backend: SilentBackend());
    final voices = HeldVoices(_crackle);
    voices.hold(scene, <Held>[_at(1, 2.0), _at(2, 4.0)]);
    expect(voices.count, 2);
    final first = scene.emitters.first;
    // The same thing heard again moves its voice rather than starting one.
    voices.hold(scene, <Held>[_at(1, 3.0, gain: 0.5), _at(2, 4.0)]);
    expect(scene.emitters, hasLength(2));
    expect(first.position.x, 3.0);
    expect(first.gain, 0.5);
    // Gone from what is heard, its voice stops; the other plays on.
    voices.hold(scene, <Held>[_at(2, 4.0)]);
    expect(voices.count, 1);
    expect(first.isStopped, isTrue);
  });

  test('a new scene begins its voices again', () {
    final silent = AudioScene(backend: SilentBackend());
    final speakers = AudioScene(backend: SilentBackend());
    final voices = HeldVoices(_crackle)..hold(silent, <Held>[_at(1, 1.0)]);
    voices.hold(speakers, <Held>[_at(1, 1.0)]);
    expect(speakers.emitters, hasLength(1));
    voices.silence();
    expect(voices.count, 0);
    expect(speakers.emitters.single.isStopped, isTrue);
  });
}
