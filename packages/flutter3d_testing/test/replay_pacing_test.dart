/// `N3`'s harness: a tape played a step a frame, each frame timed.
///
///     flutter test test/replay_pacing_test.dart
///
/// The clock is scripted, so the numbers are the test's own and the
/// arithmetic is what is checked; `apps/flutter3d_demo_dungeon` plays a real
/// run through it, and `tool/pacing.sh` on a real device.
library;

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';

Demo _demo({int steps = 10}) => Demo(
  level: 'nowhere',
  levelHash: 'deadbeef',
  start: const Snapshot(<String, Object?>{}),
  tape: InputTape(
    seed: 1,
    frames: List<InputFrame>.generate(steps, (_) => const InputFrame()),
  ),
  buildStamp: 'test-build',
  checkpoints: DigestTrace(every: 5),
);

void main() {
  group('FramePacing', () {
    test('the median, the tail and the worst frame of a run', () {
      final pacing = FramePacing.of(<double>[
        for (var i = 1; i <= 100; i++) i.toDouble(),
      ]);
      expect(pacing.frames, 100);
      expect(pacing.p50, 50.0);
      expect(pacing.p99, 99.0);
      expect(pacing.max, 100.0);
      expect(pacing.worstFrame, 99);
      // Frames 51 to 100 are over fifty milliseconds: indices 50 to 99.
      expect(pacing.overLimit, <int>[for (var i = 50; i < 100; i++) i]);
      expect(pacing.even, isFalse);
    });

    test('a frame at the limit is not a spike; one past it is', () {
      expect(FramePacing.of(<double>[16.0, 50.0, 16.0]).even, isTrue);
      final one = FramePacing.of(<double>[16.0, 50.5, 16.0]);
      expect(one.overLimit, <int>[1]);
      expect(one.worstFrame, 1);
    });

    test('no frames is an empty report, not an error', () {
      final none = FramePacing.of(const <double>[]);
      expect(none.frames, 0);
      expect(none.worstFrame, -1);
      expect(none.even, isTrue);
    });
  });

  group('replayPacing', () {
    test(
      'times each step and its draw together, a frame per tape entry',
      () async {
        // Each frame costs two milliseconds of step and draw, and the seventh
        // draw stalls for sixty.
        var micros = 0;
        final order = <String>[];
        final pacing = await replayPacing(
          demo: _demo(),
          input: InputState(),
          clock: () => micros,
          onStep: (dt) {
            order.add('step');
            micros += 1000;
          },
          drawFrame: (frame) async {
            order.add('draw $frame');
            micros += frame == 6 ? 61000 : 1000;
          },
        );
        expect(pacing.frames, 10);
        expect(order.take(4), <String>['step', 'draw 0', 'step', 'draw 1']);
        expect(pacing.p50, 2.0);
        expect(pacing.max, 62.0);
        // Mutation: start the timer after `onStep`, and the spike is 61 and
        // the median one.
        expect(pacing.overLimit, <int>[6]);
      },
    );

    test(
      'repeats rewind and replay; warm-up frames run but are not kept',
      () async {
        var rewinds = 0;
        var draws = 0;
        final pacing = await replayPacing(
          demo: _demo(steps: 4),
          input: InputState(),
          repeats: 3,
          warmUpFrames: 2,
          rewind: () => rewinds++,
          onStep: (dt) {},
          drawFrame: (frame) async => draws++,
        );
        expect(rewinds, 3);
        expect(draws, 12);
        expect(pacing.frames, 10);
      },
    );

    test('a frame on the software device settles at once', () async {
      final device = CpuDevice(
        width: 4,
        height: 4,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      await expectLater(gpuSettled(device), completes);
    });
  });
}
