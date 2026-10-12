/// The rollback party's report: a machine's line in, the page and its
/// verdict out.
///
///     dart test test/rollback_report_test.dart
@TestOn('vm')
library;

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:test/test.dart';

import '../tool/rollback_report.dart' as report;

Map<String, Object?> _machine(
  String name, {
  int dropped = 0,
  int p99Us = 1200,
  Map<String, String> digests = const <String, String>{'3600': 'efa1477a'},
  String endedBy = 'time',
}) => <String, Object?>{
  'kind': 'rollback-run',
  'version': 1,
  'machine': name,
  'device': 'Galaxy A55',
  'rttMs': <String, Object?>{'p50': 18.0, 'p99': 41.0},
  'inputDelay': 2,
  'maxRollbackFrames': 8,
  'digests': digests,
  'stats': RollbackStats(
    steps: 36000,
    rollbacks: 900,
    stepsRerun: 3100,
    settledOnGuess: 20,
    droppedCorrections: dropped,
    droppedEarly: 0,
    resimulationP50: const Duration(microseconds: 400),
    resimulationP99: Duration(microseconds: p99Us),
    resimulationMax: const Duration(microseconds: 9000),
  ).toJson(),
  'endedBy': endedBy,
};

void main() {
  const p4 = (dropped: 0.5, p99: 8.0);

  test('eight machines inside the thresholds pass', () {
    final page = report.render([
      for (var i = 0; i < 8; i++) _machine('a55-$i', dropped: 100),
    ], thresholds: p4);
    expect(page.failures, isEmpty);
    expect(page.markdown, contains('Every digest at step 3600 is `efa1477a`'));
    expect(page.markdown, contains('**Passed.**'));
  });

  test('each threshold fails by the machine that crossed it', () {
    final page = report.render([
      _machine('a55-0', dropped: 181),
      _machine('a55-1', p99Us: 8001),
      _machine('a55-2', digests: const <String, String>{'3600': '00000000'}),
      _machine('a55-3', endedBy: 'dropped'),
    ], thresholds: p4);
    expect(page.failures, hasLength(4));
    expect(page.failures[0], startsWith('a55-0: dropped corrections'));
    expect(page.failures[1], startsWith('a55-1: p99 resimulation'));
    expect(page.failures[2], 'a55-3: session ended by dropped');
    expect(page.failures[3], 'the digests at step 3600 differ');
  });

  test('the digests are compared at the last step all machines reached', () {
    final last = report.lastCommonDigest([
      _machine('a', digests: const {'100': 'aa', '200': 'bb', '300': 'cc'}),
      _machine('b', digests: const {'100': 'aa', '200': 'bb'}),
    ]);
    expect(last?.step, 200);
    expect(last?.agree, isTrue);
  });

  test('--fail-on reads P4 and refuses another key', () {
    expect(report.parseFailOn('dropped=0.5,p99=8'), (dropped: 0.5, p99: 8.0));
    expect(() => report.parseFailOn('p50=8'), throwsFormatException);
  });
}
