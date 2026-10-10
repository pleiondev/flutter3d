/// The elements heard: [ElementSounds] holds a voice to every fire and fall
/// of water and plays each splash.
///
///     flutter test test/elements/element_sounds_test.dart
///
/// Each test was written against the mutation named in it: the change to the
/// package that would let it pass while the package was wrong.
library;

import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_game_physics/elements.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Audible _audible(int key, double x) =>
    Audible(key, Vector3(x, 0.0, 0.0), 0.5, 1.0);

void main() {
  test('the elements are held by key, and a fire held elsewhere is not', () {
    // Mutation: ignore `heldElsewhere`. A torch would crackle twice, once
    // from its own loop and once from here.
    final scene = AudioScene(backend: SilentBackend());
    final sounds = ElementSounds();
    sounds.hear(
      scene,
      fires: <Audible>[_audible(64, 1.0), _audible(128, 2.0)],
      falls: <Audible>[_audible(3, 0.0)],
      splashes: <Audible>[_audible(4, 0.0)],
      heldElsewhere: (fire) => fire.key ~/ 64 == 1,
    );
    expect(sounds.held, 2);
    expect(
      scene.emitters.where((e) => e.sound == ElementCues.near.splash),
      hasLength(1),
    );
    sounds.hear(scene);
    expect(sounds.held, 0, reason: 'nothing heard, nothing held');
    expect(ElementCues.near.all, hasLength(3));
  });
}
