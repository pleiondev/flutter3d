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

/// Moves the 3D camera a metre a frame, from the game's root after Flame's
/// camera, where a synced camera is moved.
final class _CameraMover extends Component {
  _CameraMover(this.camera) : super(priority: BridgePriority.afterFlameCamera);

  final CameraNode camera;

  @override
  void update(double dt) {
    super.update(dt);
    camera.translate(1.0, 0.0, 0.0);
  }
}

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
    'added to the world, the ears are where the camera is this frame',
    _World.new,
    (game) async {
      // A priority orders siblings only: inside the world the mix ran before
      // anything at the game's root after Flame's camera, and heard from
      // where the camera had been.
      //
      // Mutation: work the mix out in the component's own update.
      game.open3d(FakeBackend());
      final audio = AudioSceneComponent(
        bank: SoundBank(const <SoundDef>[_engine]),
      );
      await game.world.add(audio);
      await game.add(_CameraMover(game.camera3d));
      await game.ready();

      game.update(1 / 60);

      expect(audio.listener.position.x, 1.0);
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

  testWithGame<FlameGame>(
    'speakers refused once are asked again on the next open',
    FlameGame.new,
    (game) async {
      // A browser refuses sound before the first touch, and a refusal
      // stayed for the rest of the game.
      //
      // Mutation: keep the finished open.
      final speakers = _Speakers();
      var refuse = true;
      final audio = AudioSceneComponent(
        bank: SoundBank(const <SoundDef>[_engine]),
        opener: () async => refuse ? null : speakers.open(),
      );
      await game.add(audio);
      await game.ready();

      await audio.open();
      expect(audio.isOpen, isFalse);
      refuse = false;
      await audio.open();
      expect(audio.isOpen, isTrue);
    },
  );

  testWithGame<FlameGame>(
    'closed while the device is opening, it stays closed',
    FlameGame.new,
    (game) async {
      // Mutation: install whatever arrives.
      final speakers = _Speakers();
      final audio = AudioSceneComponent(
        bank: SoundBank(const <SoundDef>[_engine]),
        opener: () async {
          await Future<void>.delayed(Duration.zero);
          return speakers.open();
        },
      );
      await game.add(audio);
      await game.ready();

      final opening = audio.open();
      await audio.close();
      await opening;
      expect(audio.isOpen, isFalse);
      expect(speakers.closed, isTrue, reason: 'the late device is let go');
    },
  );

  testWithGame<FlameGame>(
    'paused, every loop falls silent at once, and comes back on resume',
    FlameGame.new,
    (game) async {
      // A paused game is not updated, and the engine droned on under the
      // pause menu at its last loudness.
      //
      // Mutation: turn the mix down and wait for an update to apply it.
      final speakers = _Speakers();
      final audio = AudioSceneComponent(
        bank: SoundBank(const <SoundDef>[_engine]),
        opener: speakers.open,
      );
      await game.addAll(<Component>[audio, SoundEmitterComponent(_engine)]);
      await game.ready();
      await audio.open();
      game.update(1 / 60);
      final voice = speakers.backend.live.single;
      final loud = voice.gain;
      expect(loud, greaterThan(0.0));

      audio.pause();
      expect(voice.gain, 0.0);
      expect(voice.alive, isTrue, reason: 'held, not stopped');

      audio.resume();
      expect(voice.gain, closeTo(loud, 1e-9));
    },
  );

  testWithGame<FlameGame>(
    'a new sound for the game is found by the loops already playing',
    FlameGame.new,
    (game) async {
      // A restarted level with a new AudioSceneComponent was silent: the
      // loops played on into the old one.
      //
      // Mutation: keep the first sound found for good.
      final first = _Speakers();
      final second = _Speakers();
      final old = AudioSceneComponent(
        bank: SoundBank(const <SoundDef>[_engine]),
        opener: first.open,
      );
      await game.addAll(<Component>[old, SoundEmitterComponent(_engine)]);
      await game.ready();
      await old.open();
      game.update(1 / 60);

      old.removeFromParent();
      final fresh = AudioSceneComponent(
        bank: SoundBank(const <SoundDef>[_engine]),
        opener: second.open,
      );
      await game.add(fresh);
      await game.ready();
      await fresh.open();
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      expect(second.backend.live, hasLength(1));
    },
  );

  testWithGame<FlameGame>(
    'a one-shot is not played again when the speakers open',
    FlameGame.new,
    (game) async {
      // Mutation: start it again on every new scene.
      final speakers = _Speakers();
      final audio = AudioSceneComponent(
        bank: SoundBank(const <SoundDef>[_boom]),
        opener: speakers.open,
      );
      await game.addAll(<Component>[audio, SoundEmitterComponent(_boom)]);
      await game.ready();
      game.update(1 / 60);
      await audio.open();
      game.update(1 / 60);
      expect(speakers.backend.started, isEmpty);
    },
  );
}
