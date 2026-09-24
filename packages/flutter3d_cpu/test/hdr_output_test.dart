/// The extended output: scene-referred, past one, on a device that can show
/// it; the SDR frame, byte for byte, everywhere else — `R9`.
///
///     dart test test/hdr_output_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 48;

({Float32List pixels, TextureFormat format}) _render({
  required bool hdrDevice,
  required OutputTransform transform,
}) {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
    hdrOutputFormats: hdrDevice
        ? const <TextureFormat>[TextureFormat.r16g16b16a16Float]
        : const <TextureFormat>[],
  );
  final camera = CameraNode()
    ..setPosition(0.0, 0.0, 3.0)
    ..lookAt(Vector3.zero());
  final scene = Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape().build()),
        Material(baseColor: Vector4(1.0, 1.0, 1.0, 1.0)),
      ),
    )
    ..add(LightNode(intensity: 12.0)..setRotationYawPitchRoll(0.0, -0.2, 0.0))
    ..add(camera);
  final result = Renderer.create(device: device).render(
    width: _size,
    height: _size,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
    settings: RenderSettings(
      bloom: const BloomSettings(enabled: false),
      outputTransform: transform,
    ),
  );
  return (
    pixels: device.readHdrPixels(result.frame),
    format: result.frame.format,
  );
}

double _brightest(Float32List pixels) {
  var most = 0.0;
  for (var i = 0; i < pixels.length; i += 4) {
    if (pixels[i] > most) most = pixels[i];
  }
  return most;
}

void main() {
  test('asked for on an SDR device, it is the SDR frame', () {
    final sdr = _render(hdrDevice: false, transform: OutputTransform.sdr);
    final asked = _render(
      hdrDevice: false,
      transform: OutputTransform.extendedSrgb,
    );
    expect(asked.format, sdr.format);
    expect(asked.pixels, sdr.pixels);
  });

  test('on an HDR device the SDR branch is still the frame it was', () {
    final plain = _render(hdrDevice: false, transform: OutputTransform.sdr);
    final onHdr = _render(hdrDevice: true, transform: OutputTransform.sdr);
    expect(onHdr.pixels, plain.pixels);
  });

  test('extended, a lit highlight goes past white in a float frame', () {
    final sdr = _render(hdrDevice: true, transform: OutputTransform.sdr);
    final extended = _render(
      hdrDevice: true,
      transform: OutputTransform.extendedSrgb,
    );
    expect(extended.format, TextureFormat.r16g16b16a16Float);
    // The dither may lift white by a fraction of a step.
    expect(_brightest(sdr.pixels), lessThan(1.01));
    // Mutation: leave the curve on under the extended output. The highlight
    // is compressed back under one.
    expect(_brightest(extended.pixels), greaterThan(1.0));
  });
}
