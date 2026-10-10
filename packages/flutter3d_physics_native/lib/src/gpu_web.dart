/// The GPU passes in the browser: none yet — P9, phase 12.
///
/// The browser's WebGPU is not reached from here; [NativeGpu.open] is null,
/// and the CPU systems — [NativeParticles], [NativeDebris], [NativeCloth],
/// [NativeFluid] — stand in, as on a machine with no GPU.
library;

import 'gpu_unavailable.dart';
import 'native_cloth.dart';
import 'native_debris.dart';
import 'native_fluid.dart';
import 'native_particles.dart';

/// A GPU: never one in the browser.
final class NativeGpu {
  NativeGpu._();

  /// Throws [GpuUnavailable]: there is no GPU library in the browser.
  static NativeGpu open() => throw const GpuUnavailable(
    'there is no GPU library in the browser; the passes run on the CPU',
  );

  String get adapterName => throw _none;
  GpuParticles particles(int capacity) => throw _none;
  GpuDebris debris(int capacity) => throw _none;
  GpuCloth cloth(ClothMesh mesh) => throw _none;
  GpuFluid fluid(int capacity, double spacing) => throw _none;
  void dispose() {}
}

final UnsupportedError _none = UnsupportedError('no GPU passes in the browser');

/// Never made in the browser: [NativeGpu.open] is null.
abstract final class GpuParticles with NativeParticleCloud {}

/// Never made in the browser: [NativeGpu.open] is null.
abstract final class GpuDebris with DebrisSystem {}

/// Never made in the browser: [NativeGpu.open] is null.
abstract final class GpuCloth with ClothSystem {}

/// Never made in the browser: [NativeGpu.open] is null.
abstract final class GpuFluid with FluidSystem {}
