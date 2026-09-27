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

  test('the table reaches white where the ACES 2.0 curve does', () {
    // The SDR tonescale meets the display's peak at 128, 9.47 stops over
    // grey. A shaper that ended at +6 stops (11.5) clamped everything above
    // it to 0.92 of peak, about 246 of 255, so a sun and a lamp came out
    // the same flat grey short of white. Mutation: put the shaper back to
    // −10…+6 in `make_tables.dart`, `composite.frag` and its mirror.
    RenderSettings at(double linear) => _base().copyWith(
      tonemapCurve: TonemapCurve.aces2,
      exposure: linear / 0.18,
    );
    final bright = _centre(at(32.0));
    final brighter = _centre(at(80.0));
    final roof = _centre(at(160.0));
    expect(roof, greaterThan(0.995), reason: 'past the roof is white');
    expect(
      brighter - bright,
      greaterThan(0.005),
      reason: 'highlights keep rolling towards white rather than clamping',
    );
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
