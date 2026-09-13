// ignore_for_file: avoid_print
//
/// Reads a `.f3drun` and says what is in it — no Flutter SDK, no engine,
/// nothing this package does not already carry.
///
///     dart run bin/f3drun_info.dart path/to/run.f3drun
///
/// **This is `rp-01`'s acceptance criterion, run rather than argued.** The
/// plan asks whether a file from one game can be read by `dart run` without
/// Flutter; this script is the answer, because `Demo.fromJson` never touched
/// Flutter to begin with — the reader has always been here, in `sim`, and
/// this is the first thing that calls it from outside a test.
///
/// A future `dart run flutter3d:replay` (`rp-05`) is the same read, followed
/// by rendering every step through `flutter3d_cpu` and writing a video. This
/// script is deliberately smaller than that: it exists to answer one question
/// on its own, before the bigger tool is built on top of it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_sim/flutter3d_sim.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run bin/f3drun_info.dart <path to .f3drun>');
    exitCode = 64; // EX_USAGE
    return;
  }

  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('${args.first}: no such file');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    stderr.writeln('${args.first}: not JSON (${error.message})');
    exitCode = 65; // EX_DATAERR
    return;
  }
  if (decoded is! Map<String, Object?>) {
    stderr.writeln('${args.first}: not a document');
    exitCode = 65;
    return;
  }

  final Demo demo;
  try {
    demo = Demo.fromJson(decoded);
  } on DemoFormatException catch (error) {
    stderr.writeln('${args.first}: ${error.message}');
    exitCode = 65;
    return;
  }

  print('level:      ${demo.level}');
  print('levelHash:  ${demo.levelHash}');
  print('steps:      ${demo.steps}');
  print('checkpoints: ${demo.checkpoints.steps.length}');
  print('buildStamp: ${demo.buildStamp}');
  print('platform:   ${demo.platform ?? '(unknown)'}');
  print('recordedBy: ${demo.recordedBy ?? '(anonymous)'}');
}
