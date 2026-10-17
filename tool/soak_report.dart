/// The Dart ends of `tool/soak.sh` — P2.
///
///     dart run tool/soak_report.dart check-fail-on <fail-on>
///     dart run tool/soak_report.dart define <defines.json> <key> <value>
///     dart run tool/soak_report.dart gc <vm-service-uri> <gc.txt>
///     dart run tool/soak_report.dart report <pacing.json> <rss.txt> <gc.txt>
///       <crash.txt> <out-dir> <label> <placement> <commit> <load> [<fail-on>]
///
/// `define` adds one define to the file `pacing_report.dart defines` wrote.
/// `gc` listens to the application's VM service for its garbage
/// collections until the application goes, one line a collection
/// (`<seconds> <isolate> <space> <ms>`, below). `report` writes
/// `<out-dir>/soak-<label>-<placement>.md` and the resident-memory graph
/// beside it, `soak-<label>-<placement>-rss.svg`, and exits 1 when the run
/// broke a threshold, crashed or did not report.
///
/// ## The thresholds
///
/// P2's, by default `rssGrowth=1.15,max=250,gc50=1`:
///
/// - `rssGrowth`: the resident memory at the end over the value ten minutes
///   in. A run shorter than two hours compares with one twelfth of the way
///   in, so the three-minute rehearsal reads 15 s; the report says which.
/// - `max`: the longest frame, in milliseconds.
/// - `gc50`: garbage collections that paused over 50 ms, at most this many
///   in any one minute of the run. Where the VM service could not be
///   reached the report says the pauses were not measured, and the line
///   fails rather than passing on nothing.
///
/// A crash or an ANR, from `adb logcat` on Android and from the system's
/// crash reports on macOS (`soak.sh` gathers them into `<crash.txt>`, one
/// line each), fails the run whatever the thresholds.
///
/// ## The pauses
///
/// The VM service's `GC` stream sends an event after each collection with
/// each heap space's collection count and its cumulative time in
/// collections. A pause is the time a space gained over the collections it
/// gained since its last event: the VM's own accounting, the same numbers
/// DevTools shows. An old-space collection that marked concurrently counts
/// its marking too, so the figure errs long, never short.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// What each `--fail-on` key reads.
const Map<String, String> failOnKeys = <String, String>{
  'rssGrowth': 'times the resident memory ten minutes in, at the end',
  'max': 'ms, the longest frame',
  'gc50': 'collections over 50 ms in any one minute',
};

/// P2 whole.
const String defaultFailOn = 'rssGrowth=1.15,max=250,gc50=1';

Future<void> main(List<String> args) async {
  switch (args) {
    case ['check-fail-on', final line]:
      try {
        parseFailOn(line);
      } on FormatException catch (error) {
        stderr.writeln(error.message);
        exitCode = 2;
      }
    case ['define', final path, final key, final value]:
      final file = File(path);
      file.writeAsStringSync(
        jsonEncode(<String, Object?>{
          ...(jsonDecode(file.readAsStringSync()) as Map<String, Object?>),
          key: value,
        }),
      );
    case ['gc', final uri, final out]:
      exitCode = await _listenToGc(uri, out);
    case [
          'report',
          final pacing,
          final rss,
          final gc,
          final crash,
          final outDir,
          final label,
          final placement,
          final commit,
          final load,
          ...final rest,
        ]
        when rest.length <= 1:
      final Map<String, double> failOn;
      try {
        failOn = parseFailOn(rest.isEmpty ? defaultFailOn : rest.single);
      } on FormatException catch (error) {
        stderr.writeln(error.message);
        exitCode = 2;
        return;
      }
      final soak = SoakRun.read(
        pacingPath: pacing,
        rssPath: rss,
        gcPath: gc,
        crashPath: crash,
      );
      final name = 'soak-$label-$placement';
      final failures = soak.failures(failOn);
      final page = soak.markdown(
        label: label,
        placement: placement,
        commit: commit,
        load: load,
        failOn: failOn,
        failures: failures,
        graph: '$name-rss.svg',
      );
      Directory(outDir).createSync(recursive: true);
      File('$outDir/$name.md').writeAsStringSync(page);
      File(
        '$outDir/$name-rss.svg',
      ).writeAsStringSync(soak.rssSvg(growth: failOn['rssGrowth'] ?? 1.15));
      stdout.write(page);
      exitCode = failures.isEmpty ? 0 : 1;
    default:
      stderr.writeln(
        'usage: soak_report.dart check-fail-on <fail-on>\n'
        '       soak_report.dart define <defines.json> <key> <value>\n'
        '       soak_report.dart gc <vm-service-uri> <gc.txt>\n'
        '       soak_report.dart report <pacing.json> <rss.txt> <gc.txt> '
        '<crash.txt> <out-dir> <label> <placement> <commit> <load> '
        '[<fail-on>]',
      );
      exitCode = 2;
  }
}

