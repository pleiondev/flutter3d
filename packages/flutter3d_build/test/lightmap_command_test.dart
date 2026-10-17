import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/cli.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// `flutter3d lightmap`: a level in, its `.lightmap.bin` beside it.
void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('lightmap_cmd'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('bakes a sidecar beside the level, which reads back fresh', () async {
    final level = Level(
      name: 'a floor',
      brushes: <Brush>[
        Brush(center: Vector3(0.0, -0.5, 0.0), size: Vector3(4.0, 1.0, 4.0)),
      ],
      lights: <LevelLight>[LevelLight(position: Vector3(0.0, 2.0, 0.0))],
    );
    final path = '${scratch.path}/room.json';
    File(path).writeAsStringSync(jsonEncode(level.toJson()));

    final code = await runFlutter3d(<String>[
      'lightmap',
      '--bounces',
      '0',
      '--direct',
      path,
    ]);

    expect(code, CliExit.ok);
    final bin = File('${scratch.path}/room.lightmap.bin');
    expect(bin.existsSync(), isTrue);
    final map = Lightmap.fromBytes(bin.readAsBytesSync());
    expect(map.isStaleFor(level), isFalse);
  });

  test('a command line it cannot read is a usage error', () async {
    expect(await runFlutter3d(const <String>['lightmap']), CliExit.usage);
    expect(
      await runFlutter3d(const <String>['lightmap', '--bounces', 'x', 'a']),
      CliExit.usage,
    );
    expect(
      await runFlutter3d(<String>['lightmap', '${scratch.path}/none.json']),
      CliExit.failure,
    );
  });
}
