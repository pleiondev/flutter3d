/// The report of a rollback party: one JSON line per machine in, one
/// Markdown page out, and an exit code that holds it to the thresholds.
///
///     dart run tool/rollback_report.dart machine-*.json --out report.md \
///       --fail-on dropped=0.5,p99=8
///
/// Each machine writes its own line at the end of the run (the loopback
/// harness, `tool/rollback_party.dart`, writes all of them; on a phone the
/// game writes `RollbackSession.stats.toJson()` into the same shape):
///
/// ```json
/// {
///   "kind": "rollback-run", "version": 1,
///   "machine": "a55-3", "device": "Galaxy A55", "slot": 3, "players": 8,
///   "stepHz": 60, "inputDelay": 2, "maxRollbackFrames": 8,
///   "rttMs": {"p50": 18.0, "p99": 41.0},
///   "lastStep": 36000, "digestEvery": 100,
///   "digests": {"35900": "1a2b3c4d", "36000": "5e6f7a8b"},
///   "stats": { …RollbackStats.toJson()… },
///   "endedBy": "time"
/// }
/// ```
///
/// `rttMs` is what the machine measured, not what anyone assumed; `endedBy`
/// is `time` for a session that ran its length and anything else (`dropped`,
/// `crashed`) for one that did not.
///
/// The thresholds are P4's: every machine's `droppedCorrections` at most
/// `dropped` per cent of its steps, its 99th percentile of the time of a step
/// run again at most `p99` milliseconds, every machine's digest at the last
/// step all of them reached the same, and no session ended by anything but
/// time. The last two always hold; `--fail-on` sets the first two.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_net/flutter3d_net.dart';

/// The thresholds `--fail-on` names: `dropped` in per cent of steps, `p99`
/// in milliseconds.
typedef Thresholds = ({double? dropped, double? p99});

/// Reads `dropped=0.5,p99=8`; throws a [FormatException] on another key.
Thresholds parseFailOn(String text) {
  double? dropped;
  double? p99;
  for (final part in text.split(',').where((p) => p.trim().isNotEmpty)) {
    final [key, value] = switch (part.split('=')) {
      [final k, final v] => [k.trim(), v.trim()],
      _ => throw FormatException('expected key=value, got "$part"'),
    };
    final number = double.tryParse(value);
    if (number == null) throw FormatException('"$value" is not a number');
    switch (key) {
      case 'dropped':
        dropped = number;
      case 'p99':
        p99 = number;
      default:
        throw FormatException('no threshold "$key": dropped or p99');
    }
  }
  return (dropped: dropped, p99: p99);
}

/// The last step every machine has a digest for, and whether they agree on
/// it; null when they share none.
({int step, bool agree, Map<String, String> digests})? lastCommonDigest(
  List<Map<String, Object?>> machines,
) {
  Map<int, String> digestsOf(Map<String, Object?> m) => <int, String>{
    for (final MapEntry(:key, :value)
        in ((m['digests'] as Map?) ?? const <String, Object?>{}).entries)
      int.parse('$key'): '$value',
  };
  final all = [for (final m in machines) digestsOf(m)];
  if (all.isEmpty) return null;
  final common = all
      .map((d) => d.keys.toSet())
      .reduce((a, b) => a.intersection(b));
  if (common.isEmpty) return null;
  final step = common.reduce((a, b) => a > b ? a : b);
  final digests = <String, String>{
    for (var i = 0; i < machines.length; i++)
      '${machines[i]['machine'] ?? i}': all[i][step]!,
  };
  return (
    step: step,
    agree: digests.values.toSet().length == 1,
    digests: digests,
  );
}

