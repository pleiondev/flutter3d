/// Auto exposure, drawn: a dark room climbs to the ceiling and a bright one
/// falls to the floor, through the luminance pass, the readback and the meter.
///
///     flutter test test/auto_exposure_test.dart
///
/// The arithmetic is pinned by hand in `flutter3d/test/auto_exposure_test.dart`.
/// This is the other half: that `luminance.frag`'s transcription encodes what
/// `ExposureMeter` decodes, that the readback of the target reaches the
/// adapter, and that the composite exposes the *next* frame with the answer —
/// none of which a byte handed in by hand can show.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 64;

/// A wall filling the view, unlit, at [grey] — so every texel of the frame
/// carries one known value and the meter has exactly one thing to read.
({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) _room(
  double grey,
) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(size: Vector3(60.0, 60.0, 1.0)).build(),
        ),
        Material(
          name: 'wall',
          baseColor: Vector4(grey, grey, grey, 1.0),
          lighting: LightingModel.unlit,
        ),
        name: 'wall',
      )..setPosition(0.0, 0.0, -10.0),
    );
  final camera = CameraNode(
    projection: const PerspectiveProjection(
      fovYRadians: 1.0,
      near: 0.1,
      far: 100.0,
    ),
  );
  camera.lookAt(Vector3(0.0, 0.0, -1.0));
  scene.add(camera);
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
    camera: camera,
  );
}

Future<({FrameResult result, Uint8List pixels})> _draw(
  ({CpuDevice device, Renderer renderer, Scene scene, CameraNode camera}) it,
  RenderSettings settings,
) async {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[
      RenderView(camera: it.camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: settings,
  );
  final pixels = await it.device.readPixels(result.frame);
  // The readback of the luminance target is already complete on this backend,
  // and the meter runs on the microtask after it; let it.
  await pumpEventQueue();
  return (result: result, pixels: pixels!.buffer.asUint8List());
}

int _centre(Uint8List pixels) =>
    pixels[((_height ~/ 2) * _width + _width ~/ 2) * 4];

/// At once, so the frame after the first metered one is at the target
/// whatever the wall clock did between them.
const RenderSettings _instant = RenderSettings(
  autoExposure: AutoExposureSettings(
    enabled: true,
    speedUp: double.infinity,
    speedDown: double.infinity,
  ),
);

void main() {
  test('a dark room climbs to the ceiling by the second frame', () async {
    // Unlit at 0.02: five and a half stops under middle grey, which asks for
    // an exposure of nine, and the ceiling is eight. Frame one is composited
    // before anything has been metered, so it wears the setting; frame two
    // wears the answer. Mutation: encode linear luminance in the shader
    // rather than log — the wall meters as black, the target is still the
    // ceiling, and this passes; the bright test below is what catches that.
    final it = _room(0.02);
    final first = await _draw(it, _instant);
    expect(first.result.exposure, 1.6, reason: 'nothing metered yet');

    final second = await _draw(it, _instant);
    expect(second.result.exposure, _instant.autoExposure.maxExposure);
    expect(
      _centre(second.pixels),
      greaterThan(_centre(first.pixels)),
      reason: 'the exposure reached the picture, not only the counter',
    );
  });

  test('a bright room falls to the floor', () async {
    // Unlit white: zero stops, which asks for an exposure of the target
    // itself, 0.18, and the floor is 0.25. Mutation: swap the encoding's
    // sign, or drop the percentile band so the black surround is metered —
    // the exposure climbs instead.
    final it = _room(1.0);
    final first = await _draw(it, _instant);
    final second = await _draw(it, _instant);
    expect(second.result.exposure, _instant.autoExposure.minExposure);
    expect(_centre(second.pixels), lessThan(_centre(first.pixels)));
  });

  test('a finite rate approaches the ceiling one frame at a time', () async {
    // The wall clock between two renders here is a few milliseconds, so each
    // step is small — but it is a step in the right direction and never past
    // the ceiling. Mutation: step towards the unclamped target and the value
    // overshoots; step with the wrong sign and it falls.
    final it = _room(0.02);
    const settings = RenderSettings(
      autoExposure: AutoExposureSettings(enabled: true, speedUp: 3.0),
    );
    var previous = (await _draw(it, settings)).result.exposure;
    expect(previous, 1.6);
    for (var frame = 0; frame < 4; frame++) {
      final now = (await _draw(it, settings)).result.exposure;
      expect(now, greaterThanOrEqualTo(previous));
      expect(now, lessThanOrEqualTo(settings.autoExposure.maxExposure));
      previous = now;
    }
    expect(previous, greaterThan(1.6), reason: 'it never moved');
  });

  test('off, the picture is the bytes it was', () async {
    // Every golden rests on this. Mutation: run the luminance pass regardless
    // of the setting — it borrows a pooled target and the composite still
    // reads the setting, so even this passes; what fails is the frame's draw
    // count, which is why that is asserted too.
    final it = _room(0.5);
    final plain = await _draw(it, const RenderSettings());
    final stated = await _draw(
      it,
      const RenderSettings(autoExposure: AutoExposureSettings()),
    );
    expect(stated.pixels, equals(plain.pixels));
    expect(stated.result.drawCalls, plain.result.drawCalls);
    expect(stated.result.exposure, 1.6);
  });
}
