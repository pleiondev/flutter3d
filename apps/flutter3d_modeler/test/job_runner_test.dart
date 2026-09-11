/// `Job`: `ui-25`'s own chunked, cancellable runner, without Flutter.
///
///     dart test test/job_runner_test.dart
library;

import 'package:flutter3d_modeler/src/job_runner.dart';
import 'package:test/test.dart';

void main() {
  group('Job', () {
    test('ten chunks report progress from 0.1 to 1.0 — the row\'s own worked '
        'example', () async {
      final progresses = <double>[];
      final job = Job<int>(
        chunkCount: 10,
        runChunk: (int index) async {},
        onProgress: progresses.add,
      );

      final outcome = await job.run(() => 42);

      expect(outcome, isA<JobFinished<int>>());
      expect((outcome as JobFinished<int>).value, 42);
      expect(progresses, <double>[
        0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0,
      ]);
      expect(job.progress, 1.0);
    });

    test('cancelling during the third chunk gives no result, and no chunk '
        'after it runs — the row\'s own worked example', () async {
      final ran = <int>[];
      late final Job<int> job;
      job = Job<int>(
        chunkCount: 10,
        runChunk: (int index) async {
          ran.add(index);
          if (index == 2) job.cancel();
        },
      );

      final outcome = await job.run(() => 42);

      expect(outcome, isA<JobCancelled<int>>());
      expect(ran, <int>[0, 1, 2]);
      expect(job.progress, closeTo(0.3, 1e-9));
    });

    test('cancelling before the first chunk runs none of them', () async {
      final ran = <int>[];
      final job = Job<String>(
        chunkCount: 5,
        runChunk: (int index) async => ran.add(index),
      );
      job.cancel();

      final outcome = await job.run(() => 'done');

      expect(outcome, isA<JobCancelled<String>>());
      expect(ran, isEmpty);
      expect(job.progress, 0.0);
    });

    test('cancelling after every chunk already ran still finishes', () async {
      // A button pressed after a job's own last chunk landed asks for
      // something that has already happened; the outcome is what actually
      // ran, not what was asked for after the fact.
      final job = Job<int>(chunkCount: 3, runChunk: (int index) async {});

      final outcome = await job.run(() => 7);
      job.cancel();

      expect(outcome, isA<JobFinished<int>>());
      expect((outcome as JobFinished<int>).value, 7);
    });

    test('combine is never called on a cancelled job', () async {
      var combined = false;
      late final Job<int> job;
      job = Job<int>(
        chunkCount: 4,
        runChunk: (int index) async {
          if (index == 0) job.cancel();
        },
      );

      await job.run(() {
        combined = true;
        return 0;
      });

      expect(combined, isFalse);
    });

    test('a job of zero chunks is refused rather than silently finishing', () {
      expect(
        () => Job<int>(chunkCount: 0, runChunk: (int index) async {}),
        throwsA(isA<AssertionError>()),
        skip: !_assertionsEnabled(),
      );
    });
  });
}

bool _assertionsEnabled() {
  var enabled = false;
  assert(() {
    enabled = true;
    return true;
  }());
  return enabled;
}
