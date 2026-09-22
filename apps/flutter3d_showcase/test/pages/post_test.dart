@Tags(['golden', 'skip_very_good_optimization'])
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_showcase/pages/post/anti_aliasing.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/demo_run.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/page_harness.dart';

/// One frame of [demo] at 320 by 180, as RGBA bytes.
Future<Uint8List> _shot(ShowcaseDemo demo) async {
  final CpuDevice device = cpuDevice();
  final DemoRun run = await DemoRun.start(device, demo);
  try {
    run.update(1 / 60);
    final FrameResult frame = run.render(320, 180);
    final ByteData? pixels = await device.readPixels(frame.frame);
    return Uint8List.fromList(pixels!.buffer.asUint8List());
  } finally {
    run.dispose();
  }
}

/// The colour of the pixel at [x], [y].
(int, int, int) _at(Uint8List frame, int x, int y) {
  final int at = (y * 320 + x) * 4;
  return (frame[at], frame[at + 1], frame[at + 2]);
}

void main() {
  group('post pages', () {
    test('fxaa visibly softens one of the spokes\' edges', () async {
      // A single diagonal card staircases at exactly one contrast step,
      // which barely moves under FXAA — not enough of an edge for the
      // effect to read as more than noise. A dozen spokes crossing the
      // same centre at a dozen angles is what actually makes the softening
      // this page claims worth looking at.
      //
      // Mutation: build one rotated card instead of the spokes — this
      // point sits far enough from any single straight edge that both
      // frames come back the same background colour and this fails.
      final Uint8List on = await _shot(AntiAliasingDemo()..enabled = true);
      final Uint8List off = await _shot(AntiAliasingDemo()..enabled = false);
      final (int rOn, int gOn, int bOn) = _at(on, 109, 39);
      final (int rOff, int gOff, int bOff) = _at(off, 109, 39);
      expect(
        (rOn + gOn + bOn) - (rOff + gOff + bOff),
        greaterThan(300),
        reason: 'FXAA should lighten a pixel this close to several edges',
      );
    });
  });
}
