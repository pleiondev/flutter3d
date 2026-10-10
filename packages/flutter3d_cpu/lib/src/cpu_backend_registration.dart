/// The software rasteriser as a backend an engine can open.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'cpu_device.dart';
import 'cpu_shaders_builtin.dart';

/// Adds the software rasteriser to [registry] as its fallback: the backend
/// still standing when no GPU backend starts, and the one a test opens.
///
/// [materialCompiler] is what the device compiles a bundle's material-language
/// stages with (`P8`); without one, a bundle carrying them is refused at
/// load. The registration takes it out again. Since 1.0 it is added to the
/// engine's own registry rather than to a global one (it was
/// `ensureCpuBackendRegistered`).
///
/// **And the CPU placement of compute, since 1.0**: a one-texel device
/// added with `DeviceRegistry.addComputeDevice` as [ComputePlacement.cpu],
/// so a frame drawn on a device without compute still runs its compute
/// steps, the kernels translated to Dart. The one registration takes both
/// out again.
Registration registerCpuBackend(
  DeviceRegistry registry, {
  CpuMaterialCompiler? materialCompiler,
}) {
  final backend = registry.addBackend(
    'the software rasteriser',
    ({required int width, required int height}) async => CpuDevice(
      width: width,
      height: height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
      materialCompiler: materialCompiler,
    ),
    asFallback: true,
  );
  final compute = registry.addComputeDevice(
    ComputePlacement.cpu,
    'the software rasteriser',
    () async => cpuComputeDevice(),
  );
  return Registration(() {
    compute.cancel();
    backend.cancel();
  });
}

/// A software rasteriser for running compute and nothing else — the
/// [ComputePlacement.cpu] executor: one texel, the engine's own stages, and
/// every kernel a bundle's kernel section carries translated to Dart.
CpuDevice cpuComputeDevice() => CpuDevice(
  width: 1,
  height: 1,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);
