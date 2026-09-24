/// A sequence of frames is as deterministic as a still — `G0`, `G2`.
///
///     flutter test test/frame_index_test.dart
///
/// Everything temporal the renderer grows in 0.8 (a jitter, a noise layer, a
/// history) is a function of `Renderer.frameIndex` and of nothing else. A
/// multi-frame golden relies on that: its capture is frame N of one renderer,
/// and it is only comparable run to run if frame N is the same every time.
/// Until something temporal is switched on, frame N is also frame 1.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _draw(
  Renderer renderer,
  CpuDevice device,
  ({Scene scene, CameraNode camera}) built,
  ParityScene which, {
  bool temporal = false,
}) async {
  final base = paritySettingsFor(which);
  final frame = renderer.render(
    width: kParityWidth,
    height: kParityHeight,
    scene: built.scene,
    views: <RenderView>[RenderView(camera: built.camera)],
    settings: temporal
        ? base.copyWith(
            antiAlias: base.antiAlias.copyWith(
              temporal: const TemporalSettings(enabled: true),
            ),
          )
        : base,
  );
  return (await device.readPixels(frame.frame))!.buffer.asUint8List();
}

void main() {
  test(
    'with temporal on, a sequence of frames is the same sequence twice',
    () async {
      // `R1`'s jitter and `R2`'s history, seen in pixels: two consecutive
      // frames of a still scene differ, and two renderers drawing the same
      // seventeen frames end on the same picture, because the offset and the
      // blend are functions of the frame index and of nothing else.
      const which = ParityScene.plain;
      Future<List<Uint8List>> run() async {
        final device = CpuDevice(
          width: kParityWidth,
          height: kParityHeight,
          shaders: CpuShaderLibrary(builtinCpuShaders()),
        );
        final renderer = Renderer.create(device: device);
        final built = buildParityScene(device, which: which);
        return <Uint8List>[
          for (var i = 0; i < 17; i++)
            await _draw(renderer, device, built, which, temporal: true),
        ];
      }

      final a = await run();
      final b = await run();
      expect(a[1], isNot(a[0]));
      expect(b.last, a.last);
    },
  );

  test('frameIndex counts the frames drawn, from zero', () {
    final device = CpuDevice(
      width: kParityWidth,
      height: kParityHeight,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final built = buildParityScene(device, which: ParityScene.values.first);
    expect(renderer.frameIndex, 0);
    for (var i = 1; i <= 3; i++) {
      renderer.render(
        width: kParityWidth,
        height: kParityHeight,
        scene: built.scene,
        views: <RenderView>[RenderView(camera: built.camera)],
        settings: paritySettingsFor(ParityScene.values.first),
      );
      expect(renderer.frameIndex, i);
    }
  });

  for (final which in ParityScene.values) {
    test(
      'the ${which.name} fixture draws its third frame as its first',
      () async {
        final device = CpuDevice(
          width: kParityWidth,
          height: kParityHeight,
          shaders: CpuShaderLibrary(builtinCpuShaders()),
        );
        final renderer = Renderer.create(device: device);
        final built = buildParityScene(device, which: which);
        final first = await _draw(renderer, device, built, which);
        await _draw(renderer, device, built, which);
        final third = await _draw(renderer, device, built, which);
        expect(third, first);
      },
    );
  }
}
