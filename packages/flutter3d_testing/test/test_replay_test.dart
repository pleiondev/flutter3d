/// `N5`: a tape replayed on the software backend, checked by digest and by
/// golden.
///
///     flutter test test/test_replay_test.dart
///
/// A walker on a line rather than a shipped level, for the reason
/// `replay_golden_test.dart` gives: what is under test is the replay — which
/// steps are checked, what a divergence says, what is refused before a step
/// is taken — and a counter makes every one of those visible. A real game's
/// replay test is `apps/flutter3d_demo_platformer/test/replay_test.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;
const String _levelHash = 'c0ffee00';

/// Walks forward while the button is held, and counts every step.
final class _Walker implements ReplaySubject {
  _Walker(this.input, {this.strayFrom, this.hash});

  final InputState input;

  /// The step from which this walker goes twice as far — a change to the
  /// simulation that only shows after it.
  final int? strayFrom;

  final String? hash;

  double x = 0.0;
  int steps = 0;
  final List<int> framesAt = <int>[];

  @override
  String? get levelHash => hash;

  @override
  void restore(Snapshot start) {
    x = start.data.number('x');
    steps = start.data.integer('steps');
  }

  @override
  void step(double dt) {
    steps++;
    final stray = strayFrom != null && steps >= strayFrom!;
    if (input.held(GameAction.moveForward)) x += stray ? 2.0 : 1.0;
  }

  @override
  Snapshot save() => Snapshot(<String, Object?>{'x': x, 'steps': steps});

