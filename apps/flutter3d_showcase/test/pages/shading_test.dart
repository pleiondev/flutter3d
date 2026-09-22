@Tags(['golden', 'skip_very_good_optimization'])
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_showcase/pages/shading/alpha_modes.dart';
import 'package:flutter3d_showcase/pages/shading/ambient_light.dart';
import 'package:flutter3d_showcase/pages/shading/draw_state.dart';
import 'package:flutter3d_showcase/pages/shading/normal_mapping.dart';
import 'package:flutter3d_showcase/pages/shading/texture_filtering.dart';
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

/// How many pixels differ between two frames by more than a rounding error.
int _differing(Uint8List a, Uint8List b) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    final int delta =
        (a[i] - b[i]).abs() +
        (a[i + 1] - b[i + 1]).abs() +
        (a[i + 2] - b[i + 2]).abs();
    if (delta > 12) count++;
  }
  return count;
}

/// The colour of the pixel at [x], [y].
(int, int, int) _at(Uint8List frame, int x, int y) {
  final int at = (y * 320 + x) * 4;
  return (frame[at], frame[at + 1], frame[at + 2]);
}

void main() {
  group('shading pages', () {
    test(
      'the ambient slider lifts the side the key light never reaches',
      () async {
        // `_differing` alone does not catch this one: with the camera
        // pointed down the key light's own beam, the whole ball reads as
        // fully lit at every ambient level and only shifts by a few units
        // per channel across a wide area as the tone mapper responds to the
        // extra energy — enough rounding noise, spread over enough pixels,
        // to clear a naive pixel-count threshold while looking, to a reader,
        // exactly the same. What a reader would actually notice is the dark
        // side of the ball going from black to lit, so this checks that
        // directly, at the point the terminator crosses this page's frame.
        //
        // Mutation: point the camera back down the key light's own beam
        // (`yaw = 1.4`) — this point sits on the lit face instead and stays
        // close to full brightness at both ends of the slider.
        final Uint8List dim = await _shot(
          AmbientLightDemo()..ambientIntensity = 0.0,
        );
        final Uint8List lit = await _shot(
          AmbientLightDemo()..ambientIntensity = 1.0,
        );
        final (int r0, int g0, int b0) = _at(dim, 168, 68);
        final (int r1, int g1, int b1) = _at(lit, 168, 68);
        expect(
          r0 + g0 + b0,
          lessThan(40),
          reason:
              'this point should start on the side the key light never '
              'reaches',
        );
        expect(
          (r1 + g1 + b1) - (r0 + g0 + b0),
          greaterThan(400),
          reason: 'raising the ambient term should light it up',
        );
      },
    );

    test('the normal scale changes the picture', () async {
      // Mutation: read `normalScale` nowhere. Zero and one would then draw the
      // same frame and the slider would do nothing.
      final Uint8List flat = await _shot(NormalMappingDemo()..normalScale = 0);
      final Uint8List bumpy = await _shot(NormalMappingDemo()..normalScale = 1);
      expect(_differing(flat, bumpy), greaterThan(300));
    });

    test('taking the normal map away flattens the ball', () async {
      // Mutation: ignore the switch. The two frames would be identical.
      final Uint8List mapped = await _shot(NormalMappingDemo());
      final Uint8List bare = await _shot(NormalMappingDemo()..useMap = false);
      expect(_differing(mapped, bare), greaterThan(300));
    });

    test('a backdrop that writes no depth lets the nearer box show', () async {
      // Mutation: leave `depthWrite` alone on the panel. The panel would cover
      // the box and the centre of the frame would be orange, not blue.
      final Uint8List backdrop = await _shot(DrawStateDemo());
      final Uint8List blocking = await _shot(
        DrawStateDemo()..panelWritesDepth = true,
      );
      final (int r1, _, int b1) = _at(backdrop, 160, 90);
      final (int r2, _, int b2) = _at(blocking, 160, 90);
      expect(b1, greaterThan(r1), reason: 'the box is in front of the panel');
      expect(r2, greaterThan(b2), reason: 'the panel hides the box');
    });

    test('back-face culling hides the turned-away square', () async {
      // Mutation: pass `backfaceCulling: true` whatever the switch says. The
      // square would never appear.
      final Uint8List culled = await _shot(DrawStateDemo());
      final Uint8List both = await _shot(
        DrawStateDemo()..cullBackFaces = false,
      );
      expect(_differing(culled, both), greaterThan(100));
    });

    test('anisotropy changes how a distant floor is filtered', () async {
      // Mutation: build the settings without `anisotropy`. One and sixteen
      // would draw the same floor.
      final Uint8List one = await _shot(
        TextureFilteringDemo()..anisotropyChoice = 0,
      );
      final Uint8List sixteen = await _shot(
        TextureFilteringDemo()..anisotropyChoice = 4,
      );
      // A grazing floor at 320 by 180 differs in a thin band near the horizon.
      expect(_differing(one, sixteen), greaterThan(10));
    });

    test('the alpha cutoff moves the edge of the masked panel', () async {
      // Mutation: never copy `cutoff` to the materials. Both frames would be
      // the same.
      final Uint8List low = await _shot(AlphaModesDemo()..cutoff = 0.15);
      final Uint8List high = await _shot(AlphaModesDemo()..cutoff = 0.85);
      expect(_differing(low, high), greaterThan(100));
    });
  });
}
