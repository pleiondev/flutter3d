/// A software device set up the way a test wants one, and the two fallback
/// textures every renderer asks for.
///
///     import 'package:flutter3d_cpu/testing.dart';
///
///     final it = cpuTestDevice(width: 96, height: 72);
///     final renderer = Renderer.create(
///       device: it.device,
///       fallbackAlbedo: it.albedo,
///       fallbackNormal: it.normal,
///     );
///
/// **Fifteen lines that were in eight files**: five tests in this package, the
/// frame tests of three applications, and `tool/dump_fixture.dart`. Always the
/// same device, always the same white albedo and the same flat normal, written
/// out again each time — and a fallback normal typed `(128, 128, 255)` in seven
/// places is a fallback normal that will be typed `(128, 255, 128)` in the
/// eighth.
///
/// ## Why it stops where it does
///
/// It does not build the `Renderer`, and that is not laziness. This package must
/// not depend on `flutter3d`: a backend that could not be compiled without the
/// engine would not be an implementation of an interface, it would be a part of
/// the engine, and `no_backend_test.dart` in `flutter3d_hardware` says so for
/// the layer below. So the caller makes the renderer, from three values it no
/// longer has to spell.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'flutter3d_cpu.dart';

/// A one-pixel texture of [rgba], on [device].
///
/// The shape every fallback in this engine has. Public because a test that wants
/// a third one — a flat metallic-roughness, a black emissive — should not have
/// to write the four lines out to get it.
TextureHandle texelOn(CpuDevice device, List<int> rgba) =>
    device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
    )!;

/// A [CpuDevice] with the builtin shaders, and the fallbacks a renderer needs.
///
/// [width] and [height] default to something small enough that a software frame
/// is cheap and large enough that a shape has an inside: every caller that had
/// its own copy of this chose between 64×48 and 240×160.
({CpuDevice device, TextureHandle albedo, TextureHandle normal}) cpuTestDevice({
  int width = 96,
  int height = 72,
}) {
  final device = CpuDevice(
    width: width,
    height: height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  return (
    device: device,
    // White, so a material's own colour is what reaches the target.
    albedo: texelOn(device, <int>[255, 255, 255, 255]),
    // Flat in tangent space: (0, 0, 1) encoded, which is the normal of a
    // surface with no bumps on it.
    normal: texelOn(device, <int>[128, 128, 255, 255]),
  );
}
