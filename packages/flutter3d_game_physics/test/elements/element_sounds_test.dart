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
    Audible(key: key, at: Vector3(x, 0.0, 0.0), loudness: 0.5, rate: 1.0);

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

  group('a body wading', () {
    Wader wader({required bool wet, double speed = 20.0}) =>
        Wader(key: 0, at: Vector3(1.0, 0.0, 2.0), wet: wet, speed: speed);

    int splashes(AudioScene scene, ElementCues cues) =>
        scene.emitters.where((e) => e.sound == cues.splash).length;

    test('splashes once as it goes in at speed, and is washed while it '
        'ploughs through', () {
      // What racing played of a car in a ford, folded in here. Mutation:
      // drop the edge (play the splash whenever it is wet) — the second
      // frame in the water splashes again.
      final scene = AudioScene(backend: SilentBackend());
      final sounds = ElementSounds(ElementCues.circuit);
      sounds.wade(scene, <Wader>[wader(wet: false)], 1 / 60);
      expect(splashes(scene, ElementCues.circuit), 0);

      sounds.wade(scene, <Wader>[wader(wet: true)], 1 / 60);
      expect(splashes(scene, ElementCues.circuit), 1);
      expect(sounds.held, 1, reason: 'the wash, held while it wades');

      sounds.wade(scene, <Wader>[wader(wet: true)], 1 / 60);
      expect(splashes(scene, ElementCues.circuit), 1);

      // Out of the water and the wash goes.
      sounds.wade(scene, <Wader>[wader(wet: false)], 1 / 60);
      expect(sounds.held, 0);
    });

    test('in and out again at once is one splash, not two', () {
      // A car hopping along the edge of a puddle. Mutation: drop the hush —
      // the second entry splashes too.
      final scene = AudioScene(backend: SilentBackend());
      final sounds = ElementSounds(ElementCues.circuit);
      for (final wet in <bool>[true, false, true]) {
        sounds.wade(scene, <Wader>[wader(wet: wet)], 1 / 60);
      }
      expect(splashes(scene, ElementCues.circuit), 1);
    });

    test('a body crawling in makes no splash and no wash', () {
      final scene = AudioScene(backend: SilentBackend());
      final sounds = ElementSounds(ElementCues.circuit)
        ..wade(scene, <Wader>[wader(wet: false, speed: 1.0)], 1 / 60)
        ..wade(scene, <Wader>[wader(wet: true, speed: 1.0)], 1 / 60);
      expect(splashes(scene, ElementCues.circuit), 0);
      expect(sounds.held, 0);
    });

    test('the circuit\'s cues are racing\'s, the wash its own voice', () {
      // A wash held by a wader's key must not take a fall's voice of the
      // same key: they are held apart. Mutation: hold the washes among the
      // falls — the two share key 0 and one voice is held, not two.
      final scene = AudioScene(backend: SilentBackend());
      final sounds = ElementSounds(ElementCues.circuit)
        ..hear(scene, falls: <Audible>[_audible(0, 5.0)])
        ..wade(scene, <Wader>[wader(wet: true)], 1 / 60);
      expect(sounds.held, 2);
      expect(ElementCues.circuit.wash.asset, endsWith('falls_loop.wav'));
      expect(ElementCues.circuit.all, contains(ElementCues.circuit.wash));
    });
  });
}