/// Reads `rssGrowth=1.15,max=250,gc50=1`; a key it does not know is a
/// [FormatException], so a misspelt line checks something or nothing runs.
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
            '--fail-on: "$key" is not a threshold of the soak; '
            'the known ones are ${failOnKeys.keys.join(', ')}',
          ),
        _ => throw FormatException('--fail-on: "$part" is not key=number'),
      },
  };
}

/// The `ws://` address of the VM service a `flutter drive` log names as
/// `http://127.0.0.1:<port>/<token>=/`.
String webSocketOf(String uri) {
  final http = Uri.parse(uri.trim());
  final path = http.path.endsWith('/') ? http.path : '${http.path}/';
  return http.replace(scheme: 'ws', path: '${path}ws').toString();
}

Future<int> _listenToGc(String uri, String out) async {
  final WebSocket socket;
  try {
    socket = await WebSocket.connect(webSocketOf(uri));
  } on Object catch (error) {
    stderr.writeln('gc: no VM service at $uri: $error');
    return 1;
  }
  socket.add(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': '1',
      'method': 'streamListen',
      'params': <String, Object?>{'streamId': 'GC'},
    }),
  );
  final pauses = GcPauses();
  final clock = Stopwatch()..start();
  final sink = File(out).openWrite(mode: FileMode.append);
  await for (final raw in socket) {
    if (raw is! String) continue;
    final message = jsonDecode(raw);
    if (message case {
      'method': 'streamNotify',
      'params': {'event': final Map<String, Object?> event},
    }) {
      final seconds = clock.elapsedMilliseconds / 1000;
      for (final pause in pauses.observe(event)) {
        sink.writeln(
          '${seconds.toStringAsFixed(3)} ${pause.isolate} ${pause.space} '
          '${pause.millis.toStringAsFixed(3)}',
        );
      }
      await sink.flush();
    }
  }
  await sink.close();
  return 0;
}

/// Turns the VM's `GC` events into pauses: per isolate and heap space, the
/// time in collections gained over the collections gained.
final class GcPauses {
  final Map<String, ({int collections, double seconds})> _last =
      <String, ({int collections, double seconds})>{};

  /// The pauses one event tells of: none for an event that is not a
  /// collection, or a space that did not collect.
  List<({String isolate, String space, double millis})> observe(
    Map<String, Object?> event,
  ) {
    if (event['kind'] != 'GC') return const [];
    final isolate = switch (event['isolate']) {
      {'id': final String id} => id,
      _ => '?',
    };
    return [
      for (final space in const <String>['new', 'old'])
        if (event[space] case {
          'collections': final num collections,
          'time': final num seconds,
        })
          ?_pause(isolate, space, collections.toInt(), seconds.toDouble()),
    ];
  }

  ({String isolate, String space, double millis})? _pause(
    String isolate,
    String space,
    int collections,
    double seconds,
  ) {
    final key = '$isolate/$space';
    final last = _last[key];
    _last[key] = (collections: collections, seconds: seconds);
    // The first event of a space has nothing to subtract: what it carries
    // is everything since the isolate began, the run's start-up among it.
    if (last == null || collections <= last.collections) return null;
    final millis =
        (seconds - last.seconds) * 1000 / (collections - last.collections);
    return (isolate: isolate, space: space, millis: millis);
  }
}

/// One soak, read off the files `soak.sh` gathered.
final class SoakRun {
  SoakRun({
    required this.pacing,
    required this.about,
    required this.rss,
    required this.gc,
    required this.crashes,
  });

  factory SoakRun.read({
    required String pacingPath,
    required String rssPath,
    required String gcPath,
    required String crashPath,
  }) {
    final data = switch (File(pacingPath).existsSync()
        ? jsonDecode(File(pacingPath).readAsStringSync())
        : null) {
      final Map<String, Object?> map => map,
      _ => const <String, Object?>{},
    };
    List<String> lines(String path) => File(path).existsSync()
        ? File(
            path,
          ).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList()
        : const <String>[];
    return SoakRun(
      pacing: (data['pacing'] as Map?)?.cast<String, Object?>(),
      about: (data['about'] as Map?)?.cast<String, Object?>() ?? const {},
      rss: [
        for (final line in lines(rssPath))
          if (line.split(RegExp(r'\s+')) case [
            final t,
            final kb,
          ] when num.tryParse(t) != null && num.tryParse(kb) != null)
            (seconds: num.parse(t).toDouble(), mb: num.parse(kb) / 1024),
      ],
      gc: File(gcPath).existsSync()
          ? [
              for (final line in lines(gcPath))
                if (line.split(' ') case [final t, _, final space, final ms]
                    when double.tryParse(t) != null &&
                        double.tryParse(ms) != null)
                  (
                    seconds: double.parse(t),
                    space: space,
                    millis: double.parse(ms),
                  ),
            ]
          : null,
      crashes: lines(crashPath),
    );
  }

