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
Registration registerCpuBackend(
  DeviceRegistry registry, {
  CpuMaterialCompiler? materialCompiler,
}) => registry.addBackend(
  'the software rasteriser',
  ({required int width, required int height}) async => CpuDevice(
    width: width,
    height: height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
    materialCompiler: materialCompiler,
  ),
  asFallback: true,
);
