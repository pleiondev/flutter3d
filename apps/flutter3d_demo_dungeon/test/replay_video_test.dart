/// `rp-05`, run rather than argued: a `.f3drun` rendered to a video with no
/// GPU, and a `.f3drun` checked against its own digests without drawing a
/// pixel.
///
///     flutter test test/replay_video_test.dart
///
/// **Why this is a test and not `dart run flutter3d:replay`.** The plan's own
/// syntax names a CLI in a `build` package (`flutter3d_build`) that does not
/// exist yet — it is `ap-10`'s to create, in `doc/asset-pipeline-plan.md`.
/// What is real today, and what this file proves, is the mechanism
/// underneath that command: replaying a genre's own simulation from a
/// `.f3drun` cannot be a plain `dart run` script regardless of which package
/// eventually hosts it, because every genre package depends on Flutter
/// (`pointer_lock` alone pulls in `dart:ui` for `Offset`) — measured by
/// trying it, the same way `wg-00` measures rather than assumes. `flutter
/// test` is the shape that already works for headless rendering in this
/// repository (`frame_test.dart`), so the two pieces `--video` and `--check`
/// would be are written and proved here, and `flutter3d_build` wraps them in
/// an actual terminal command whenever `ap-10` exists to receive them.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
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

/// The crypt, loaded and dressed — the same assembly `frame_test.dart` uses,
/// so a replay is drawn the way the shipped game draws rather than the way a
/// harness imagines it.
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
/// `frame_test.dart`'s `_drawFromTheStart` builds.
Future<Uint8List> _drawOne(
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
  return pixels.buffer.asUint8List();
}

/// Replays [demo]'s tape into a fresh crypt and reports the first checkpoint
/// that disagrees with the ones it was recorded with, or null if none does —
/// `--check`, without drawing a single pixel.
Future<Divergence?> checkReplay(Demo demo) async {
  final shown = await _shown();
  shown.level.staged.sim.restore(demo.start);
  final input = shown.input;
  final playback = InputTapePlayback(demo.tape);
  final trace = DigestTrace(every: demo.checkpoints.every);
  var step = 0;
  while (!playback.isFinished) {
    playback.applyTo(input);
    shown.level.staged.sim.step(_dt);
    step++;
    trace.observe(step, shown.level.staged.sim.save().toJson());
    input.endStep();
  }
  return trace.divergenceFromHex(demo.checkpoints.hexDigests);
}

/// Replays [demo]'s tape, draws every step, and stitches the frames into
/// [outputPath] with `ffmpeg` — `--video`, no GPU anywhere in the pipeline.
Future<void> renderReplayVideo(Demo demo, String outputPath) async {
  final frameDir = Directory.systemTemp.createTempSync('replay_frames');
  try {
    final shown = await _shown();
    shown.level.staged.sim.restore(demo.start);
    final input = shown.input;
    final playback = InputTapePlayback(demo.tape);
    var step = 0;
    while (!playback.isFinished) {
      playback.applyTo(input);
      shown.level.staged.sim.step(_dt);
      step++;
      input.endStep();
      final pixels = await _drawOne(shown);
      final png = encodePng(pixels, _width, _height);
      File(
        '${frameDir.path}/frame_${step.toString().padLeft(6, '0')}.png',
      ).writeAsBytesSync(png);
    }

    final result = Process.runSync('ffmpeg', <String>[
      '-y',
      '-framerate',
      '60',
      '-i',
      '${frameDir.path}/frame_%06d.png',
      '-pix_fmt',
      'yuv420p',
      outputPath,
    ]);
    if (result.exitCode != 0) {
      throw StateError('ffmpeg failed: ${result.stderr}');
    }
  } finally {
    frameDir.deleteSync(recursive: true);
  }
}

Future<Demo> _recordAShortRun({int steps = 20}) async {
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

  test(
    '--check: a genuine replay matches its own recorded checkpoints',
    () async {
      final demo = await _recordAShortRun();
      final divergence = await checkReplay(demo);
      expect(divergence, isNull);
    },
  );

  test('--check: a tampered checkpoint is named by step', () async {
    final demo = await _recordAShortRun();
    final tamperedHex = List<String>.of(demo.checkpoints.hexDigests);
    tamperedHex[1] = '00000000';
    final tampered = Demo(
      level: demo.level,
      levelHash: demo.levelHash,
      start: demo.start,
      tape: demo.tape,
      buildStamp: demo.buildStamp,
      checkpoints: DigestTrace.fromJson(<String, Object?>{
        'every': demo.checkpoints.every,
        'steps': demo.checkpoints.steps,
        'digests': tamperedHex,
      }),
    );

    final divergence = await checkReplay(tampered);
    expect(divergence, isNotNull);
    expect(divergence!.step, demo.checkpoints.steps[1]);
  });

  test(
    '--video: a replay renders to an actual playable file via ffmpeg',
    () async {
      final demo = await _recordAShortRun(steps: 8);
      final dir = Directory.systemTemp.createTempSync('replay_video_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final outputPath = '${dir.path}/replay.mp4';

      await renderReplayVideo(demo, outputPath);

      final output = File(outputPath);
      expect(output.existsSync(), isTrue);
      expect(
        output.lengthSync(),
        greaterThan(0),
        reason: 'ffmpeg produced an empty file, which is not a video',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
