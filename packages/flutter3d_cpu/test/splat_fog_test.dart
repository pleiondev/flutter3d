/// A splat cloud fades into fog like everything else in the scene.
///
///     dart test test/splat_fog_test.dart
///
/// Both splat stages read `FogInfo`, and the contributor never bound it. An
/// unbound block reads as zeros and a density of zero is no fog, so a cloud
/// stayed at full colour in the murk on every backend. WebGL2 named the block
/// at the draw; the others drew the unfogged cloud without a word.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 32;
const int _height = 24;

/// One opaque red splat at the origin, seen from five metres, as the centre
/// pixel's colour.
List<double> _centre(SplatComposite composite, FogSettings fog) =>
    _seen(composite, fog);

/// One opaque red splat at [at], seen by [camera] (from five metres along +z
/// by default), as the colour of [pixel] (the centre by default).
List<double> _seen(
  SplatComposite composite,
  FogSettings fog, {
  CameraNode? camera,
  Vector3? at,
  (int, int) pixel = (_width ~/ 2, _height ~/ 2),
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final view =
      camera ??
      (CameraNode()
        ..setPosition(0.0, 0.0, 5.0)
        ..lookAt(Vector3.zero()));
  final scene = Scene()
    ..ambientIntensity = 0.0
    ..add(view);
  final cloud = SplatCloud(
    centres: Float32List.fromList(<double>[at?.x ?? 0, at?.y ?? 0, at?.z ?? 0]),
    colours: Float32List.fromList(<double>[1.0, 0.0, 0.0, 1.0]),
    scales: Float32List.fromList(<double>[1.0, 1.0, 1.0]),
    rotations: Float32List.fromList(<double>[0.0, 0.0, 0.0, 1.0]),
  );
  final renderer = Renderer.create(device: device)
    ..addContributor(SplatContributor(cloud, composite: composite));
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <RenderView>[
      RenderView(camera: view, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      fog: fog,
    ),
  );
  final pixels = device.readHdrPixels(result.frame);
  final index = (pixel.$2 * _width + pixel.$1) * 4;
  return pixels.sublist(index, index + 3);
}

void main() {
  for (final composite in <SplatComposite>[
    SplatComposite.sorted,
    SplatComposite.hashed,
  ]) {
    test('a ${composite.name} splat takes the fog colour at a distance', () {
      // Mutation: drop the FogInfo binding from SplatContributor.encode. The
      // fogged centre comes back red, the same as the clear one.
      final clear = _centre(composite, const FogSettings());
      final fogged = _centre(
        composite,
        FogSettings(color: Vector3(0.0, 0.0, 1.0), density: 2.0),
      );
      expect(clear[0], greaterThan(0.5), reason: 'the splat is not there');
      expect(clear[2], lessThan(0.05));
      // Five metres at two per metre leaves e^-10 of the splat's own colour.
      expect(fogged[0], lessThan(0.05));
      expect(fogged[2], greaterThan(0.5));
    });
  }

  test('through an orthographic lens a splat fogs by its depth', () {
    // `P7`: three metres to the side of an orthographic camera five metres
    // back, the splat is five metres deep and 5.8 from the eye's point. With
    // blue fog over black, red over red and blue is the share the fog left.
    //
    // Mutation: fog by distance from the eye whatever the lens, as before,
    // or leave `projection` unbound in `SplatContributor` — e^(−0.3 × 5.8)
    // is 0.17, not e^(−1.5), 0.22.
    final camera = CameraNode()
      ..projection = const OrthographicProjection(height: 10.0, far: 100.0)
      ..setPosition(0.0, 0.0, 5.0)
      ..lookAt(Vector3.zero());
    // 10 m over 24 rows is 2.4 rows a metre, the same across: three metres
    // right of the middle is column 16 + 7.
    final seen = _seen(
      SplatComposite.sorted,
      FogSettings(color: Vector3(0.0, 0.0, 1.0), density: 0.3),
      camera: camera,
      at: Vector3(3.0, 0.0, 0.0),
      pixel: (_width ~/ 2 + 7, _height ~/ 2),
    );
    // The composite encodes; the share is one of light.
    double linear(double encoded) => encoded <= 0.04045
        ? encoded / 12.92
        : math.pow((encoded + 0.055) / 1.055, 2.4).toDouble();
    final (red, blue) = (linear(seen[0]), linear(seen[2]));
    expect(red + blue, greaterThan(0.1), reason: 'no splat there');
    expect(red / (red + blue), closeTo(math.exp(-1.5), 0.02));
  });
}
