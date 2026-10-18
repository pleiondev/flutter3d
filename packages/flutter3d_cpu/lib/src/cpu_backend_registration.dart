/// The software rasteriser as a backend an engine can open.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/backend.dart' show MaterialCompilerRegistry;

import 'cpu_device.dart';
import 'cpu_section_compiler.dart';
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
///
/// **And its material compiler, since 1.0** (D26): given [compilers], the
/// registry `RuntimeShaders` and a build consult by backend, the
/// [CpuSectionCompiler] is registered there too, and taken out with the
/// rest.
Registration registerCpuBackend(
  DeviceRegistry registry, {
  CpuMaterialCompiler? materialCompiler,
  MaterialCompilerRegistry? compilers,
}) {
  final backend = registry.addBackend(
    'the software rasteriser',
    (DeviceRequest request) async => CpuDevice(
      width: request.width,
      height: request.height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
      materialCompiler: materialCompiler,
    ),
    asFallback: true,
  );
  final compute = registry.addComputeDevice(
    ComputePlacement.cpu,
    'the software rasteriser',
    (DeviceRequest _) async => cpuComputeDevice(),
  );
  final compiler = compilers?.register(const CpuSectionCompiler());
  return Registration(() {
    compiler?.cancel();
    compute.cancel();
    backend.cancel();
  });
}

/// A software rasteriser for running compute and nothing else — the
/// [ComputePlacement.cpu] executor: one texel, the engine's own stages, and
/// every kernel a bundle's kernel section carries translated to Dart.
///
/// **Breaking in 1.0.0-rc.1: no `standInForGpu`.** A test that wants the
/// device to stand in for a GPU asks `cpuComputeDeviceStandingInForGpu`
/// from `package:flutter3d_cpu/testing.dart`.
CpuDevice cpuComputeDevice() => CpuDevice(
  width: 1,
  height: 1,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);
