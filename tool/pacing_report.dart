/// The two ends of `tool/pacing.sh` that want Dart rather than shell — `N3`.
///
///     dart run tool/pacing_report.dart defines <run.f3drun> <out.json> <repeats> <budget>
///     dart run tool/pacing_report.dart check-fail-on <fail-on>
///     dart run tool/pacing_report.dart report <pacing.json> <report.md> <label> <commit> <load> [<fail-on>]
///
/// `defines` writes the `--dart-define-from-file` the device run reads its
/// tape from: the file's contents as one string, which the shell cannot
/// quote into JSON on its own. `report` turns what the run sent back into
/// the Markdown kept in `doc/pacing/`, and exits 1 when any frame was longer
/// than the limit, so the script — and CI — fails on a spike.
///
/// **With a `<fail-on>` line the run is held to it instead.** A phone is
/// held to the thresholds of the release proof (`p99=33.3` nightly, the
/// whole `p50=16.7,p99=33.3,over50=0.1,max=100` by hand), not to "no frame
/// over 50 ms", which a mid-range phone misses by a frame or two on every
/// run and which would therefore say nothing night after night.
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  switch (args) {
    case ['defines', final run, final out, final repeats, final budget]:
      _defines(run, out, repeats, budget);
    // What `pacing.sh` asks before it builds anything.
    case ['check-fail-on', final line]:
      try {
        parseFailOn(line);
      } on FormatException catch (error) {
        stderr.writeln(error.message);
        exitCode = 2;
      }
    case [
          'report',
          final data,
          final report,
          final label,
          final commit,
          final load,
          ...final rest,
        ]
        when rest.length <= 1:
      final Map<String, double>? failOn;
      try {
        failOn = rest.isEmpty ? null : parseFailOn(rest.single);
      } on FormatException catch (error) {
        stderr.writeln(error.message);
        exitCode = 2;
        return;
      }
      exitCode = _report(data, report, label, commit, load, failOn);
    default:
      stderr.writeln(
        'usage: pacing_report.dart defines <run> <out> <repeats> <budget>\n'
        '       pacing_report.dart check-fail-on <fail-on>\n'
        '       pacing_report.dart report <data> <report> <label> <commit> '
        '<load> [<fail-on>]',
      );
      exitCode = 2;
  }
}

/// What each `--fail-on` key reads, and the unit its value is in.
const Map<String, String> failOnKeys = <String, String>{
  'p50': 'ms',
  'p99': 'ms',
  'max': 'ms',
  'over50': '% of frames over the limit',
};

/// Reads `p99=33.3` or `p50=16.7,p99=33.3,over50=0.1,max=100`.
///
/// A key it does not know is a [FormatException] rather than a key it
/// skips: a nightly told `p95=20` would otherwise check nothing and say so in
/// green.
Map<String, double> parseFailOn(String line) {
  final parts = line.split(',').map((part) => part.trim()).toList();
  if (parts.every((part) => part.isEmpty)) {
    throw const FormatException('--fail-on names no threshold');
  }
  return <String, double>{
    for (final part in parts)
      ...switch (part.split('=')) {
        [final key, final value]
            when failOnKeys.containsKey(key) &&
                double.tryParse(value) != null =>
          <String, double>{key: double.parse(value)},
        [final key, _] when !failOnKeys.containsKey(key) =>
          throw FormatException(
            '--fail-on: "$key" is not a threshold; '
            'the known ones are ${failOnKeys.keys.join(', ')}',
          ),
        _ => throw FormatException('--fail-on: "$part" is not key=number'),
      },
  };
}

/// One sentence per threshold the run broke, empty when it held every one.
///
/// [pacing] is `ReplayPacing.toJson`. A value on the line passes: the
/// release proof writes its thresholds as "≤".
List<String> thresholdFailures(
  Map<String, Object?> pacing,
  Map<String, double> failOn,
) {
  String ms(num value) => '${value.toStringAsFixed(2)} ms';
  final frames = pacing['frames']! as int;
  final over = (pacing['overLimit']! as List).length;
  final limit = (pacing['limitMillis']! as num).round();
  // The tolerance is for the division: one frame in a thousand is 0.1 %, and
  // it is on the line, not a rounding error over it.
  final share = frames == 0 ? 0.0 : over * 100 / frames;
  String overShare(double line) =>
      'over$limit ${share.toStringAsFixed(2)} % ($over of $frames frames) '
      'is over the line of ${line.toStringAsFixed(2)} %';
  return <String>[
    for (final MapEntry(:key, value: line) in failOn.entries)
      if (key == 'over50') ...[
        if (share > line + 1e-9) overShare(line),
      ] else if ((pacing[key]! as num) > line)
        '$key ${ms(pacing[key]! as num)} is over the line of ${ms(line)}',
  ];
}

