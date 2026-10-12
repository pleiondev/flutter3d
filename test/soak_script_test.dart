/// `tool/soak.sh` names the platformer's harness and tape and refuses what it
/// cannot soak, and `tool/soak_report.dart` reads a soak the way P2 does:
/// the memory from ten minutes in (or a twelfth of a shorter run), the
/// pauses from the VM's own count, a crash whatever the thresholds.
///
///     dart test test/soak_script_test.dart
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tool/soak_report.dart';

Future<ProcessResult> _soak(List<String> args) =>
    Process.run('bash', <String>['tool/soak.sh', ...args]);

SoakRun _run({
  List<({double seconds, double mb})>? rss,
  List<({double seconds, String space, double millis})>? gc = const [],
  List<String> crashes = const <String>[],
  num max = 40.0,
}) => SoakRun(
  pacing: <String, Object?>{
    'frames': 1000,
    'p50': 16.0,
    'p99': 30.0,
    'max': max,
    'millis': <num>[16.0, max],
  },
  about: const <String, Object?>{'run': 'platformer.f3drun'},
  rss:
      rss ??
      [for (var s = 0; s <= 7200; s += 60) (seconds: s * 1.0, mb: 300.0)],
  gc: gc,
  crashes: crashes,
);

void main() {
  const harness =
      'apps/flutter3d_demo_platformer/integration_test/pacing_test.dart';
  final placesInIsolate = File(
    harness,
  ).readAsStringSync().contains('FLUTTER3D_SOAK_PLACEMENT');

  test('the inline soak names the platformer, its tape and P2', () async {
    final result = await _soak(<String>[
      '-d',
      'R5CX00A55',
      '--placement',
      'inline',
      '--dry-run',
    ]);
    final said = '${result.stdout}${result.stderr}';
    expect(result.exitCode, 0, reason: said);
    expect(said, contains('apps/flutter3d_demo_platformer'));
    expect(said, contains('site/assets/samples/platformer.f3drun'));
    expect(said, contains('looped for 120 min'));
    expect(said, contains('rssGrowth=1.15,max=250,gc50=1'));
    expect(said, contains('soak-R5CX00A55-<placement>.md'));
  });

  test('the isolate is refused by name while the harness cannot place it '
      'there', () async {
    final result = await _soak(<String>['-d', 'macos', '--dry-run']);
    final said = '${result.stdout}${result.stderr}';
    // Mutation: soak the isolate through the inline harness, and the report
    // says isolate over an inline run.
    expect(result.exitCode, placesInIsolate ? 0 : 2, reason: said);
    if (!placesInIsolate) expect(said, contains('FLUTTER3D_SOAK_PLACEMENT'));
  });

  test('a threshold it does not know is refused before a build', () async {
    final result = await _soak(<String>[
      '-d',
      'macos',
      '--placement',
      'inline',
      '--fail-on',
      'rssEnd=400',
      '--dry-run',
    ]);
    expect(result.exitCode, 2);
    expect('${result.stderr}', contains('"rssEnd" is not a threshold'));
  });

  test('the memory is compared from ten minutes in, or a twelfth of a '
      'shorter run', () {
    final long = _run(
      rss: [
        for (var s = 0; s <= 7200; s += 60)
          (seconds: s * 1.0, mb: s < 600 ? 250.0 : 300.0 + s / 7200 * 40),
      ],
    );
    expect(long.baseline?.seconds, 600);
    expect(long.rssGrowth, closeTo(340 / (300 + 600 / 7200 * 40), 1e-9));
    expect(long.failures(parseFailOn(defaultFailOn)), isEmpty);

    final rehearsal = _run(
      rss: [for (var s = 0; s <= 180; s++) (seconds: s * 1.0, mb: 100.0 + s)],
    );
    expect(rehearsal.baseline?.seconds, 15);
    expect(rehearsal.rssGrowth, closeTo(280 / 115, 1e-9));
    expect(
      rehearsal.failures(parseFailOn(defaultFailOn)).single,
      startsWith('rssGrowth 2.435'),
    );
  });

  test('two pauses over 50 ms in one minute fail, one a minute holds', () {
    ({double seconds, String space, double millis}) pause(double at) =>
        (seconds: at, space: 'old', millis: 61.0);
    final once = _run(gc: [pause(10), pause(70), pause(130)]);
    expect(once.worstMinuteOver50, 1);
    expect(once.failures(parseFailOn('gc50=1')), isEmpty);
    final twice = _run(gc: [pause(10), pause(50)]);
    expect(twice.failures(parseFailOn('gc50=1')).single, startsWith('gc50: 2'));
    // Not measured is not nought.
    expect(
      _run(gc: null).failures(parseFailOn('gc50=1')).single,
      contains('not measured'),
    );
  });

  test('a crash fails whatever the thresholds, and so does a frame over the '
      'line', () {
    final crashed = _run(crashes: <String>['ANR in dev.flutter3d.platformer']);
    expect(crashed.failures(parseFailOn('max=250')).single, contains('ANR'));
    expect(
      _run(max: 251.0).failures(parseFailOn('max=250')).single,
      startsWith('the longest frame'),
    );
  });

  test('a pause is the time a space gained over the collections it gained', () {
    final pauses = GcPauses();
    Map<String, Object?> event(int collections, double seconds) =>
        <String, Object?>{
          'kind': 'GC',
          'isolate': const <String, Object?>{'id': 'isolates/1'},
          'new': <String, Object?>{'collections': collections, 'time': seconds},
          'old': const <String, Object?>{'collections': 0, 'time': 0.0},
        };
    // The first event is everything since the isolate began: no pause.
    expect(pauses.observe(event(10, 0.5)), isEmpty);
    final [one] = pauses.observe(event(11, 0.502));
    expect(one.space, 'new');
    expect(one.millis, closeTo(2.0, 1e-9));
    final [two] = pauses.observe(event(13, 0.522));
    expect(two.millis, closeTo(10.0, 1e-9));
    expect(pauses.observe(<String, Object?>{'kind': 'Logging'}), isEmpty);
  });

  test('the address flutter drive prints becomes the service\'s socket', () {
    expect(
      webSocketOf('http://127.0.0.1:59279/Pqre6WYif8I=/'),
      'ws://127.0.0.1:59279/Pqre6WYif8I=/ws',
    );
  });

  test('the graph draws the line the memory must stay under', () {
    final svg = _run().rssSvg(growth: 1.15);
    expect(svg, startsWith('<svg'));
    expect(svg, contains('1.15 × 300.0 MB'));
    expect(svg, contains('<polyline'));
  });
}
