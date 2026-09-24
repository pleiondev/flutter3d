/// A display transform is read in place of the tone curve — `L2`.
///
///     dart test test/display_transform_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

const int _size = 16;

double _encode(double x) => x <= 0.0031308
    ? x * 12.92
    : 1.055 * math.pow(x, 1.0 / 2.4).toDouble() - 0.055;

/// The centre of a frame filled by an unlit card whose light is [linear].
double _centre(RenderSettings settings, {double linear = 0.18}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  // The tint is authored in sRGB and decoded by the shader, so this is the
  // sRGB value whose linear light is [linear].
  final authored = _encode(linear);
  final card =
      MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          Material(
            lighting: LightingModel.unlit,
            baseColor: Vector4(authored, authored, authored, 1.0),
          ),
        )
        ..setPosition(0.0, 0.0, -1.0)
        ..setScale(4.0, 4.0, 0.1);
  final camera = CameraNode();
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: Scene()
      ..add(card)
      ..add(camera),
    views: <RenderView>[RenderView(camera: camera)],
    settings: settings,
  );
  final Float32List hdr = device.readHdrPixels(result.frame);
  return hdr[(_size ~/ 2 * _size + _size ~/ 2) * 4];
}

RenderSettings _base() => const RenderSettings(
  exposure: 1.0,
  bloom: BloomSettings(enabled: false),
  look: LookSettings(dither: 0.0),
);

void main() {
  test('ACES 2.0 puts mid grey at a tenth of the display', () {
    // Mutation: return `tonemapBy` for curve 6 in the composite's mirror.
    // Neutral leaves 0.18 near 0.18, well above a tenth.
    final grey = _centre(_base().copyWith(tonemapCurve: TonemapCurve.aces2));
    expect(grey, closeTo(_encode(0.1), 0.02));
  });

  test('a table of its own wins over the curve', () {
    final device = CpuDevice(
      width: 4,
      height: 2,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    // Two entries per axis, all half grey: whatever comes in, 0.5 goes out.
    final half = ByteData(4 * 2 * 16);
    for (var i = 0; i < 4 * 2 * 4; i++) {
      half.setFloat32(i * 4, i % 4 == 3 ? 1.0 : 0.5, Endian.little);
    }
    final table = device.createTextureFromPixels(
      width: 4,
      height: 2,
      format: TextureFormat.r32g32b32a32Float,
      pixels: half,
    )!;
    // The table belongs to another device; the software rasteriser samples
    // any `CpuTexture`, which is what makes this cheap to set up.
    final value = _centre(
      _base().copyWith(
        look: LookSettings(
          dither: 0.0,
          displayTransform: DisplayTransform(texture: table, size: 2),
        ),
      ),
      linear: 3.0,
    );
    expect(value, closeTo(_encode(0.5), 0.01));
  });

  test('with the tone map off, neither is read', () {
    final grey = _centre(
      _base().copyWith(tonemap: false, tonemapCurve: TonemapCurve.aces2),
    );
    expect(grey, closeTo(_encode(0.18), 0.02));
  });
}
