/// An engine's log: levels, listeners, and the hook a crash reporter hangs
/// on.
///
///     dart test test/log_test.dart
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

void main() {
  test('a record below the level reaches nobody', () {
    // Mutation: drop the `isLogged` check in `log`. The debug line then
    // reaches the listener of a log kept at warning.
    final log = EngineLog(level: LogLevel.warning);
    final seen = <LogRecord>[];
    log.listen(seen.add);
    log.debug('a cache missed');
    log.info('a level loaded');
    log.warning('a backend would not start', source: 'view');
    expect(seen.map((r) => r.level), <LogLevel>[LogLevel.warning]);
    expect(seen.single.source, 'view');
    expect(log.isLogged(LogLevel.error), isTrue);
    expect(log.isLogged(LogLevel.trace), isFalse);
  });

  test('the level can be lowered while the engine runs', () {
    final log = EngineLog();
    final seen = <String>[];
    log.listen((r) => seen.add(r.message));
    log.debug('before');
    log.level = LogLevel.trace;
    log.debug('after');
    expect(seen, <String>['after']);
  });

  test('levels are ordered by severity and named for the wire', () {
    // Mutation: give `warning` a severity below `info`; the order, and
    // with it every threshold, turns over.
    expect(
      LogLevel.values,
      orderedEquals(<LogLevel>[...LogLevel.values]..sort()),
    );
    expect(LogLevel.error.isAtLeast(LogLevel.warning), isTrue);
    expect(LogLevel.debug.isAtLeast(LogLevel.info), isFalse);
    expect(LogLevel.byName('warning'), LogLevel.warning);
    expect(LogLevel.byName('fatal'), isNull);
    expect(
      <String>[for (final l in LogLevel.values) l.name],
      <String>['trace', 'debug', 'info', 'warning', 'error'],
    );
  });

  test('a cancelled listener hears nothing more', () {
    final log = EngineLog();
    final seen = <String>[];
    final registration = log.listen((r) => seen.add(r.message));
    log.info('one');
    registration.cancel();
    log.info('two');
    expect(seen, <String>['one']);
  });

  test('a crash reaches the reporter with its record', () {
    // Mutation: keep the record in `reportCrash` and leave the reporters
    // out. The crash is then a line in a log nobody reads after the app
    // closes, and the reporter never hears it.
    final log = EngineLog(level: LogLevel.error);
    final crashes = <Object>[];
    final records = <LogRecord>[];
    log
      ..listen(records.add)
      ..onCrash((error, stack, record) {
        crashes.add(error);
        expect(record.stackTrace, same(stack));
      });
    final error = StateError('a frame callback threw');
    log.reportCrash(error, StackTrace.current, source: 'view');
    expect(crashes, <Object>[error]);
    expect(records.single.level, LogLevel.error);
    expect(records.single.error, same(error));
    expect(log.hasCrashReporter, isTrue);
  });

  test('records are numbered in order, and stamped only by a clock given', () {
    // Mutation: read a wall clock when none was given. The package is under
    // the simulation, which may read none, so the time stays null.
    final plain = EngineLog();
    final seen = <LogRecord>[];
    plain.listen(seen.add);
    plain
      ..info('a')
      ..info('b');
    expect(seen.map((r) => r.sequence), <int>[0, 1]);
    expect(seen.first.time, isNull);

    final at = DateTime.utc(2026, 10, 10, 12);
    final clocked = EngineLog(clock: () => at);
    expect(clocked.log(LogLevel.info, 'c')!.time, at);
  });
}
