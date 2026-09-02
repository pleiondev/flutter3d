/// What a wall does to a sound: quieter, and duller.
///
///     flutter test test/occlusion_test.dart
///
/// The scene asks the world how much of a sound gets through and hands the
/// backend two numbers for it: the gain, which every backend applies, and the
/// muffle, which one that can filter turns into a low-pass cutoff. The
/// second is the half a wall used to be missing.
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

AudioListener _ears() => AudioListener()..aimAt(Vector3.zero(), 0.0);

void main() {
  test('a wall reaches the voice as a muffle beside the gain', () async {
    final backend = SilentBackend();
    // Half gets through: a torch behind one wall.
    final scene = AudioScene(backend: backend, occlusion: (_, _) => 0.5);
    await scene.preload(<SoundDef>[_torch]);

    scene.play(_torch, Vector3(0.0, 0.0, -3.0));
    scene.update(_ears());

    final voice = backend.live.single;
    expect(voice.muffle, closeTo(0.5, 1e-9));
    expect(voice.gain, closeTo(0.5 * _torch.attenuation.gainAt(3.0), 1e-9));
  });

  test('and follows the wall as the listener moves', () async {
    final backend = SilentBackend();
    var through = 1.0;
    final scene = AudioScene(backend: backend, occlusion: (_, _) => through);
    await scene.preload(<SoundDef>[_torch]);
    scene.play(_torch, Vector3(0.0, 0.0, -3.0));
    scene.update(_ears());
    expect(backend.live.single.muffle, 0.0, reason: 'clear line');

    through = 0.25;
    scene.update(_ears());

    expect(backend.live.single.muffle, closeTo(0.75, 1e-9));
    expect(backend.live.single.updates, 1);
  });

  test('no occlusion callback is a clear world', () async {
    final backend = SilentBackend();
    final scene = AudioScene(backend: backend);
    await scene.preload(<SoundDef>[_torch]);
    scene.play(_torch, Vector3(0.0, 0.0, -3.0));
    scene.update(_ears());

    expect(backend.live.single.muffle, 0.0);
  });
}
