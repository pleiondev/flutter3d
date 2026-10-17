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
/// the engine, and `tool/structure.dart`'s "the hardware layer names no
/// graphics API" rule says so for the layer below. So the caller makes the
/// renderer, from three values it no longer has to spell.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'flutter3d_cpu.dart';
import 'src/cpu_device.dart' as device show standInForGpu;
import 'src/cpu_shaders_builtin.dart' show UnlitShader;

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
    );

/// What [cpuTestDevice] hands a test: a software device and the two fallback
/// textures a renderer made on it asks for.
final class CpuTestKit {
  /// [device], with [albedo] and [normal] made on it.
  const CpuTestKit({
    required this.device,
    required this.albedo,
    required this.normal,
  });

  /// The software device, with the builtin shaders.
  final CpuDevice device;

  /// A one-pixel white texture, a renderer's fallback albedo.
  final TextureHandle albedo;

  /// A one-pixel flat normal in tangent space, a renderer's fallback normal.
  final TextureHandle normal;

  @override
  bool operator ==(Object other) =>
      other is CpuTestKit &&
      other.device == device &&
      other.albedo == albedo &&
      other.normal == normal;

  @override
  int get hashCode => Object.hash(device, albedo, normal);

  @override
  String toString() => 'CpuTestKit($device)';
}

/// A [CpuDevice] with the builtin shaders, and the fallbacks a renderer needs.
///
/// [width] and [height] default to something small enough that a software frame
/// is cheap and large enough that a shape has an inside: every caller that had
/// its own copy of this chose between 64×48 and 240×160.
CpuTestKit cpuTestDevice({int width = 96, int height = 72}) {
  final device = CpuDevice(
    width: width,
    height: height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  return CpuTestKit(
    device: device,
    // White, so a material's own colour is what reaches the target.
    albedo: texelOn(device, <int>[255, 255, 255, 255]),
    // Flat in tangent space: (0, 0, 1) encoded, which is the normal of a
    // surface with no bumps on it.
    normal: texelOn(device, <int>[128, 128, 255, 255]),
  );
}

/// An unlit stage, for a test that hands the software rasteriser a
/// material stage the engine does not ship (a game's `Liquid`) and wants it
/// drawn in its base colour: `'Liquid': cpuUnlitStage`.
const CpuStage cpuUnlitStage = CpuStage.fragment(UnlitShader());

/// A [cpuComputeDevice] standing in for a GPU — since 1.0.0-rc.1, in place
/// of `CpuDevice(standInForGpu: true)` and `cpuComputeDevice(standInForGpu:
/// true)`.
///
/// It answers `isSoftware` false, so the hardware layer places a workload
/// with host code of its own on it as on a GPU, rather than leaving it to
/// that host code: how a simulation's kernels are checked against its own
/// CPU step without a GPU. Configured by the test, never asked for by the
/// work.
CpuDevice cpuComputeDeviceStandingInForGpu() =>
    device.standInForGpu(cpuComputeDevice());
