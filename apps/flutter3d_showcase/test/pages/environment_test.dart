@Tags(['golden', 'skip_very_good_optimization'])
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_showcase/pages/environment/irradiance_field.dart';
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
  group('environment pages', () {
    test('the irradiance field toggle tints the shadow it falls on', () async {
      // The point sampled sits in the shadow the wall casts on the floor
      // beside it — visible only because the wall casts a shadow at all.
      //
      // Mutation: leave the sun's `castsShadow` false, or leave the
      // shadow settings at the default `casterFaces: back` — a one-sided
      // plane the shadow pass "sees straight through" by that default —
      // and the floor beside the wall never actually falls into shadow,
      // so both frames come back the same flat white and this fails.
      final Uint8List on = await _shot(IrradianceFieldDemo()..baked = true);
      final Uint8List off = await _shot(IrradianceFieldDemo()..baked = false);
      final (int rOn, int gOn, int bOn) = _at(on, 64, 135);
      final (int rOff, int gOff, int bOff) = _at(off, 64, 135);
      expect(
        rOn + gOn + bOn,
        lessThan(150),
        reason: 'this point should be in the wall\'s own shadow',
      );
      expect(
        rOff,
        closeTo(gOff, 5),
        reason:
            'with no field, a shadow is lit by nothing but the flat, '
            'colourless ambient term',
      );
      expect(
        rOn - bOn,
        greaterThan((rOff - bOff) + 20),
        reason:
            'the field should warm the shadow towards the red wall\'s '
            'own colour, which the flat ambient term never does',
      );
    });
  });
}