void _defines(String run, String out, String repeats, String budget) {
  final contents = File(run).readAsStringSync();
  // Parsed here so a file that is not a run fails before a build, not after.
  jsonDecode(contents);
  File(out).writeAsStringSync(
    jsonEncode(<String, String>{
      'FLUTTER3D_PACING_RUN': contents,
      'FLUTTER3D_PACING_RUN_NAME': run.split('/').last,
      'FLUTTER3D_PACING_REPEATS': repeats,
      'FLUTTER3D_PACING_BUDGET': budget,
    }),
  );
}

int _report(
  String dataPath,
  String reportPath,
  String label,
  String commit,
  String load,
  Map<String, double>? failOn,
) {
  final data = jsonDecode(File(dataPath).readAsStringSync()) as Map;
  final pacing = data['pacing'] as Map;
  final about = data['about'] as Map;
  final spikes = (pacing['overLimit'] as List).cast<int>();
  final limit = pacing['limitMillis'] as num;
  final steps = about['steps'] as int;
  String at(int frame) =>
      'pass ${frame ~/ steps + 1}, step ${frame % steps + 1}';
  String ms(Object? value) => (value! as num).toStringAsFixed(2);
  final date = DateTime.now().toUtc().toIso8601String().substring(0, 10);

  final report = StringBuffer()
    ..writeln('# Frame pacing: $label')
    ..writeln()
    ..writeln(
      'Written by `tool/pacing.sh` on $date at `$commit`. '
      '`${about['run']}` played through the renderer a step a frame, '
      '${about['repeats']} times, each frame timed from the step to the GPU '
      'finishing its draw (see `replayPacing` in `flutter3d_testing`). '
      'A frame over ${ms(limit)} ms is a spike, and '
      '${failOn == null ? 'any spike fails the run.' : 'the run is held to `${_failOnLine(failOn)}`.'}',
    )
    ..writeln()
    ..writeln('| frames | p50 | p99 | worst | over ${limit.round()} ms |')
    ..writeln('| ---: | ---: | ---: | ---: | ---: |')
    ..writeln(
      '| ${pacing['frames']} | ${ms(pacing['p50'])} ms '
      '| ${ms(pacing['p99'])} ms | ${ms(pacing['max'])} ms '
      '(${at(pacing['worstFrame'] as int)}) | ${spikes.length} |',
    )
    ..writeln()
    ..writeln('- device: ${about['device']}, ${about['os']}')
    ..writeln('- build: ${about['mode']}')
    // A frame time is the machine's as much as the engine's: a run on a
    // host already busy with other work spikes for reasons of its own.
    ..writeln('- host load average when the run began: $load')
    ..writeln('- frame: ${about['width']} x ${about['height']}')
    ..writeln(
      '- `RenderSettings.frameWorkBudget`: '
      '${about['frameWorkBudget'] == 0 ? 'none' : '${about['frameWorkBudget']} us'}',
    );
  if (spikes.isNotEmpty) {
    report
      ..writeln()
      ..writeln('Spikes:')
      ..writeln();
    final millis = (pacing['millis'] as List).cast<num>();
    for (final frame in spikes) {
      report.writeln('- ${at(frame)}: ${ms(millis[frame])} ms');
    }
  }
  final broken = failOn == null
      ? null
      : thresholdFailures(pacing.cast<String, Object?>(), failOn);
  if (broken != null) {
    report
      ..writeln()
      ..writeln(
        broken.isEmpty
            ? 'Held every threshold of `${_failOnLine(failOn!)}`.'
            : 'Broke:',
      );
    if (broken.isNotEmpty) report.writeln();
    for (final line in broken) {
      report.writeln('- $line');
    }
  }
  File(reportPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(report.toString());
  stdout.write(report);
  return switch (broken) {
    null => spikes.isEmpty ? 0 : 1,
    final broken => broken.isEmpty ? 0 : 1,
  };
}

String _failOnLine(Map<String, double> failOn) => [
  for (final MapEntry(:key, :value) in failOn.entries) '$key=$value',
].join(',');
