/// The GPU passes in the browser: none yet — P9, phase 12.
///
/// The browser's WebGPU is not reached from here; [NativeGpu.open] is null,
/// and the CPU systems — [NativeParticles], [NativeDebris], [NativeCloth],
/// [NativeFluid] — stand in, as on a machine with no GPU.
library;

import 'native_cloth.dart';
import 'native_debris.dart';
import 'native_fluid.dart';
import 'native_particles.dart';

/// A GPU: never one in the browser.
final class NativeGpu {
  NativeGpu._();

  /// Null: there is no GPU library in the browser.
  static NativeGpu? open() => null;

  String get adapterName => throw _none;
  GpuParticles particles(int capacity) => throw _none;
  GpuDebris debris(int capacity) => throw _none;
  GpuCloth cloth(ClothMesh mesh) => throw _none;
  GpuFluid fluid(int capacity, double spacing) => throw _none;
  void dispose() {}
}

final UnsupportedError _none = UnsupportedError('no GPU passes in the browser');

/// Never made in the browser: [NativeGpu.open] is null.
abstract final class GpuParticles implements ParticleSystem {}

/// Never made in the browser: [NativeGpu.open] is null.
abstract final class GpuDebris implements DebrisSystem {}

/// Never made in the browser: [NativeGpu.open] is null.
abstract final class GpuCloth implements ClothSystem {}

/// Never made in the browser: [NativeGpu.open] is null.
abstract final class GpuFluid implements FluidSystem {}
