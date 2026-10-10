/// The loop's clock: real, scaled, a log's, or moved by hand.
///
///     dart test test/time_source_test.dart
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

const Duration _period = Duration(microseconds: 16667);

void main() {
  test('real time is the gap between the vsyncs', () {
    const time = TimeSource.realTime();
    expect(time.elapsed(Duration.zero, _period * 2), closeTo(0.033334, 1e-9));
  });

  test('scaled time is real time times the factor', () {
    expect(
      TimeSource.scaled(0.5).elapsed(Duration.zero, _period * 2),
      closeTo(0.016667, 1e-9),
    );
    expect(() => TimeSource.scaled(-1.0), throwsArgumentError);
  });

  test("a log's time walks its timestamps, one gap a frame", () {
    final log = TimeSource.log(<double>[10.0, 10.5, 12.0]) as LogTime;
    // Mutation: hand the wall clock's gap instead of the log's.
    expect(log.elapsed(Duration.zero, _period), 0.5);
    expect(log.elapsed(_period, _period * 2), 1.5);
    expect(log.isFinished, isTrue);
    expect(log.elapsed(_period * 2, _period * 3), 0.0);
    log.reset();
    expect(log.elapsed(Duration.zero, _period), 0.5);
    expect(() => TimeSource.log(<double>[1.0, 0.5]), throwsArgumentError);
  });

  test('manual time brings what was queued, once', () {
    final manual = TimeSource.manual() as ManualTime;
    expect(manual.elapsed(Duration.zero, _period), 0.0);
    manual
      ..advance(0.25)
      ..advance(0.25);
    expect(manual.elapsed(_period, _period * 2), 0.5);
    expect(manual.elapsed(_period * 2, _period * 3), 0.0);
    expect(() => manual.advance(-0.1), throwsArgumentError);
  });

  test("the loop steps by its clock's time, not the wall's", () {
    // Mutation: have `frameAtVsync` hand `frame` the vsync gap without
    // asking `time` — the loop steps sixty times a second whatever the
    // laboratory said.
    final manual = ManualTime();
    final loop = EngineLoop(input: InputState())..time = manual;
    expect(loop.frameAtVsync(Duration.zero), 0);
    expect(loop.frameAtVsync(_period * 60), 0, reason: 'nothing queued');
    manual.advance(loop.stepSeconds * 3);
    expect(loop.frameAtVsync(_period * 61), 3);
  });

  test('a cadence draws by refreshes and brings its clock\'s time', () {
    final cadence = FrameCadence(
      cap: 60.0,
      refreshRate: 120.0,
      time: TimeSource.scaled(0.1),
    );
    const refresh = Duration(microseconds: 8333);
    expect(cadence.due(Duration.zero), 0.0);
    expect(cadence.due(refresh), isNull);
    expect(cadence.due(refresh * 2), closeTo(0.0016666, 1e-9));
  });
}
