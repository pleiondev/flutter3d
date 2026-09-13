/// `rp-05`'s golden half: replay a `.f3drun` to one step, draw it, compare.
///
///     flutter test test/replay_golden_test.dart
///
/// An empty scene rather than a shipped level, on purpose — the mechanism
/// under test is the replay (how many times `onStep` runs, and what happens
/// when the tape is shorter than [replayGolden] was asked for), not a
/// picture. A real game's own frame test is where the picture is checked;
/// `apps/flutter3d_demo_dungeon`'s `replay_golden_test.dart` is that one.
library;

import 'dart:io';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Demo _demo({int steps = 10}) {
  final checkpoints = DigestTrace(every: 5);
  return Demo(
    level: 'nowhere',
    levelHash: 'deadbeef',
    start: const Snapshot(<String, Object?>{}),
    tape: InputTape(
      seed: 1,
      frames: List<InputFrame>.generate(steps, (_) => const InputFrame()),
    ),
    buildStamp: 'test-build',
    checkpoints: checkpoints,
  );
}

FrameSubject _emptyScene(FrameRequest request) {
  final scene = Scene();
  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.2,
      near: 0.05,
      far: 200.0,
    ),
  )..setPositionFrom(Vector3(0.0, 0.0, 5.0));
  camera.lookAt(Vector3.zero());
  scene.add(camera);
  return (scene: scene, camera: camera);
}

void main() {
  test('drives onStep exactly atStep times, in tape order', () async {
    var calls = 0;
    final dir = Directory.systemTemp.createTempSync('replay_golden_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    await replayGolden(
      demo: _demo(steps: 10),
      atStep: 6,
      input: InputState(),
      onStep: (dt) => calls++,
      width: 16,
      height: 16,
      frame: _emptyScene,
      goldenPath: '${dir.path}/frame.png',
    );

    expect(calls, 6, reason: 'six steps asked for, six steps taken');
    expect(File('${dir.path}/frame.png').existsSync(), isTrue);
  });

  test('throws when the tape ends before atStep, not a rendering failure', () {
    expect(
      () => replayGolden(
        demo: _demo(steps: 3),
        atStep: 10,
        input: InputState(),
        onStep: (dt) {},
        width: 16,
        height: 16,
        frame: _emptyScene,
        goldenPath: '${Directory.systemTemp.path}/should_not_be_written.png',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('ended at step 3'),
        ),
      ),
    );
  });

  test('a second replay to the same step matches the recorded golden', () async {
    final dir = Directory.systemTemp.createTempSync('replay_golden_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final goldenPath = '${dir.path}/frame.png';

    Future<void> once() => replayGolden(
      demo: _demo(steps: 10),
      atStep: 6,
      input: InputState(),
      onStep: (dt) {},
      width: 16,
      height: 16,
      frame: _emptyScene,
      goldenPath: goldenPath,
    );

    await once(); // records
    await once(); // compares against what it just recorded
  });
}
