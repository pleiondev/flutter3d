/// `rp-05`'s own literal acceptance: "frame 600 of the run is the same as
/// the reference" — the golden half `replay_video_test.dart`'s own doc
/// comment left for this file, and `packages/flutter3d_testing/test/
/// replay_golden_test.dart`'s own doc comment already named this exact path
/// as "where the picture is checked."
///
///     flutter test test/replay_golden_test.dart
///
/// **Not through `replayGolden()` itself.** That function asks its own
/// `frame:` callback to build a scene against a *fresh* device — the shape a
/// caller with no scene of its own yet needs — but this file already has
/// one, built once by `_shown()` and stepped in place exactly the way
/// `replay_video_test.dart` already proves draws correctly frame after
/// frame. Rebuilding a second scene from the document just to hand it to
/// `replayGolden` would draw the *level*, not the *run* — a fresh load knows
/// nothing of where the tape actually left the player and every monster.
/// `expectMatchesGolden` is `replayGolden`'s own last step, called directly
/// here on the frame `_drawOne` already knows how to draw.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;
const int _width = 160;
const int _height = 100;

final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};
  @override
  String? read(String name) => documents[name];
  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

/// The crypt, loaded and dressed — the same assembly `frame_test.dart` and
/// `replay_video_test.dart` both use, so a golden is drawn the way the
/// shipped game draws rather than the way a harness imagines it.
Future<
  ({LevelReady level, InputState input, CpuDevice device, Renderer renderer})
>
_shown() async {
  final it = cpuTestDevice(width: _width, height: _height);
  final input = InputState();
  final run = RunCubit(
    DungeonRun(
      firstLevel: 'assets/levels/crypt.json',
      registry: sampleRegistry(extra: const <EntityKind>[WidgetSurfaceKind()]),
      input: input,
      inventory: startingInventory(),
      saves: SaveFile(appName: 'dungeon', storage: _Storage()),
      device: it.device,
    ),
  );
  await run.begin();
  final state = run.state;
  return (
    level: (state as RunPlaying<LevelReady>).level,
    input: input,
    device: it.device,
    renderer: Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    ),
  );
}

void _play(InputState input, int step) {
  if (step % 40 < 30) {
    input.press(GameAction.moveForward);
  } else {
    input.release(GameAction.moveForward);
  }
  input.addLook((step % 7 - 3) * 0.01, 0.0);
}

/// One frame, from where the player stands right now — the same camera
/// `frame_test.dart`'s `_drawFromTheStart` and `replay_video_test.dart`'s
/// `_drawOne` both build.
Future<RenderedFrame> _drawOne(
  ({LevelReady level, InputState input, CpuDevice device, Renderer renderer})
  shown,
) async {
  final player = shown.level.staged.player;
  final scene = shown.level.loaded.scene;
  final eye = Vector3.zero();
  final aim = Vector3.zero();
  player
    ..eye(eye)
    ..aim(aim);
  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.2,
      near: 0.05,
      far: 200.0,
    ),
  )..setPositionFrom(eye);
  camera.lookAt(eye + aim);
  scene.add(camera);
  final result = shown.renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: const RenderSettings(),
  );
  final pixels = await shown.device.readPixels(result.frame);
  scene.remove(camera);
  if (pixels == null) {
    throw StateError('the frame could not be read back');
  }
  return (
    pixels: pixels.buffer.asUint8List(),
    width: _width,
    height: _height,
    drawCalls: result.drawCalls,
  );
}

/// Records a short, deterministic tape the same way `replay_video_test.dart`
/// does — walked, not typed, so the golden below is a picture of the game
/// actually playing rather than of a scripted camera.
Future<Demo> _recordAShortRun({int steps = 30}) async {
  final live = await _shown();
  final start = live.level.staged.sim.save();
  final input = live.input;
  final recorder = InputTapeRecorder(seed: start.data.integer('random'));
  final checkpoints = DigestTrace(every: 5);
  for (var i = 0; i < steps; i++) {
    _play(input, i);
    recorder.record(input);
    live.level.staged.sim.step(_dt);
    checkpoints.observe(
      recorder.tape.steps,
      live.level.staged.sim.save().toJson(),
    );
    input.endStep();
  }
  return Demo(
    level: 'assets/levels/crypt.json',
    levelHash: 'deadbeef',
    start: start,
    tape: recorder.tape,
    buildStamp: 'test-build',
    checkpoints: checkpoints,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("rp-05's own literal row: the frame at the tape's own last step matches "
      'a committed reference', () async {
    final demo = await _recordAShortRun();

    final shown = await _shown();
    shown.level.staged.sim.restore(demo.start);
    final playback = InputTapePlayback(demo.tape);
    while (!playback.isFinished) {
      playback.applyTo(shown.input);
      shown.level.staged.sim.step(_dt);
      shown.input.endStep();
    }

    final frame = await _drawOne(shown);
    await expectMatchesGolden(frame, 'test/goldens/replay-frame.png');
  });

  test('replaying the same recorded tape twice, fresh each time, draws the '
      'same bytes both times', () async {
    final demo = await _recordAShortRun(steps: 12);

    Future<Uint8List> replayed() async {
      final shown = await _shown();
      shown.level.staged.sim.restore(demo.start);
      final playback = InputTapePlayback(demo.tape);
      while (!playback.isFinished) {
        playback.applyTo(shown.input);
        shown.level.staged.sim.step(_dt);
        shown.input.endStep();
      }
      return (await _drawOne(shown)).pixels;
    }

    final first = await replayed();
    final second = await replayed();
    expect(second, first);
  });
}
