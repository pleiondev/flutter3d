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
  ParityScene which,
) async {
  final frame = renderer.render(
    width: kParityWidth,
    height: kParityHeight,
    scene: built.scene,
    views: <RenderView>[RenderView(camera: built.camera)],
    settings: paritySettingsFor(which),
  );
  return (await device.readPixels(frame.frame))!.buffer.asUint8List();
}

void main() {
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
