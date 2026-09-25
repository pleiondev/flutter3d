/// A splat cloud fades into fog like everything else in the scene.
///
///     dart test test/splat_fog_test.dart
///
/// Both splat stages read `FogInfo`, and the contributor never bound it. An
/// unbound block reads as zeros and a density of zero is no fog, so a cloud
/// stayed at full colour in the murk on every backend. WebGL2 named the block
/// at the draw; the others drew the unfogged cloud without a word.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 32;
const int _height = 24;

/// One opaque red splat at the origin, seen from five metres, as the centre
/// pixel's colour.
List<double> _centre(SplatComposite composite, FogSettings fog) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 0.0, 5.0)
    ..lookAt(Vector3.zero());
  final scene = Scene()
    ..ambientIntensity = 0.0
    ..add(camera);
  final cloud = SplatCloud(
    centres: Float32List(3),
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
      RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      fog: fog,
    ),
  );
  final pixels = device.readHdrPixels(result.frame);
  final at = ((_height ~/ 2) * _width + _width ~/ 2) * 4;
  return pixels.sublist(at, at + 3);
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
}
