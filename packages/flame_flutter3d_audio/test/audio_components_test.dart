/// A Flame game's sound: silent until the speakers open, loops held by the
/// components that want them, and ears on the game's 3D camera.
library;

import 'package:flame/components.dart' show Component;
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flame_flutter3d_audio/flame_flutter3d_audio.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter_test/flutter_test.dart';

const SoundDef _engine = SoundDef(
  name: 'engine',
  asset: 'engine.wav',
  loop: true,
  attenuation: NoAttenuation(),
);

const SoundDef _boom = SoundDef(
  name: 'boom',
  asset: 'boom.wav',
  attenuation: NoAttenuation(),
);

/// Speakers that make no sound and remember what they were asked, and
/// whether they were closed.
final class _Speakers {
  final SilentBackend backend = SilentBackend();
  late final AudioScene scene = AudioScene(backend: backend);
  int opened = 0;
  bool closed = false;

  Future<OpenedSpeakers?> open() async {
    opened++;
    return (scene: scene, close: () async => closed = true);
  }
}

final class _World extends FlameGame with HasFlutter3d {}

void main() {
  testWithGame<FlameGame>(
    'a loop waits in silence, and moves onto the speakers when they open',
    FlameGame.new,
    (game) async {
      final speakers = _Speakers();
      final audio = AudioSceneComponent(
        bank: SoundBank(const <SoundDef>[_engine]),
        opener: speakers.open,
      );
      final engine = SoundEmitterComponent(_engine);
      await game.addAll(<Component>[audio, engine]);
      await game.ready();

      game.update(1 / 60);
      expect(audio.isOpen, isFalse);
      expect(speakers.backend.started, isEmpty, reason: 'nothing heard yet');

      await Future.wait(<Future<void>>[audio.open(), audio.open()]);
      expect(speakers.opened, 1, reason: 'twice is once');
      game.update(1 / 60);
      expect(speakers.backend.live.map((v) => v.asset), <String>['engine.wav']);
    },
  );

  testWithGame<FlameGame>(
    'a loop stops when it is no longer wanted, and when its component goes',
    FlameGame.new,
    (game) async {
      final speakers = _Speakers();
      final audio = AudioSceneComponent(
        bank: SoundBank(const <SoundDef>[_engine]),
        opener: speakers.open,
      );
      final engine = SoundEmitterComponent(_engine);
      await game.addAll(<Component>[audio, engine]);
      await game.ready();
      await audio.open();
      game.update(1 / 60);
      expect(speakers.backend.live, hasLength(1));

      engine.playing = false;
      game.update(1 / 60);
      expect(speakers.backend.live, isEmpty);

      engine.playing = true;
      game.update(1 / 60);
      expect(speakers.backend.live, hasLength(1));

      engine.removeFromParent();
      await game.ready();
      game.update(1 / 60);
      expect(speakers.backend.live, isEmpty, reason: 'left running');
    },
  );

  testWithGame<FlameGame>(
    'one-shots play into the scene, and closing goes back to silence',
    FlameGame.new,
    (game) async {
      final speakers = _Speakers();
      final audio = AudioSceneComponent(
        bank: SoundBank(const <SoundDef>[_boom]),
        opener: speakers.open,
      );
      await game.add(audio);
      await game.ready();
      await audio.open();

      audio.play(_boom);
      game.update(1 / 60);
      expect(speakers.backend.started.single.asset, 'boom.wav');

      await audio.close();
      expect(speakers.closed, isTrue);
      expect(audio.isOpen, isFalse);
    },
  );

  testWithGame<_World>(
    'the ears are on the 3D camera, and a bridged loop sounds from its craft',
    _World.new,
    (game) async {
      game.open3d(FakeBackend());
      game.camera3d.setPosition(1.0, 2.0, 3.0);
      final audio = AudioSceneComponent(
        bank: SoundBank(const <SoundDef>[_engine]),
      );
      final jet = Object3dComponent(
        node: SceneNode(),
        scene: game.scene,
        plane: BridgePlane.ground(),
        direction: SyncDirection.flameToScene,
        elevation: 1.5,
        position: Vector2(4.0, -10.0),
      );
      final engine = SoundEmitterComponent(_engine);
      jet.add(engine);
      await game.addAll(<Component>[audio, jet]);
      await game.ready();
      game.update(1 / 60);

      expect(audio.listener.position, Vector3(1.0, 2.0, 3.0));
      final at = engine.emitter!.position;
      expect(at.x, closeTo(4.0, 1e-6));
      expect(at.y, closeTo(1.5, 1e-6));
      expect(at.z, closeTo(-10.0, 1e-6));
    },
  );

  testWithGame<FlameGame>(
    'a loop added before the scene, in the same batch, still finds it',
    FlameGame.new,
    (game) async {
      // What River Sortie did: its loops and its sound in one addAll, the
      // loops mounted first and found no scene to play into.
      //
      // Mutation: look for the scene once, on mount.
      final speakers = _Speakers();
      final engine = SoundEmitterComponent(_engine);
      final audio = AudioSceneComponent(
        bank: SoundBank(const <SoundDef>[_engine]),
        opener: speakers.open,
      );
      await game.addAll(<Component>[engine, audio]);
      await game.ready();
      await audio.open();
      game.update(1 / 60);
      expect(speakers.backend.live, hasLength(1));
    },
  );
}
