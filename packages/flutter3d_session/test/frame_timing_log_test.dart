/// What a window of frames says about itself.
///
///     flutter test test/frame_timing_log_test.dart
///
/// The binding half registers nothing in a test build — `enabled` is a
/// compile-time constant — so what is held here is the arithmetic: a window
/// reports once, when it is full, with the mean and the worst of each half,
/// and starts again from nothing.
library;

import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter_test/flutter_test.dart';

Duration _ms(double milliseconds) =>
    Duration(microseconds: (milliseconds * 1000).round());

void main() {
  test('a window reports once, when it is full', () {
    final log = FrameTimingLog(label: 'race', window: 3);

    expect(log.note(build: _ms(2.0), raster: _ms(4.0)), isNull);
    expect(log.note(build: _ms(4.0), raster: _ms(8.0)), isNull);
    final line = log.note(build: _ms(3.0), raster: _ms(6.0));

    expect(line, isNotNull);
    expect(line, startsWith('race: over 3 frames'));
    expect(line, contains('build 3.00 ms mean / 4.00 worst'));
    expect(line, contains('raster 6.00 ms mean / 8.00 worst'));
  });

  test('and the next window starts from nothing', () {
    // Mutation: forget to reset the worst — one slow frame at launch is
    // reported as the worst of every window for the rest of the session.
    final log = FrameTimingLog(window: 2);
    log.note(build: _ms(30.0), raster: _ms(30.0));
    log.note(build: _ms(30.0), raster: _ms(30.0));

    log.note(build: _ms(1.0), raster: _ms(1.0));
    final line = log.note(build: _ms(1.0), raster: _ms(1.0));

    expect(line, contains('build 1.00 ms mean / 1.00 worst'));
    expect(line, contains('raster 1.00 ms mean / 1.00 worst'));
  });

  test('is off in a build that did not ask', () {
    // The flag is the whole cost model: a shipped game must register no
    // callback. Held at the constant, since that is what gates `start`.
    expect(FrameTimingLog.enabled, isFalse);
    // And starting is then safe with no binding at all.
    FrameTimingLog()
      ..start()
      ..stop();
  });
}
