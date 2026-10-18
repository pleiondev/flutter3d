@Tags(['golden', 'skip_very_good_optimization'])
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_showcase/pages/scene/polylines.dart';
import 'package:flutter3d_showcase/src/demo/demo_run.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/page_harness.dart';

void main() {
  test('the routes are measured against the size they are drawn at', () async {
    // Mutation: leave the viewport at the 1280 by 720 the page starts with. A
    // route six pixels wide at that size draws three wide on a canvas half as
    // big, and twelve on one twice as big.
    final CpuDevice device = cpuDevice(width: 640, height: 360);
    final DemoRun run = await DemoRun.start(device, PolylinesDemo());
    try {
      for (final (int width, int height) in <(int, int)>[
        (640, 360),
        (320, 180),
      ]) {
        run.update(1 / 60);
        final FrameResult frame = run.render(width, height);
        final List<Float32List?> viewports = <Float32List?>[
          for (final MeshNode node in run.scene.meshes)
            node.material.polylineViewport,
        ];
        expect(viewports, hasLength(3));
        for (final Float32List? viewport in viewports) {
          expect(viewport, isNotNull);
          expect(
            <double>[viewport![0], viewport[1]],
            <double>[width.toDouble(), height.toDouble()],
            reason: '$width by $height',
          );
        }
        run.demo.verify(run.scene, frame);
      }
    } finally {
      run.dispose();
    }
  });
}
