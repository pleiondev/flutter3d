/// A normal map with two channels: x and y stored, z left to the reader.
///
///     dart test test/two_channel_normal_test.dart
///
/// BC5 and RG8 sample as (x, y, 0, 1). Read as an RGB map, the blue zero is
/// z = -1 and the normal points into the surface. The oracle is the same map
/// written with all three channels, z computed on the CPU: the two-channel map
/// has to light the plane as that one does, to within the rounding of a byte.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

const int _size = 32;

/// Four texels leaning four ways, as (x, y) bytes.
const List<List<int>> _leans = <List<int>>[
  <int>[220, 128],
  <int>[128, 220],
  <int>[40, 150],
  <int>[150, 40],
];

TextureHandle _twoChannel(CpuDevice device) => device.createTextureFromPixels(
  width: 2,
  height: 2,
  format: TextureFormat.r8g8UNormInt,
  pixels: ByteData.sublistView(
    Uint8List.fromList(<int>[for (final lean in _leans) ...lean]),
  ),
)!;

TextureHandle _threeChannel(CpuDevice device) => device.createTextureFromPixels(
  width: 2,
  height: 2,
  format: TextureFormat.r8g8b8a8UNormInt,
  pixels: ByteData.sublistView(
    Uint8List.fromList(<int>[
      for (final [x, y] in _leans) ...<int>[x, y, _zByte(x, y), 255],
    ]),
  ),
)!;

/// The blue byte a three-channel map stores for the unit normal whose x and
/// y are the bytes [x] and [y].
int _zByte(int x, int y) {
  final nx = x / 255.0 * 2.0 - 1.0;
  final ny = y / 255.0 * 2.0 - 1.0;
  final nz = math.sqrt(math.max(1.0 - nx * nx - ny * ny, 0.0));
  return ((nz * 0.5 + 0.5) * 255.0).round();
}

/// The HDR frame of a lit two-metre plane seen from straight above, with
/// [normal] as its normal map.
Float32List _render(TextureHandle Function(CpuDevice device) normal) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 2.0, 0.0)
    ..lookAt(Vector3.zero(), up: Vector3(0.0, 0.0, -1.0));
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(
          device,
          const PlaneShape(width: 2.0, depth: 2.0).build(),
        ),
        Material(
          normal: normal(device),
          normalSampler: SamplerOptions.nearestClamp,
          roughness: 0.7,
        ),
      ),
    )
    ..add(camera)
    ..add(LightNode(intensity: 3.0)..setRotationYawPitchRoll(0.4, -1.0, 0.0))
    ..ambientIntensity = 0.25;
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
    ),
  );
  return device.readHdrPixels(result.frame);
}

double _largestDifference(Float32List a, Float32List b) {
  var largest = 0.0;
  for (var i = 0; i < a.length; i++) {
    largest = math.max(largest, (a[i] - b[i]).abs());
  }
  return largest;
}

void main() {
  test('a two-channel normal map lights as its three-channel twin', () {
    final twoChannel = _render(_twoChannel);
    final threeChannel = _render(_threeChannel);
    // The plane with no map at all, to show the relief is really there.
    final flat = _render(
      (device) => device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(
          Uint8List.fromList(<int>[128, 128, 255, 255]),
        ),
      )!,
    );

    // Mutation: leave `emissive.w` at zero in the encoder, or read
    // `texel.z * 2 - 1` regardless in `applyNormalMap`, and the RG map's
    // normals point into the plane: the first expectation fails by far more
    // than a byte's rounding.
    expect(_largestDifference(twoChannel, threeChannel), lessThan(0.02));
    expect(_largestDifference(threeChannel, flat), greaterThan(0.1));
  });
}
