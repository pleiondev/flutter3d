import 'package:flutter3d_lab/flutter3d_lab.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Demo, Level;
import 'package:test/test.dart';

void main() {
  group('PendulumSimulation', () {
    test('a longer pendulum swings slower than a shorter one', () {
      final short = PendulumSimulation(lengthMeters: 0.5);
      final long = PendulumSimulation(lengthMeters: 2.0);
      // Both start at the same angle and rest; after the same number of
      // steps the short one has moved further from its start, because its
      // period is shorter — real physics, not a stub that always answers
      // the same number regardless of length.
      for (var i = 0; i < 30; i++) {
        short.step(labFixedDt);
        long.step(labFixedDt);
      }
      expect((short.theta - 0.6).abs(), greaterThan((long.theta - 0.6).abs()));
    });

    test('rejects a non-positive length', () {
      expect(() => PendulumSimulation(lengthMeters: 0.0), throwsArgumentError);
      expect(() => PendulumSimulation(lengthMeters: -1.0), throwsArgumentError);
      final p = PendulumSimulation(lengthMeters: 1.0);
      expect(() => p.lengthMeters = 0.0, throwsArgumentError);
    });
  });

  group('PendulumLabRun', () {
    test('the same length run twice is bit-for-bit the same run', () {
      final a = PendulumLabRun(startLength: 1.0, steps: 300);
      final b = PendulumLabRun(startLength: 1.0, steps: 300);
      expect(a.checkpoints.divergenceFrom(b.checkpoints.digests), isNull);
      expect(a.lengths.toJson(), b.lengths.toJson());
    });

    test('two different lengths diverge, and the check names a real step', () {
      final short = PendulumLabRun(
        startLength: 0.6,
        steps: 300,
        checkpointEvery: 10,
      );
      final long = PendulumLabRun(
        startLength: 1.4,
        steps: 300,
        checkpointEvery: 10,
      );
      final divergence = short.checkpoints.divergenceFrom(
        long.checkpoints.digests,
      );
      // A bit-exact digest has no tolerance: two different lengths already
      // read different `theta` after one step, so the very first checkpoint
      // already disagrees — found by running this, not assumed beforehand.
      // What matters for `edu-04`'s "what if" is that the check finds a real,
      // named step rather than silently agreeing on nothing.
      expect(divergence, isNotNull);
      expect(divergence!.step, short.checkpoints.steps.first);
      expect(divergence.expected, isNot(equals(divergence.found)));
    });

    test("ls-e-01's own acceptance: divergenceFrom names the step and the two "
        'lengths that disagreed', () {
      final assignment = PendulumLabRun(
        startLength: 1.0,
        steps: 300,
        checkpointEvery: 10,
      );
      final student = PendulumLabRun(
        startLength: 1.4,
        steps: 300,
        checkpointEvery: 10,
      );

      final found = student.divergenceFrom(assignment);
      expect(found, isNotNull);
      expect(found!.checkpoint.step, student.checkpoints.steps.first);
      expect(found.assignmentLength, 1.0);
      expect(found.studentLength, 1.4);
    });

    test('two runs of the same length report no divergence at all', () {
      final assignment = PendulumLabRun(startLength: 1.0, steps: 200);
      final student = PendulumLabRun(startLength: 1.0, steps: 200);
      expect(student.divergenceFrom(assignment), isNull);
    });

    test('a "what if" branch leaves the original run untouched', () {
      final original = PendulumLabRun(
        startLength: 1.0,
        steps: 200,
        checkpointEvery: 20,
      );
      final originalDigestsBefore = List<int>.of(original.checkpoints.digests);
      final originalLengthsBefore = original.lengths.toJson();

      final branch = original.branchAt(100, 200, (step, currentLength) => 2.0);

      // The original is untouched — same object, same recorded numbers.
      expect(original.checkpoints.digests, originalDigestsBefore);
      expect(original.lengths.toJson(), originalLengthsBefore);

      // The branch agrees with the original up to and including step 100 —
      // it resumed from that exact state, not from the nearest checkpoint.
      expect(branch.stateAt(100), original.stateAt(100));

      // And it disagrees afterwards, because it swung a 2 m pendulum from
      // there on rather than a 1 m one.
      final afterBranch = branch.stateAt(200);
      final afterOriginal = original.stateAt(200);
      expect(afterBranch, isNot(equals(afterOriginal)));
    });

    test('branchAt refuses a step outside the run', () {
      final run = PendulumLabRun(startLength: 1.0, steps: 50);
      expect(() => run.branchAt(51, 60, (step, l) => l), throwsArgumentError);
      expect(() => run.branchAt(-1, 60, (step, l) => l), throwsArgumentError);
    });

    test('toDemo writes a genuine, replayable-shaped .f3drun', () {
      final run = PendulumLabRun(
        startLength: 1.2,
        steps: 90,
        checkpointEvery: 15,
      );
      final level = Level(name: 'pendulum-lab');
      final demo = run.toDemo(
        levelPath: 'assets/levels/pendulum_lab.json',
        level: level,
        buildStamp: 'test',
      );

      expect(demo.steps, 90);
      expect(demo.levelHash, level.digestHex);
      expect(demo.checkpoints.digests, run.checkpoints.digests);
      expect(demo.dataSources, isNotNull);
      expect(demo.dataSources!.length, 90);

      final json = demo.toJson();
      final reread = Demo.fromJson(json);
      expect(reread.checkpoints.digests, demo.checkpoints.digests);
      expect(reread.dataSources!.toJson(), demo.dataSources!.toJson());
    });

    test(
      'a panel that changes length mid-run is recorded at the step it changed',
      () {
        final run = PendulumLabRun(
          startLength: 1.0,
          steps: 40,
          lengthAt: (step, currentLength) => step < 20 ? 1.0 : 1.5,
        );
        expect(run.lengths.valueAt(19)!['length'], 1.0);
        expect(run.lengths.valueAt(20)!['length'], 1.5);
        expect(run.lengths.valueAt(40)!['length'], 1.5);
      },
    );
  });
}
