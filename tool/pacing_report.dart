/// The two ends of `tool/pacing.sh` that want Dart rather than shell — `N3`.
///
///     dart run tool/pacing_report.dart defines <run.f3drun> <out.json> <repeats> <budget> [<seconds> <warm-up>]
///     dart run tool/pacing_report.dart report <pacing.json> <report.md> <label> <commit> <load>
///
/// `defines` writes the `--dart-define-from-file` the device run reads its
/// tape from: the file's contents as one string, which the shell cannot
/// quote into JSON on its own, and the same gzipped in base64. With [seconds] above nought, the timed passes
/// are as many as cover that many seconds of play rather than [repeats];
/// [warm-up] seconds become passes played before them and not counted.
/// `report` turns what the run sent back into
/// the Markdown kept in `doc/pacing/`, and exits 1 when any frame was longer
/// than the limit, so the script — and CI — fails on a spike.
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
    case [
      'report',
      final data,
      final report,
      final label,
      final commit,
      final load,
    ]:
      exitCode = _report(data, report, label, commit, load);
    default:
      stderr.writeln(
        'usage: pacing_report.dart defines <run> <out> <repeats> <budget> '
        '[<seconds> <warm-up>]\n'
        '       pacing_report.dart report <data> <report> <label> <commit> <load>',
      );
      exitCode = 2;
  }
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
  // A step is a sixtieth of a second, so a pass is `steps / 60` seconds and
  // a window is the whole passes that cover it.
  int passes(String seconds) => (double.parse(seconds) * 60 / steps).ceil();
  final timed = double.parse(seconds) > 0
      ? passes(seconds)
      : int.parse(repeats);
  final warm = passes(warmUp);
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

int _report(
  String dataPath,
  String reportPath,
  String label,
  String commit,
  String load,
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
      'A frame over ${ms(limit)} ms is a spike, and any spike fails the run.',
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
  File(reportPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(report.toString());
  stdout.write(report);
  return spikes.isEmpty ? 0 : 1;
}
