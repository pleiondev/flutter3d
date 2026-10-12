import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:test/test.dart';

/// A backend that opts into both capabilities and writes none of their
/// members: what one written against 1.0 looks like after a minor adds one.
final class _Bare extends AudioBackend with MixingBackend, DirectionalBackend {
  @override
  Future<void> preload(String asset) async {}

  @override
  VoiceId? start(VoiceStart voice) => voice.asset;

  @override
  void update(VoiceUpdate voice) {}

  @override
  void stop(VoiceId voice) {}

  @override
  bool isAlive(VoiceId voice) => true;
}

void main() {
  test('a capability mixed in with no members of its own does nothing', () {
    final backend = _Bare();
    expect(backend, isA<MixingBackend>());
    expect(backend, isA<DirectionalBackend>());
    backend
      ..routeVoice(VoiceRoute(voice: 'voice', bus: AudioBus.sfx))
      ..mixBus(
        BusMix(
          bus: AudioBus.sfx,
          parent: AudioBus.master,
          gain: 0.5,
          effects: const <BusEffect>[],
        ),
      )
      ..placeVoice(VoicePlacement(voice: 'voice', spatial: SpatialResult()));
  });

  test('a silent voice is made by name', () {
    final voice = SilentVoice(
      id: 3,
      asset: 'step.wav',
      gain: 0.5,
      pan: -0.25,
      rate: 1.5,
      loop: true,
    );
    expect(voice.id, 3);
    expect(voice.asset, 'step.wav');
    expect(voice.gain, 0.5);
    expect(voice.pan, -0.25);
    expect(voice.rate, 1.5);
    expect(voice.loop, isTrue);
    expect(voice.isAlive, isTrue);
  });
}
