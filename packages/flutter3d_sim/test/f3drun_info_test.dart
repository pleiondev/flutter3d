/// `rp-01`'s acceptance criterion, run rather than argued: a `.f3drun` from
/// one game, read by `dart run` with no Flutter SDK anywhere in the process.
///
///     dart test test/f3drun_info_test.dart
///
/// `@TestOn('vm')` because this spawns a real `dart run` subprocess —
/// `dart:io`'s `Process`, which does not exist on the web, and which
/// `dart test -p chrome` would otherwise try and fail to compile.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

Demo _demo() {
  final checkpoints = DigestTrace(every: 1)
    ..observe(1, <String, Object?>{'step': 1})
    ..observe(2, <String, Object?>{'step': 2});
  return Demo(
    level: 'assets/levels/crypt.json',
    levelHash: 'deadbeef',
    start: const Snapshot(<String, Object?>{'random': 7}),
    tape: InputTape(
      seed: 7,
      frames: const <InputFrame>[InputFrame(), InputFrame()],
    ),
    buildStamp: 'test-build-42',
    checkpoints: checkpoints,
    platform: 'macos',
    recordedBy: 'dmitrii',
  );
}

void main() {
  test('a .f3drun is read by dart run, with no Flutter SDK involved', () {
    final dir = Directory.systemTemp.createTempSync('f3drun_info_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    final file = File('${dir.path}/run${Demo.fileExtension}')
      ..writeAsStringSync(jsonEncode(_demo().toJson()));

    // The one thing this test cannot fake: a fresh `dart` process, the same
    // one `dart run` invokes from a terminal, given nothing but this
    // package's own `pub get` and the file just written.
    final result = Process.runSync('dart', <String>[
      'run',
      'bin/f3drun_info.dart',
      file.path,
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: 'stderr was: ${result.stderr}');
    final out = result.stdout as String;
    expect(out, contains('level:      assets/levels/crypt.json'));
    expect(out, contains('levelHash:  deadbeef'));
    expect(out, contains('steps:      2'));
    expect(out, contains('checkpoints: 2'));
    expect(out, contains('buildStamp: test-build-42'));
    expect(out, contains('platform:   macos'));
    expect(out, contains('recordedBy: dmitrii'));
    expect(out, isNot(contains('levelSwap')));
  });

  test('a level swapped under the run is listed with its step', () {
    final dir = Directory.systemTemp.createTempSync('f3drun_info_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final plain = _demo();
    final edit = Level(name: 'crypt', fogDensity: 0.02);
    final file = File('${dir.path}/run${Demo.fileExtension}')
      ..writeAsStringSync(
        jsonEncode(
          Demo(
            level: plain.level,
            levelHash: plain.levelHash,
            start: plain.start,
            tape: plain.tape,
            buildStamp: plain.buildStamp,
            checkpoints: plain.checkpoints,
            levelSwaps: <DemoLevelSwap>[DemoLevelSwap(step: 1, level: edit)],
          ).toJson(),
        ),
      );

    final result = Process.runSync('dart', <String>[
      'run',
      'bin/f3drun_info.dart',
      file.path,
    ], workingDirectory: Directory.current.path);

    // Mutation: leave the swaps out of the listing — a file that replays
    // only in the game that recorded it looks like any other run.
    expect(result.exitCode, 0, reason: 'stderr was: ${result.stderr}');
    expect(
      result.stdout as String,
      contains('levelSwap:  step 1, ${edit.digestHex}'),
    );
  });

  test('a demo from a newer format is refused with a suggestion, not a '
      'crash', () {
    final dir = Directory.systemTemp.createTempSync('f3drun_info_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    final json = _demo().toJson()..['version'] = Demo.formatVersion + 1;
    final file = File('${dir.path}/run${Demo.fileExtension}')
      ..writeAsStringSync(jsonEncode(json));

    final result = Process.runSync('dart', <String>[
      'run',
      'bin/f3drun_info.dart',
      file.path,
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, isNot(0));
    expect(result.stderr as String, contains('update flutter3d'));
  });
}
