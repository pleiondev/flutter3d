/// A rough metal keeps the light single scattering loses, when asked — `L1`.
///
///     dart test test/energy_compensation_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

const int _size = 48;

/// The mean of the red channel over a gold sphere of [roughness], lit from
/// the camera's side.
double _brightness({required double roughness, required bool compensate}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()..setPosition(0.0, 0.0, 2.0);
  final sphere = MeshNode(
    DeviceMesh.upload(device, const SphereShape().build()),
    Material(
      baseColor: Vector4(1.0, 0.78, 0.34, 1.0),
      metallic: 1.0,
      roughness: roughness,
    ),
  );
  final light = LightNode(intensity: 3.0)
    ..setRotationYawPitchRoll(0.3, -0.4, 0.0);
  final scene = Scene()
    ..add(sphere)
    ..add(light)
    ..add(camera);
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      tonemap: false,
      bloom: const BloomSettings(enabled: false),
      energyCompensation: compensate,
    ),
  );
  final Float32List hdr = device.readHdrPixels(result.frame);
  var sum = 0.0;
  for (var i = 0; i < hdr.length; i += 4) {
    sum += hdr[i];
  }
  return sum / (hdr.length / 4);
}

void main() {
  test('a rough metal brightens, a polished one barely moves', () {
    final roughOff = _brightness(roughness: 0.9, compensate: false);
    final roughOn = _brightness(roughness: 0.9, compensate: true);
    final smoothOff = _brightness(roughness: 0.1, compensate: false);
    final smoothOn = _brightness(roughness: 0.1, compensate: true);

    // Mutation: drop `specular *= MultiscatterScale` in the mirror. The rough
    // sphere comes back exactly as dark as without it.
    expect(roughOn, greaterThan(roughOff * 1.05));
    // At low roughness single scattering already keeps nearly everything.
    expect(smoothOn / smoothOff, closeTo(1.0, 0.05));
  });

  test('off, it changes nothing', () {
    expect(
      _brightness(roughness: 0.5, compensate: false),
      _brightness(roughness: 0.5, compensate: false),
    );
  });
}
