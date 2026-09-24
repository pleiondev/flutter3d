/// Every engine block is bound whole — `H1`.
///
///     flutter test test/uniform_block_bind_test.dart
///
/// A block a draw binds replaces the block, member by member: whatever the map
/// leaves out is zero on a backend that packs the block afresh, and stale on
/// one that does not. The renderer used to spell each block's members out at
/// every call site, and a site that forgot one drew with a zero where a
/// shadow strength or an exposure belonged. With the generated blocks every
/// member is always there; this holds it, against the compiled layout, on
/// every parity fixture.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:flutter3d_shaders/uniform_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final which in ParityScene.values) {
    test('the ${which.name} fixture binds every engine block whole', () {
      // Mutation: bind FragInfo through a map written out by hand again, as
      // it was before the generated blocks, and leave `'target_origin'` out
      // of it: that bind comes back one member short.
      final device = RecordingDevice(
        CpuDevice(
          width: kParityWidth,
          height: kParityHeight,
          shaders: CpuShaderLibrary(builtinCpuShaders()),
        ),
      );
      final renderer = Renderer.create(
        device: device,
        fallbackAlbedo: texelOn(device.inner as CpuDevice, <int>[
          255,
          255,
          255,
          255,
        ]),
        fallbackNormal: texelOn(device.inner as CpuDevice, <int>[
          128,
          128,
          255,
          255,
        ]),
      );
      final built = buildParityScene(device, which: which);
      renderer.render(
        width: kParityWidth,
        height: kParityHeight,
        scene: built.scene,
        views: <RenderView>[RenderView(camera: built.camera)],
        settings: paritySettingsFor(which),
      );

      final short = <String>{};
      var checked = 0;
      for (final event in device.events) {
        if (event case TraceBindUniformBlock(
          :final shader,
          :final block,
          :final members,
        )) {
          final layout = uniformBlocks[shader]?[block];
          if (layout == null) continue;
          checked++;
          final missing = layout.keys.toSet().difference(members.keys.toSet());
          if (missing.isNotEmpty) short.add('$shader.$block lacks $missing');
        }
      }
      expect(checked, greaterThan(0));
      expect(short, isEmpty, reason: short.join('\n'));
    });
  }
}