/// The page, and the thresholds it failed (empty when it passed).
({String markdown, List<String> failures}) render(
  List<Map<String, Object?>> machines, {
  Thresholds thresholds = (dropped: null, p99: null),
  String title = 'Rollback party',
  String? commit,
  String? note,
}) {
  final failures = <String>[];
  final rows = <String>[];
  for (final m in machines) {
    final stats = RollbackStats.fromJson(
      ((m['stats'] as Map?) ?? const <String, Object?>{})
          .cast<String, Object?>(),
    );
    final name = '${m['machine'] ?? m['slot']}';
    final share = stats.droppedCorrectionShare * 100;
    final p99 = stats.resimulationP99.inMicroseconds / 1000;
    final rtt = (m['rttMs'] as Map?)?.cast<String, Object?>();
    final ended = '${m['endedBy'] ?? 'unknown'}';
    if (thresholds.dropped case final limit? when share > limit) {
      failures.add('$name: dropped corrections ${_f(share, 3)} % > $limit %');
    }
    if (thresholds.p99 case final limit? when p99 > limit) {
      failures.add('$name: p99 resimulation ${_f(p99, 2)} ms > $limit ms');
    }
    if (ended != 'time') failures.add('$name: session ended by $ended');
    rows.add(
      '| $name | ${m['device'] ?? '?'} | ${rtt?['p50'] ?? '?'} / '
      '${rtt?['p99'] ?? '?'} | ${stats.steps} | ${stats.rollbacks} | '
      '${stats.stepsRerun} | ${stats.settledOnGuess} | '
      '${stats.droppedCorrections} (${_f(share, 3)} %) | '
      '${_f(stats.resimulationP50.inMicroseconds / 1000, 3)} | '
      '${_f(p99, 3)} | '
      '${_f(stats.resimulationMax.inMicroseconds / 1000, 3)} | $ended |',
    );
  }
  final last = lastCommonDigest(machines);
  if (last == null) {
    failures.add('no step every machine has a digest for');
  } else if (!last.agree) {
    failures.add('the digests at step ${last.step} differ');
  }
  final first = machines.isEmpty ? const <String, Object?>{} : machines.first;
  final out = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln(
      '${machines.length} machines, ${first['stepHz'] ?? 60} Hz, '
      '`inputDelay ${first['inputDelay'] ?? '?'}`, '
      '`maxRollbackFrames ${first['maxRollbackFrames'] ?? '?'}`'
      '${commit == null ? '' : ', commit `$commit`'}.',
    );
  if (note != null) {
    out
      ..writeln()
      ..writeln(note);
  }
  out
    ..writeln()
    ..writeln(
      '| Machine | Device | RTT p50 / p99 (ms) | Steps | Rollbacks | '
      'Steps run again | Settled on a guess | Dropped corrections | '
      'Resim p50 (ms) | Resim p99 (ms) | Resim max (ms) | Ended by |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|---|---|---|---|');
  rows.forEach(out.writeln);
  out
    ..writeln()
    ..writeln(switch (last) {
      null => 'No step every machine has a digest for.',
      (:final step, agree: true, :final digests) =>
        'Every digest at step $step is `${digests.values.first}`.',
      (:final step, agree: false, :final digests) =>
        'The digests at step $step differ: '
            '${digests.entries.map((e) => '${e.key} `${e.value}`').join(', ')}.',
    })
    ..writeln()
    ..writeln(
      'Thresholds: dropped corrections ≤ '
      '${thresholds.dropped ?? '—'} % of steps, p99 resimulation ≤ '
      '${thresholds.p99 ?? '—'} ms, one digest at the last common step, no '
      'session ended by anything but time.',
    )
    ..writeln()
    ..writeln(
      failures.isEmpty ? '**Passed.**' : '**Failed:** ${failures.join('; ')}.',
    );
  return (markdown: out.toString(), failures: failures);
}

String _f(double value, int digits) => value.toStringAsFixed(digits);

Future<void> main(List<String> args) async {
  final files = <String>[];
  String? out;
  String? failOn;
  String? title;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--out':
        out = args[++i];
      case '--fail-on':
        failOn = args[++i];
      case '--title':
        title = args[++i];
      case final file:
        files.add(file);
    }
  }
  if (files.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/rollback_report.dart <machine.json>... '
      '[--out report.md] [--fail-on dropped=0.5,p99=8] [--title text]',
    );
    exit(2);
  }
  final Thresholds thresholds;
  try {
    thresholds = failOn == null
        ? (dropped: null, p99: null)
        : parseFailOn(failOn);
  } on FormatException catch (e) {
    stderr.writeln('--fail-on: ${e.message}');
    exit(2);
  }
  final machines = [
    for (final f in files)
      (jsonDecode(File(f).readAsStringSync()) as Map).cast<String, Object?>(),
  ];
  final report = render(
    machines,
    thresholds: thresholds,
    title: title ?? 'Rollback party',
  );
  if (out == null) {
    stdout.write(report.markdown);
  } else {
    File(out).writeAsStringSync(report.markdown);
    stdout.writeln('wrote $out');
  }
  for (final failure in report.failures) {
    stderr.writeln('FAIL $failure');
  }
  exit(report.failures.isEmpty ? 0 : 1);
}
