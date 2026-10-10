/// Decision 9: a run records its simulation, a tape from another is refused
/// with a reason, and the poses written beside it play anyway.
///
///     dart test test/replay_simulation_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const SimulationVersion _platformer1 = SimulationVersion(genre: 'platformer');
const SimulationVersion _platformer2 = SimulationVersion(
  genre: 'platformer',
  genreVersion: 2,
);

PoseRecord _poses() {
  final recorder = PoseRecorder(every: 3);
  for (var step = 0; step <= 9; step++) {
    recorder.record(step, <BodyPose>[
      BodyPose(
        'runner',
        Vector3(step.toDouble(), 0.0, 0.0),
        Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.25),
      ),
    ]);
  }
  return recorder.recorded;
}

Demo _demo({SimulationVersion? simulation, PoseRecord? poses}) => Demo(
  level: 'assets/levels/a.json',
  levelHash: 'deadbeef',
  start: const Snapshot(<String, Object?>{'random': 1}),
  tape: InputTape(seed: 1, frames: const <InputFrame>[InputFrame()]),
  buildStamp: 'test',
  checkpoints: DigestTrace(every: 1),
  simulation: simulation,
  poses: poses,
);

Demo _roundTrip(Demo demo) => Demo.fromJson(
  jsonDecode(jsonEncode(demo.toJson())) as Map<String, Object?>,
);

void main() {
  group('the simulation version', () {
    test('travels in the run and does not move its format version', () {
      final read = _roundTrip(_demo(simulation: _platformer2));

      expect(read.simulation, _platformer2);
      // Additive, like the platform: an older reader ignores it and plays
      // the run as before. Mutation: count it in `writtenVersion` and every
      // run becomes unreadable to the build before.
      expect(_demo(simulation: _platformer2).toJson()['version'], 1);
    });

    test('the same simulation replays', () {
      expect(_demo(simulation: _platformer1).refusalOn(_platformer1), isNull);
    });

    test('an older simulation is refused with both numbers named', () {
      final reason = _demo(simulation: _platformer1).refusalOn(_platformer2)!;

      // Mutation: compare only the engine number and a genre's tuning change
      // replays into a divergence that reads like a bug.
      expect(reason, contains('platformer 1'));
      expect(reason, contains('platformer 2'));
      expect(reason, contains('not replayed'));
    });

    test('a newer simulation asks for an update', () {
      final reason = _demo(simulation: _platformer2).refusalOn(_platformer1)!;

      expect(reason, contains('update flutter3d'));
    });

    test('a run from another genre is refused as that', () {
      final reason = _demo(
        simulation: const SimulationVersion(genre: 'racing'),
      ).refusalOn(_platformer1)!;

      expect(reason, contains('racing'));
    });

    test('checkSimulation throws with the pose record to show instead', () {
      final demo = _demo(simulation: _platformer1, poses: _poses());

      // Mutation: throw without the poses and every tool has to dig them out
      // of the file it already gave up on.
      expect(
        () => demo.checkSimulation(_platformer2),
        throwsA(
          isA<ReplayException>()
              .having((r) => r.poses, 'poses', same(demo.poses))
              .having((r) => r.message, 'message', contains('pose record')),
        ),
      );
      expect(() => demo.checkSimulation(_platformer1), returnsNormally);
    });

    test('a nonsense number is refused rather than guessed', () {
      final json = _demo(simulation: _platformer1).toJson();
      (json['simulation']! as Map<String, Object?>)['engine'] = 'one';

      expect(() => Demo.fromJson(json), throwsA(isA<DemoFormatException>()));
    });
  });

  group('the pose record', () {
    test('is taken every few steps, not every step', () {
      // Mutation: record on every call and the record is as big as the run.
      expect(_poses().frames.map((f) => f.step), <int>[0, 3, 6, 9]);
    });

    test('survives the file, to a millimetre', () {
      final read = _roundTrip(_demo(poses: _poses())).poses!;

      expect(read.every, 3);
      expect(read.bodies, <String>['runner']);
      expect(read.frames.last.bodies.single![0], 9.0);
      expect(read.frames.last.bodies.single![4], closeTo(0.1247, 1e-4));
    });

    test('a body that leaves is written absent, in one null', () {
      final recorder = PoseRecorder(every: 1)
        ..record(0, <BodyPose>[
          BodyPose('a', Vector3.zero(), Quaternion.identity()),
          BodyPose('b', Vector3.all(1.0), Quaternion.identity()),
        ])
        ..record(1, <BodyPose>[
          BodyPose('b', Vector3.all(2.0), Quaternion.identity()),
        ]);
      final json = recorder.recorded.toJson();
      final frames = json['frames']! as List<Object?>;

      // Mutation: write seven zeros for a missing body and a destroyed crate
      // reappears at the origin in every viewer.
      expect((frames[1]! as Map<String, Object?>)['b'], hasLength(8));
      final read = PoseRecord.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(read.frames[1].bodies[0], isNull);
      expect(read.frames[1].bodies[1]![0], 2.0);
    });

    test('a truncated frame is refused with the step it stopped at', () {
      final json = _poses().toJson();
      final frame =
          (json['frames']! as List<Object?>).last! as Map<String, Object?>;
      frame['b'] = (frame['b']! as List<Object?>).sublist(0, 5);

      expect(
        () => PoseRecord.fromJson(json),
        throwsA(
          isA<PoseRecordFormatException>().having(
            (e) => e.message,
            'message',
            contains('step 9'),
          ),
        ),
      );
    });

    test('a body becomes the ghost\'s tape, which plays', () {
      final track = _poses().track('runner');

      expect(track.poses.map((p) => p.position.x), <double>[0, 3, 6, 9]);
      expect(track.poses.first.yaw, closeTo(0.25, 1e-3));
      // The ghost's own player draws it: the pose record reuses the ghost's
      // format rather than standing beside it. Mutation: time the poses in
      // steps rather than seconds and the ghost runs sixty times too fast.
      final out = Pose();
      expect(Playback(track).sampleAt(4.5 / 60.0, out), isTrue);
      expect(out.position.x, closeTo(4.5, 0.1));
      expect(_poses().track('nobody').isEmpty, isTrue);
    });
  });
}
