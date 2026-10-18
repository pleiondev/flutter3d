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
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 32;
const int _height = 24;

/// One opaque red splat at the origin, seen from five metres — or from
/// [eye] — as the centre pixel's colour.
List<double> _center(
  SplatComposite composite,
  FogSettings fog, {
  Vector3? eye,
}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()
    ..setPositionFrom(eye ?? Vector3(0.0, 0.0, 5.0))
    ..lookAt(Vector3.zero());
  final scene = Scene()
    ..ambientIntensity = 0.0
    ..add(camera);
  final cloud = SplatCloud(
    centers: Float32List(3),
    colors: Float32List.fromList(<double>[1.0, 0.0, 0.0, 1.0]),
    scales: Float32List.fromList(<double>[1.0, 1.0, 1.0]),
    rotations: Float32List.fromList(<double>[0.0, 0.0, 0.0, 1.0]),
  );
  final renderer = Renderer.create(device: device)
    ..renderSteps.addContributor(SplatContributor(cloud, composite: composite));
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: scene,
    views: <CameraView>[
      CameraView(
        camera: camera,
        clearColor: LinearColor.fromSrgb(0.0, 0.0, 0.0, 1.0),
      ),
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
      final clear = _center(composite, const FogSettings());
      final fogged = _center(
        composite,
        FogSettings(color: LinearColor(0.0, 0.0, 1.0), density: 2.0),
      );
      expect(clear[0], greaterThan(0.5), reason: 'the splat is not there');
      expect(clear[2], lessThan(0.05));
      // Five metres at two per metre leaves e^-10 of the splat's own colour.
      expect(fogged[0], lessThan(0.05));
      expect(fogged[2], greaterThan(0.5));
    });

    test('in a height fog a ${composite.name} splat above the eye fogs as '
        'the thinner air there does', () {
      // Mutation: leave the falloff out of `fogTransmittance` (or out of
      // `eye.w` in SplatContributor), and the splat fogs at the camera's
      // density the whole way up.
      final eye = Vector3(0.0, -4.0, 5.0);
      final fog = FogSettings(
        color: LinearColor.black,
        density: 0.4,
        heightFalloff: 0.5,
        baseHeight: -4.0,
      );
      double linear(double encoded) => encoded <= 0.04045
          ? encoded / 12.92
          : math.pow((encoded + 0.055) / 1.055, 2.4).toDouble();
      final clear = linear(
        _center(composite, const FogSettings(), eye: eye)[0],
      );
      final fogged = linear(_center(composite, fog, eye: eye)[0]);
      final k = 0.5 * 4.0;
      final mean = (1.0 - math.exp(-k)) / k;
      expect(clear, greaterThan(0.5), reason: 'the splat is not there');
      expect(fogged / clear, closeTo(math.exp(-0.4 * mean * eye.length), 0.02));
    });

    test('through an orthographic camera a ${composite.name} splat fogs by '
        'depth, not by distance — P7', () {
      // Two splats at the same depth, one on the axis and one four metres
      // off it. The air between each and the eye's plane is the same five
      // metres, so the fog must be too.
      //
      // Mutation: measure `FogDistance` from the eye's position, as the
      // stages did, and the one off the axis is six and a half metres away
      // and the bluer of the two.
      final device = CpuDevice(
        width: _width,
        height: _height,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      final camera = CameraNode()
        ..projection = const OrthographicProjection(height: 12.0)
        ..setPosition(0.0, 0.0, 5.0)
        ..lookAt(Vector3.zero());
      final scene = Scene()
        ..ambientIntensity = 0.0
        ..add(camera);
      final cloud = SplatCloud(
        centers: Float32List.fromList(<double>[0.0, 0.0, 0.0, 4.0, 0.0, 0.0]),
        colors: Float32List.fromList(<double>[
          1.0, 0.0, 0.0, 1.0, //
          1.0, 0.0, 0.0, 1.0,
        ]),
        scales: Float32List.fromList(<double>[0.6, 0.6, 0.6, 0.6, 0.6, 0.6]),
        rotations: Float32List.fromList(<double>[
          0.0, 0.0, 0.0, 1.0, //
          0.0, 0.0, 0.0, 1.0,
        ]),
      );
      final renderer = Renderer.create(device: device)
        ..renderSteps.addContributor(
          SplatContributor(cloud, composite: composite),
        );
      final result = renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: <CameraView>[
          CameraView(
            camera: camera,
            clearColor: LinearColor.fromSrgb(0.0, 0.0, 0.0, 1.0),
          ),
        ],
        settings: RenderSettings(
          tonemap: false,
          bloom: const BloomSettings(enabled: false),
          fog: FogSettings(color: LinearColor(0.0, 0.0, 1.0), density: 0.2),
        ),
      );
      final pixels = device.readHdrPixels(result.frame);
      // Two pixels to the metre: the axis between columns 15 and 16, four
      // metres off it between 23 and 24. The brightest pixel of each, because
      // a hashed splat keeps or drops each pixel at random and the ones it
      // keeps carry its colour, fogged.
      double brightest(int from, int c) => <double>[
        for (var x = from; x < from + 8; x++)
          pixels[((_height ~/ 2) * _width + x) * 4 + c],
      ].reduce(math.max);
      final onAxis = brightest(12, 0);
      final offAxis = brightest(20, 0);
      expect(onAxis, greaterThan(0.1), reason: 'no splat on the axis');
      expect(offAxis, greaterThan(0.1), reason: 'no splat off it');
      expect(offAxis, closeTo(onAxis, 0.02));
      expect(brightest(20, 2), closeTo(brightest(12, 2), 0.02));
    });
  }
}