  @override
  FrameSubject frame(int step) {
    framesAt.add(step);
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
}

/// Twenty steps of the walker, held forward on two steps out of three, with
/// a checkpoint every five — the way a game's own recorder writes a run.
Demo _record({int steps = 20}) {
  final input = InputState();
  final walker = _Walker(input);
  final start = walker.save();
  final recorder = InputTapeRecorder(seed: 1);
  final checkpoints = DigestTrace(every: 5);
  for (var i = 0; i < steps; i++) {
    i % 3 == 2
        ? input.release(GameAction.moveForward)
        : input.press(GameAction.moveForward);
    recorder.record(input);
    walker.step(_dt);
    checkpoints.observe(recorder.tape.steps, walker.save().toJson());
    input.endStep();
  }
  return Demo(
    level: 'line.json',
    levelHash: _levelHash,
    start: start,
    tape: recorder.tape,
    buildStamp: 'test-build',
    checkpoints: checkpoints,
  );
}

Matcher _failsWith(String text) => throwsA(
  isA<TestFailure>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('test_replay_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the same simulation replays its own tape and every checkpoint '
      'agrees', () async {
    // Mutation: drop `playback.applyTo(input)` from `expectReplayMatches`,
    // and the walker stands still through the replay and diverges at step 5.
    late _Walker walker;
    await expectReplayMatches(
      _record(),
      start: (start) => walker = _Walker(start.input),
      width: 16,
      height: 16,
    );
    // Mutation: stop at the first checkpoint rather than the last, and only
    // five steps are taken.
    expect(walker.steps, 20, reason: 'the last checkpoint is at step 20');
  });

  test('a changed simulation fails at the first checkpoint it changed '
      'before, and names the one that still agreed', () async {
    // Mutation: compare the digest after `endStep` against a recorder that
    // took it before, or compare nothing, and a walker that goes twice as
    // far from step 8 passes.
    await expectLater(
      expectReplayMatches(
        _record(),
        start: (start) => _Walker(start.input, strayFrom: 8),
        width: 16,
        height: 16,
        label: 'line.f3drun',
      ),
      _failsWith('line.f3drun diverged at step 10'),
    );
    await expectLater(
      expectReplayMatches(
        _record(),
        start: (start) => _Walker(start.input, strayFrom: 8),
        width: 16,
        height: 16,
      ),
      _failsWith('Step 5 still agreed'),
    );
  });

  test('digestAt checks only the steps it names', () async {
    // Mutation: ignore `digestAt` and check every checkpoint, and the stray
    // from step 8 is caught at step 10, which this test did not ask about.
    late _Walker walker;
    await expectReplayMatches(
      _record(),
      start: (start) => walker = _Walker(start.input, strayFrom: 8),
      digestAt: <int>[5],
      width: 16,
      height: 16,
    );
    expect(walker.steps, 5, reason: 'nothing past the last step asked for');
  });

  test('goldensAt draws at the steps it names, into goldenDirectory, and a '
      'second replay matches what the first recorded', () async {
    // Mutation: draw only at the last step asked for, and `framesAt` is
    // [10]; name the file after its place in the list rather than its step,
    // and `line-3.png` is not where it is looked for.
    late _Walker walker;
    Future<void> once() => expectReplayMatches(
      _record(),
      start: (start) => walker = _Walker(start.input),
      digestAt: const <int>[],
      goldensAt: <int>[3, 10],
      goldenDirectory: dir.path,
      goldenName: 'line',
      width: 16,
      height: 16,
      // Recording is what the first call is for, even on a CI runner.
      recordMissing: true,
    );
    await once();
    expect(walker.framesAt, <int>[3, 10]);
    expect(File('${dir.path}/line-3.png').existsSync(), isTrue);
    expect(File('${dir.path}/line-10.png').existsSync(), isTrue);
    await once();
  });

  group('refuses before it steps', () {
    Future<_Walker> refused(
      Matcher failure, {
      Iterable<int>? digestAt,
      Iterable<int> goldensAt = const <int>[],
      Demo? demo,
      String? hash,
    }) async {
      _Walker? walker;
      await expectLater(
        expectReplayMatches(
          demo ?? _record(),
          start: (start) => walker = _Walker(start.input, hash: hash),
          digestAt: digestAt,
          goldensAt: goldensAt,
          goldenDirectory: dir.path,
          width: 16,
          height: 16,
        ),
        failure,
      );
      return walker ?? _Walker(InputState());
    }

    test('a digest at a step the tape holds no checkpoint for', () async {
      // Mutation: skip the check, and `recorded[7]!` throws a null check
      // error that names neither the step nor the checkpoints there are.
      await refused(
        _failsWith('no checkpoint at step 7: it took one every 5 steps'),
        digestAt: <int>[7],
      );
    });

    test('a golden past the end of the tape', () async {
      // Mutation: skip the check, and the replay steps an empty tape past
      // its end, draws a frame of a walker who stopped, and records it.
      await refused(
        _failsWith('lasts 20 steps, so there is no step 21'),
        goldensAt: <int>[21],
      );
    });

    test('a replay that checks nothing', () async {
      // Mutation: skip the check, and `reduce` throws on an empty set — or,
      // written with a default, the test passes whatever the game does.
      await refused(_failsWith('checks nothing'), digestAt: const <int>[]);
    });

    test('a level that changed since the recording', () async {
      // Mutation: skip the check, and the failure is a divergence at step 5,
      // which sends the reader into the simulation.
      final walker = await refused(
        _failsWith('the level line.json has changed'),
        hash: 'baadf00d',
      );
      expect(walker.steps, 0, reason: 'refused before the first step');
    });
  });

  group('readTape', () {
    test('names the path when there is no file there', () {
      // Mutation: let `File.readAsStringSync` throw, and the report is a
      // PathNotFoundException rather than what to do about it.
      expect(
        () => readTape('${dir.path}/missing.f3drun'),
        _failsWith('no tape at ${dir.path}/missing.f3drun'),
      );
    });

    test("says why a file is not a tape, in the format's own words", () {
      // Mutation: let the DemoFormatException through, and the path is lost.
      final file = File('${dir.path}/half.f3drun')
        ..writeAsStringSync(jsonEncode(<String, Object?>{'version': 1}));
      expect(
        () => readTape(file.path),
        _failsWith('${file.path} is not a tape: the demo names no level'),
      );
    });

    test('reads back what a recorder wrote', () {
      // Mutation: read the tape but drop its checkpoints, and a replay of it
      // has nothing to compare against.
      final demo = _record();
      final file = File('${dir.path}/line.f3drun')
        ..writeAsStringSync(jsonEncode(demo.toJson()));
      final read = readTape(file.path);
      expect(read.steps, 20);
      expect(read.checkpoints.hexDigests, demo.checkpoints.hexDigests);
    });
  });
}
