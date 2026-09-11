/// `teapot.f3d -f glb` — `fmt-14`'s own worked example, run for real: the
/// output opens through `GltfLoader` and passes `validateGltfExport`.
///
///     dart test test/convert_teapot_test.dart
///
/// **The one thing neither `options_test.dart` nor `report_printer_test.dart`
/// checks.** Both exercise this tool's own helpers against values built by
/// hand; neither ever runs a real file through `exportToGlb` the way `bin/
/// convert_asset.dart` does, so a real fixture converting cleanly was never
/// actually confirmed by a test — only by whoever last ran the CLI by hand.
library;

import 'dart:io';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:test/test.dart';

void main() {
  test('teapot.f3d converted to glb reads back clean through the loader and '
      'passes the validator — the row\'s own worked example', () async {
    final bytes = await File(
      '../../packages/flutter3d_samples/assets/f3d/teapot.f3d',
    ).readAsBytes();
    final document = F3dDocument.parse(bytes);

    final report = await exportToGlb(document, name: 'teapot');

    // The loader: exportToGlb already writes the GLB, reads it back with
    // GltfLoader and compares against the source document — a difference
    // here means the loader could not make sense of what the writer wrote.
    expect(report.differences, isEmpty);

    // The validator: fmt-11's own check on top of the loader, catching a
    // wrong accessor bound the loader itself has no reason to recompute.
    final problems = await validateGltfExport(report.files['teapot.glb']!);
    expect(problems, isEmpty);
  });
}
