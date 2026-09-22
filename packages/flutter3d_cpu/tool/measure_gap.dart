// What the two backends' references actually differ by, for one scene.
//
// `cross_backend_test.dart` prints this for every scene it compares, and the
// budgets in it are set just above what it printed. This is the same
// measurement for a single scene, reachable without a test runner, for the
// case that needs it: a reference has just been re-recorded and the budget
// beside it has to be re-set from the new number rather than from the old
// comment.
//
// Reads the PNGs through `flutter3d_core`'s own decoder rather than
// `dart:ui`, which is what lets this run under plain `dart`.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/measure_gap.dart <scene>');
    exitCode = 2;
    return;
  }
  final scene = args.single;
  final mine = File('test/goldens/$scene.png');
  final theirs = File('../flutter3d/test/goldens/$scene.png');
  for (final f in <File>[mine, theirs]) {
    if (!f.existsSync()) {
      stderr.writeln('missing: ${f.path}');
      exitCode = 1;
      return;
    }
  }

  final a = _rgba(mine);
  final b = _rgba(theirs);
  if (a.length != b.length) {
    stderr.writeln('different sizes: ${a.length} against ${b.length}');
    exitCode = 1;
    return;
  }

  final difference = compareFrames(a, b, channel: 8);
  stdout.writeln('$scene: $difference by more than 8');
}

Uint8List _rgba(File file) {
  final decoded = decodePng(file.readAsBytesSync());
  if (decoded == null) throw StateError('not a PNG this reader knows: $file');
  return decoded.rgba;
}