  /// `ReplayPacing.toJson` with the frames in `millis`; null when the run
  /// did not report.
  final Map<String, Object?>? pacing;
  final Map<String, Object?> about;

  /// One sample a second, in MB from the first.
  final List<({double seconds, double mb})> rss;

  /// The collections, or null when the VM service was not reached.
  final List<({double seconds, String space, double millis})>? gc;

  /// A crash or an ANR, a line each.
  final List<String> crashes;

  /// How long the memory was sampled, in seconds.
  double get seconds => rss.isEmpty ? 0 : rss.last.seconds - rss.first.seconds;

  /// Where the memory is compared from: ten minutes in, or one twelfth of
  /// a run shorter than two hours.
  double get baselineSeconds => math.min(600.0, seconds / 12);

  /// The first sample at or past [baselineSeconds]; null with no samples.
  ({double seconds, double mb})? get baseline {
    if (rss.isEmpty) return null;
    final at = rss.first.seconds + baselineSeconds;
    return rss.firstWhere((s) => s.seconds >= at, orElse: () => rss.last);
  }

  double? get rssGrowth => switch ((baseline, rss.lastOrNull)) {
    (final from?, final end?) when from.mb > 0 => end.mb / from.mb,
    _ => null,
  };

  /// The most collections over 50 ms in one minute of the run.
  int? get worstMinuteOver50 {
    final gc = this.gc;
    if (gc == null) return null;
    final perMinute = <int, int>{};
    for (final pause in gc.where((p) => p.millis > 50)) {
      perMinute.update(pause.seconds ~/ 60, (n) => n + 1, ifAbsent: () => 1);
    }
    return perMinute.values.fold<int>(0, math.max);
  }

  /// One sentence per threshold broken, crash and missing report included.
  List<String> failures(Map<String, double> failOn) {
    final pacing = this.pacing;
    return <String>[
      if (pacing == null) 'the run ended without reporting its frames',
      for (final crash in crashes) 'crash or ANR: $crash',
      for (final MapEntry(:key, value: line) in failOn.entries)
        ?switch (key) {
          'rssGrowth' => switch (rssGrowth) {
            null => 'rssGrowth: no resident memory was measured',
            final growth when growth > line + 1e-9 =>
              'rssGrowth ${growth.toStringAsFixed(3)} is over the line of '
                  '${line.toStringAsFixed(2)}',
            _ => null,
          },
          'max' => switch (pacing?['max']) {
            final num max when max > line =>
              'the longest frame, ${max.toStringAsFixed(2)} ms, is over the '
                  'line of ${line.toStringAsFixed(0)} ms',
            _ => null,
          },
          'gc50' => switch (worstMinuteOver50) {
            null =>
              'gc50: the pauses were not measured (the VM service was not '
                  'reached)',
            final worst when worst > line =>
              'gc50: $worst collections over 50 ms in one minute, over the '
                  'line of ${line.toStringAsFixed(0)}',
            _ => null,
          },
          _ => null,
        },
    ];
  }

