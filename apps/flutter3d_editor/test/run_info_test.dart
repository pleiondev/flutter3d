import 'dart:convert';

import 'package:flutter3d_editor/src/run_info.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

Demo _run() => Demo(
  level: 'assets/levels/crypt.json',
  levelHash: 'deadbeef',
  start: const Snapshot(<String, Object?>{'player': <String, Object?>{}}),
  tape: InputTape(
    seed: 7,
    frames: <InputFrame>[for (var i = 0; i < 40; i++) const InputFrame()],
  ),
  buildStamp: 'test-build',
  checkpoints: DigestTrace(every: 25),
  platform: 'macos',
  recordedBy: 'apps/flutter3d_demo_dungeon',
);

void main() {
  test('a real .f3drun round-trips through parseRunFile', () {
    final run = _run();
    final text = jsonEncode(run.toJson());
    final parsed = parseRunFile(text);
    expect(parsed.level, run.level);
    expect(parsed.levelHash, run.levelHash);
    expect(parsed.buildStamp, run.buildStamp);
    expect(parsed.tape.frames, hasLength(40));
  });

  test('text that is not JSON at all throws, not crashes', () {
    expect(() => parseRunFile('not json'), throwsFormatException);
  });

  test('JSON that is not an object is refused by name', () {
    expect(
      () => parseRunFile('[1, 2, 3]'),
      throwsA(isA<DemoFormatException>()),
    );
  });

  test('JSON missing a required field is refused, not defaulted', () {
    final json = _run().toJson()..remove('checkpoints');
    expect(
      () => parseRunFile(jsonEncode(json)),
      throwsA(isA<DemoFormatException>()),
    );
  });

  test('a newer format version is refused with a sentence', () {
    final json = _run().toJson();
    json['version'] = Demo.formatVersion + 1;
    expect(
      () => parseRunFile(jsonEncode(json)),
      throwsA(isA<DemoFormatException>()),
    );
  });
}
