/// `readRecentModel`/`pathExists` — the two seams `ui-15`'s start screen
/// reads a stored recent path through.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_modeler/src/files/project_files_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('recent_model_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a real file reads back exactly what was written', () async {
    final file = File('${dir.path}/model.glb')
      ..writeAsBytesSync(<int>[1, 2, 3, 4]);
    final read = await readRecentModel(file.path);
    expect(read, Uint8List.fromList(<int>[1, 2, 3, 4]));
  });

  test(
    'a path nothing lives at any more reads as null, not an exception',
    () async {
      final read = await readRecentModel('${dir.path}/gone.glb');
      expect(read, isNull);
    },
  );

  test('pathExists agrees with what is actually on disk', () {
    final file = File('${dir.path}/here.glb')..writeAsBytesSync(<int>[0]);
    expect(pathExists(file.path), isTrue);
    expect(pathExists('${dir.path}/not-here.glb'), isFalse);
  });
}
