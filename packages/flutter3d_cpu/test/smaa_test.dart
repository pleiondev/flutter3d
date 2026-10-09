/// SMAA 1x smooths a staircase towards the edge it stands for — `P1`.
///
///     dart test test/smaa_test.dart
///
/// Against the coverage an 8×8 supersample gives, at both slopes and both
/// orientations: a share applied to the wrong side of an edge, or a pattern
/// read the wrong way up, makes the staircase worse rather than better, and
/// one tilt alone would not see it.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 96;
const int _height = 64;

/// A white card tilted by [roll] on black, [factor] times the size, through
/// [antiAlias]. Unlit, so the only thing to smooth is the silhouette.
Float32List _render({
  required double roll,
  AntiAliasSettings antiAlias = const AntiAliasSettings(),
  int factor = 1,
  bool tall = false,
}) {
  final width = _width * factor;
  final height = _height * factor;
  final device = CpuDevice(
    width: width,
    height: height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final card =
      MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          RenderMaterial(
            lighting: LightingModel.unlit,
            baseColor: LinearColor.fromSrgb(1.0, 1.0, 1.0, 1.0),
          ),
        )
        ..setPosition(0.0, -0.3, -3.0)
        ..setRotationYawPitchRoll(0.0, 0.0, roll)
        ..setScale(tall ? 1.4 : 6.0, tall ? 6.0 : 1.4, 0.05);
  final camera = CameraNode();
  final result = Renderer.create(device: device).render(
    width: width,
    height: height,
    scene: Scene()
      ..add(card)
      ..add(camera),
    views: <RenderView>[
      RenderView(camera: camera, clearColorSrgb: Vector4(0.0, 0.0, 0.0, 1.0)),
    ],
    settings: RenderSettings(
      bloom: const BloomSettings(enabled: false),
      look: const LookSettings(dither: 0.0),
      antiAlias: antiAlias,
    ),
  );
  return device.readHdrPixels(result.frame);
}

/// [big] box-filtered down by [factor]: the coverage each pixel should have.
Float32List _downsample(Float32List big, int factor) {
  final out = Float32List(_width * _height);
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      var sum = 0.0;
      for (var dy = 0; dy < factor; dy++) {
        for (var dx = 0; dx < factor; dx++) {
          sum +=
              big[((y * factor + dy) * _width * factor + x * factor + dx) * 4];
        }
      }
      out[y * _width + x] = sum / (factor * factor);
    }
  }
  return out;
}

/// The summed distance of [frame]'s red from [reference].
double _error(Float32List frame, Float32List reference) {
  var sum = 0.0;
  for (var i = 0; i < reference.length; i++) {
    sum += (frame[i * 4] - reference[i]).abs();
  }
  return sum;
}

const AntiAliasSettings _smaa = AntiAliasSettings(
  enabled: true,
  method: EdgeSmoothing.smaa,
);

void main() {
  for (final (name, roll, tall) in <(String, double, bool)>[
    ('a shallow edge rising', 0.07, false),
    ('a shallow edge falling', -0.07, false),
    ('a steep edge leaning right', 0.07, true),
    ('a steep edge leaning left', -0.07, true),
  ]) {
    test('$name comes out nearer its supersampled coverage', () {
      // Mutation: swap red and green in the table, or the near and far
      // codes, and the share goes to the wrong side of the edge — the error
      // grows past the hard edge's.
      final reference = _downsample(
        _render(roll: roll, factor: 8, tall: tall),
        8,
      );
      final hard = _error(_render(roll: roll, tall: tall), reference);
      final smoothed = _error(
        _render(roll: roll, antiAlias: _smaa, tall: tall),
        reference,
      );
      // ignore: avoid_print
      print('$name: hard $hard, SMAA $smoothed');
      expect(smoothed, lessThan(hard * 0.6));
    });
  }

  test('a picture with no edge comes back as it went in', () {
    final device = CpuDevice(
      width: 16,
      height: 16,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final camera = CameraNode();
    Float32List draw(AntiAliasSettings antiAlias) {
      final result = Renderer.create(device: device).render(
        width: 16,
        height: 16,
        scene: Scene()..add(camera),
        views: <RenderView>[
          RenderView(
            camera: camera,
            clearColorSrgb: Vector4(0.3, 0.5, 0.7, 1.0),
          ),
        ],
        settings: RenderSettings(
          bloom: const BloomSettings(enabled: false),
          look: const LookSettings(dither: 0.0),
          antiAlias: antiAlias,
        ),
      );
      return Float32List.fromList(device.readHdrPixels(result.frame));
    }

    expect(draw(_smaa), draw(const AntiAliasSettings()));
  });
}