  String markdown({
    required String label,
    required String placement,
    required String commit,
    required String load,
    required Map<String, double> failOn,
    required List<String> failures,
    required String graph,
  }) {
    final pacing = this.pacing;
    String ms(Object? value) =>
        value is num ? '${value.toStringAsFixed(2)} ms' : '—';
    final millis = (pacing?['millis'] as List?)?.cast<num>() ?? const <num>[];
    final over250 = millis.where((m) => m > 250).length;
    final date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final from = baseline;
    final gc = this.gc;
    final out = StringBuffer()
      ..writeln('# Soak: $label, $placement')
      ..writeln()
      ..writeln(
        'Written by `tool/soak.sh` on $date at `$commit`. '
        '`${about['run'] ?? 'the run'}` looped for '
        '${(seconds / 60).toStringAsFixed(1)} minutes with the simulation '
        '$placement, every frame timed and the resident memory read once a '
        'second. Held to `${[for (final e in failOn.entries) '${e.key}=${e.value == e.value.roundToDouble() ? e.value.toInt() : e.value}'].join(',')}`.',
      )
      ..writeln()
      ..writeln(
        '| frames | p50 | p99 | worst | over 250 ms | RSS at '
        '${(baselineSeconds / 60).toStringAsFixed(1)} min | RSS at the end '
        '| growth | GC pauses over 50 ms (worst minute) |',
      )
      ..writeln(
        '| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
      )
      ..writeln(
        '| ${pacing?['frames'] ?? '—'} | ${ms(pacing?['p50'])} | '
        '${ms(pacing?['p99'])} | ${ms(pacing?['max'])} | $over250 | '
        '${from == null ? '—' : '${from.mb.toStringAsFixed(1)} MB'} | '
        '${rss.isEmpty ? '—' : '${rss.last.mb.toStringAsFixed(1)} MB'} | '
        '${rssGrowth?.toStringAsFixed(3) ?? '—'} | '
        '${gc == null ? 'not measured' : '${gc.where((p) => p.millis > 50).length} ($worstMinuteOver50)'} |',
      )
      ..writeln()
      ..writeln('![Resident memory over the run]($graph)')
      ..writeln()
      ..writeln('- device: ${about['device'] ?? '?'}, ${about['os'] ?? '?'}')
      ..writeln('- build: ${about['mode'] ?? '?'}')
      ..writeln('- host load average when the run began: $load')
      ..writeln(
        '- memory compared from '
        '${baselineSeconds >= 600 ? 'ten minutes in' : 'one twelfth of the way in (a run shorter than two hours)'}',
      )
      ..writeln(switch (gc) {
        null =>
          '- garbage collection: not measured, the VM service was not '
              'reached',
        final gc =>
          '- garbage collection: ${gc.length} collections from the VM '
              'service\'s `GC` stream, the longest '
              '${gc.isEmpty ? '—' : ms(gc.map((p) => p.millis).reduce(math.max))}',
      })
      ..writeln(
        '- crashes and ANRs: ${crashes.isEmpty ? 'none' : crashes.length}',
      )
      ..writeln()
      ..writeln(failures.isEmpty ? '**Held every threshold.**' : 'Broke:');
    if (failures.isNotEmpty) out.writeln();
    for (final line in failures) {
      out.writeln('- $line');
    }
    return out.toString();
  }

  /// The resident memory over the run, with the line [growth] times the
  /// value it is compared from that it must stay under.
  String rssSvg({double growth = 1.15}) {
    const width = 720.0, height = 300.0, left = 56.0, bottom = 36.0;
    const top = 16.0, right = 16.0;
    final from = baseline;
    final limit = from == null ? null : from.mb * growth;
    final high = math.max(
      rss.fold<double>(1, (m, s) => math.max(m, s.mb)),
      limit ?? 0,
    );
    final yMax = (high * 1.1 / 50).ceil() * 50.0;
    final minutes = math.max(seconds / 60, 1 / 60);
    double x(double s) =>
        left +
        (s - (rss.firstOrNull?.seconds ?? 0)) /
            60 /
            minutes *
            (width - left - right);
    double y(double mb) => top + (1 - mb / yMax) * (height - top - bottom);
    String f(double v) => v.toStringAsFixed(1);
    final out = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $width $height" '
        'width="$width" height="$height" font-family="sans-serif" '
        'font-size="11">',
      )
      ..writeln('<rect width="$width" height="$height" fill="#ffffff"/>');
    for (var i = 0; i <= 5; i++) {
      final mb = yMax * i / 5;
      out
        ..writeln(
          '<line x1="$left" x2="${width - right}" y1="${f(y(mb))}" '
          'y2="${f(y(mb))}" stroke="#e4e4e4"/>',
        )
        ..writeln(
          '<text x="${left - 6}" y="${f(y(mb) + 4)}" text-anchor="end" '
          'fill="#555">${mb.round()} MB</text>',
        );
    }
    for (var i = 0; i <= 4; i++) {
      final m = minutes * i / 4;
      final at = (rss.firstOrNull?.seconds ?? 0) + m * 60;
      out.writeln(
        '<text x="${f(x(at))}" y="${height - 14}" text-anchor="middle" '
        'fill="#555">${m.toStringAsFixed(m < 10 ? 1 : 0)} min</text>',
      );
    }
    if (limit != null && from != null) {
      out
        ..writeln(
          '<line x1="$left" x2="${width - right}" y1="${f(y(limit))}" '
          'y2="${f(y(limit))}" stroke="#c0392b" stroke-dasharray="6 4"/>',
        )
        ..writeln(
          '<text x="${width - right}" y="${f(y(limit) - 5)}" '
          'text-anchor="end" fill="#c0392b">$growth × '
          '${f(from.mb)} MB</text>',
        )
        ..writeln(
          '<line x1="${f(x(from.seconds))}" x2="${f(x(from.seconds))}" '
          'y1="$top" y2="${height - bottom}" stroke="#999" '
          'stroke-dasharray="2 3"/>',
        );
    }
    if (rss.isNotEmpty) {
      out.writeln(
        '<polyline fill="none" stroke="#1f6feb" stroke-width="1.5" '
        'points="${rss.map((s) => '${f(x(s.seconds))},${f(y(s.mb))}').join(' ')}"/>',
      );
    }
    out.writeln('</svg>');
    return out.toString();
  }
}
