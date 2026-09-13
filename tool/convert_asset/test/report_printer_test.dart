/// `writeReport` on its own — `fmt-14`'s own row.
///
///     dart test test/report_printer_test.dart
library;

import 'dart:typed_data';

import 'package:convert_asset/convert_asset.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:test/test.dart';

void main() {
  test('a clean report names the file and says so twice', () {
    final report = ExportReport(
      files: <String, Uint8List>{'teapot.glb': Uint8List(0)},
      writerWarnings: const <String>[],
      differences: const <DocumentDifference>[],
    );
    final out = StringBuffer();
    writeReport(report, out);
    final text = out.toString();
    expect(text, contains('wrote teapot.glb'));
    expect(text, contains('no warnings'));
    expect(text, contains('read back clean'));
  });

  test('warnings and differences are both counted and listed', () {
    final report = ExportReport(
      files: <String, Uint8List>{
        'teapot.obj': Uint8List(0),
        'teapot.mtl': Uint8List(0),
      },
      writerWarnings: const <String>[
        '1 skin(s) were not written; OBJ has no skinning',
      ],
      differences: <DocumentDifference>[
        const DocumentDifference('nodes: 2 in, 1 out'),
      ],
    );
    final out = StringBuffer();
    writeReport(report, out);
    final text = out.toString();
    expect(text, contains('wrote teapot.obj, teapot.mtl'));
    expect(text, contains('1 warning(s):'));
    expect(text, contains('- 1 skin(s) were not written; OBJ has no skinning'));
    expect(text, contains('1 difference(s) reading it back:'));
    expect(text, contains('- nodes: 2 in, 1 out'));
  });
}
