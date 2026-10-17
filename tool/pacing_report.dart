/// The two ends of `tool/pacing.sh` that want Dart rather than shell — `N3`.
///
///     dart run tool/pacing_report.dart defines <run.f3drun> <out.json> <repeats> <budget> [<seconds> <warm-up>]
///     dart run tool/pacing_report.dart check-fail-on <fail-on>
///     dart run tool/pacing_report.dart rss <pacing.json> <samples.txt> <source>
///     dart run tool/pacing_report.dart report <pacing.json> <report.md> <label> <commit> <load> [<fail-on>]
///
/// `defines` writes the `--dart-define-from-file` the device run reads its
/// tape from: the file's contents as one string, which the shell cannot
/// quote into JSON on its own, and the same gzipped in base64. With
/// `<seconds>` above nought, the timed passes are as many whole passes of
/// the tape as cover that many seconds of play rather than `<repeats>`;
/// `<warm-up>` seconds become passes played before them and not counted.
/// `rss` puts the resident memory the script sampled during the run into
/// what the run reported. `report` turns all of it into the Markdown kept in
/// `doc/pacing/`, and exits 1 when any frame was longer than the limit, so
/// the script — and CI — fails on a spike.
///
/// **With a `<fail-on>` line the run is held to it instead.** A phone is
/// held to the thresholds of the release proof (`p99=33.3` nightly, the
/// whole `p50=16.7,p99=33.3,over50=0.1,max=100,rssGrowth=1.10,rssEnd=400`
/// by hand), not to "no frame over 50 ms", which a mid-range phone misses by
/// a frame or two on every run and which would therefore say nothing night
/// after night.
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  switch (args) {
    case ['defines', final run, final out, final repeats, final budget]:
      exitCode = _defines(run, out, repeats, budget, '0', '0');
    case [
      'defines',
      final run,
      final out,
      final repeats,
      final budget,
      final seconds,
      final warmUp,
    ]:
      exitCode = _defines(run, out, repeats, budget, seconds, warmUp);
    // What `pacing.sh` asks before it builds anything.
    case ['check-fail-on', final line]:
      try {
        parseFailOn(line);
      } on FormatException catch (error) {
        stderr.writeln(error.message);
        exitCode = 2;
      }
    case ['rss', final data, final samples, final source]:
      _addRss(data, samples, source);
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
        'usage: pacing_report.dart defines <run> <out> <repeats> <budget> '
        '[<seconds> <warm-up>]\n'
        '       pacing_report.dart check-fail-on <fail-on>\n'
        '       pacing_report.dart rss <data> <samples> <source>\n'
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
  'rssGrowth': 'times the resident memory 30 s into the run, at its end',
  'rssEnd': 'MB of resident memory at the end of the run',
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

/// The resident memory of one run, in MB (1024 kB), as P1 reads it.
final class RssSummary {
  const RssSummary({
    required this.at30,
    required this.end,
    required this.peak,
    required this.seconds,
    required this.samples,
  });

  /// The first sample 30 s or more after the application was first seen;
  /// null for a run that ended before then.
  final double? at30;

  /// The last sample.
  final double end;

  /// The largest sample.
  final double peak;

  /// How long after the first sample the last one was taken, in seconds.
  final double seconds;

  /// How many samples there were.
  final int samples;

  /// [end] over [at30]; null without an [at30].
  double? get growth => switch (at30) {
    final double at30 when at30 > 0 => end / at30,
    _ => null,
  };
}

/// [samples] as `pacing.sh` writes them, `[seconds, kB]` in the order they
/// were taken, summed up; null when there are none.
RssSummary? rssSummary(List<List<num>> samples) {
  if (samples.isEmpty) return null;
  double mb(num kb) => kb / 1024;
  final at30 = samples.where((sample) => sample[0] >= 30).firstOrNull;
  return RssSummary(
    at30: at30 == null ? null : mb(at30[1]),
    end: mb(samples.last[1]),
    peak: mb(
      samples.map((sample) => sample[1]).reduce((a, b) => a > b ? a : b),
    ),
    seconds: (samples.last[0] - samples.first[0]).toDouble(),
    samples: samples.length,
  );
}

/// Whole passes of a tape [steps] long that cover [seconds] of play, a step
/// being a sixtieth of a second.
int passesFor(double seconds, {required int steps}) =>
    (seconds * 60 / steps).ceil();

/// One sentence per threshold the run broke, empty when it held every one.
///
/// [pacing] is `ReplayPacing.toJson`; [rss] is what was sampled of the
/// application's memory, null when nothing was. A value on the line passes:
/// the release proof writes its thresholds as "≤". A memory line with no
/// memory to read is broken, not held.
List<String> thresholdFailures(
  Map<String, Object?> pacing,
  Map<String, double> failOn, {
  RssSummary? rss,
}) {
  String ms(num value) => '${value.toStringAsFixed(2)} ms';
  final frames = pacing['frames']! as int;
  final over = (pacing['overLimit']! as List).length;
  final limit = (pacing['limitMillis']! as num).round();
  // The tolerance is for the division: one frame in a thousand is 0.1 %, and
  // it is on the line, not a rounding error over it.
  final share = frames == 0 ? 0.0 : over * 100 / frames;
  String? broken(String key, double line) => switch (key) {
    'over50' when share > line + 1e-9 =>
      'over$limit ${share.toStringAsFixed(2)} % ($over of $frames frames) '
          'is over the line of ${line.toStringAsFixed(2)} %',
    'over50' => null,
    'rssGrowth' || 'rssEnd' when rss == null =>
      '$key: no resident memory was measured on this device',
    'rssGrowth' => switch (rss!.growth) {
      null =>
        'rssGrowth: the run ended ${rss.seconds.round()} s in, before the '
            '30 s it grows from',
      final growth when growth > line + 1e-9 =>
        'rssGrowth ${growth.toStringAsFixed(3)} '
            '(${rss.end.toStringAsFixed(1)} MB at the end, '
            '${rss.at30!.toStringAsFixed(1)} MB at 30 s) is over the line of '
            '${line.toStringAsFixed(2)}',
      _ => null,
    },
    'rssEnd' when rss!.end > line =>
      'rssEnd ${rss.end.toStringAsFixed(1)} MB is over the line of '
          '${line.toStringAsFixed(1)} MB',
    'rssEnd' => null,
    _ when (pacing[key]! as num) > line =>
      '$key ${ms(pacing[key]! as num)} is over the line of ${ms(line)}',
    _ => null,
  };
  return <String>[
    for (final MapEntry(:key, value: line) in failOn.entries)
      ?broken(key, line),
  ];
}

/// The longest run, in characters, also handed over uncompressed.
const int _plainLimit = 64 * 1024;

int _defines(
  String run,
  String out,
  String repeats,
  String budget,
  String seconds,
  String warmUp,
) {
  final contents = File(run).readAsStringSync();
  // Parsed here so a file that is not a run fails before a build, not after.
  final steps = switch (jsonDecode(contents)) {
    {'tape': {'frames': final List<Object?> frames}} => frames.length,
    _ => 0,
  };
  if (steps == 0) {
    stderr.writeln('$run has no tape to play');
    return 2;
  }
  final timed = double.parse(seconds) > 0
      ? passesFor(double.parse(seconds), steps: steps)
      : int.parse(repeats);
  final warm = passesFor(double.parse(warmUp), steps: steps);
  stdout.writeln(
    '${run.split('/').last}: $steps steps a pass, '
    '$warm warm-up passes, $timed timed',
  );
  File(out).writeAsStringSync(
    jsonEncode(<String, String>{
      // **Compressed as well, and only compressed past 64 KiB.** A define
      // reaches the build as one environment variable, and a run that saves
      // a level's water (the platformer's is 600 KB) is past what macOS lets
      // a process be handed; as gzip it is 21 KB. Plain too while it fits,
      // for a harness that reads only the plain one.
      if (contents.length <= _plainLimit) 'FLUTTER3D_PACING_RUN': contents,
      'FLUTTER3D_PACING_RUN_GZIP': base64.encode(
        gzip.encode(utf8.encode(contents)),
      ),
      'FLUTTER3D_PACING_RUN_NAME': run.split('/').last,
      'FLUTTER3D_PACING_REPEATS': '$timed',
      'FLUTTER3D_PACING_WARMUP': '$warm',
      'FLUTTER3D_PACING_BUDGET': budget,
    }),
  );
  return 0;
}

/// Adds the samples in [samplesPath], one `<seconds> <kB>` a line, to the
/// run's report in [dataPath] under `rss`, with where they were read from.
void _addRss(String dataPath, String samplesPath, String source) {
  final file = File(dataPath);
  final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final samples = File(samplesPath).existsSync()
      ? <List<num>>[
          for (final line in File(samplesPath).readAsLinesSync())
            if (line.trim().split(RegExp(r'\s+')) case [
              final t,
              final kb,
            ] when num.tryParse(t) != null && num.tryParse(kb) != null)
              <num>[num.parse(t), num.parse(kb)],
        ]
      : const <List<num>>[];
  file.writeAsStringSync(
    jsonEncode(<String, Object?>{
      ...data,
      'rss': <String, Object?>{'source': source, 'samples': samples},
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
  final (rss, rssSource) = switch (data['rss']) {
    {'source': final String source, 'samples': final List<Object?> samples} => (
      rssSummary(<List<num>>[
        for (final sample in samples) (sample! as List).cast<num>(),
      ]),
      source,
    ),
    _ => (null, null),
  };

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
    ..writeln(
      '- warm-up: ${about['warmUpPasses'] ?? 0} passes played before the '
      'timed ones and not counted',
    )
    ..writeln('- frame: ${about['width']} x ${about['height']}')
    ..writeln(
      '- `RenderSettings.frameWorkBudget`: '
      '${about['frameWorkBudget'] == 0 ? 'none' : '${about['frameWorkBudget']} us'}',
    )
    ..writeln(switch (rss) {
      null => '- resident memory: not measured on this device',
      final rss =>
        '- resident memory (`$rssSource`, ${rss.samples} samples over '
            '${rss.seconds.round()} s): '
            '${rss.at30 == null ? 'no sample at 30 s' : '${rss.at30!.toStringAsFixed(1)} MB at 30 s'}, '
            '${rss.end.toStringAsFixed(1)} MB at the end'
            '${rss.growth == null ? '' : ' (${rss.growth!.toStringAsFixed(3)} times)'}'
            ', peak ${rss.peak.toStringAsFixed(1)} MB',
    });
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
      : thresholdFailures(pacing.cast<String, Object?>(), failOn, rss: rss);
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
