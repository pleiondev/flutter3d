/// The software backend, for running the demo without a GPU.
///
/// Not a platform choice like the other two — every platform has a CPU. It is
/// selected explicitly:
///
///     flutter run -d macos -t lib/main.dart --dart-define=cpuBackend=true
///
/// Which makes it the one case where the application really does pick a backend
/// at build time rather than being handed whichever one this target has. Worth
/// having, because it is the only way to run the whole demo — every lighting
/// model, shadows, post, particles — through an implementation that shares
/// nothing with the hardware ones, and a demo is a far broader test than a
/// fixture.
library;

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'example_stripes_cpu.dart';

/// Whether this build was asked for the software backend.
const bool kUseCpuBackend = bool.fromEnvironment('cpuBackend');

/// The engine's stages and the example's own, which is how a look in a
/// loadable bundle reaches the backend that compiles nothing: the bundle
/// names `ExampleStripes`, and this is the Dart that answers to it.
GraphicsDevice createCpuBackend({required int width, required int height}) =>
    CpuDevice(
      width: width,
      height: height,
      shaders: CpuShaderLibrary(<String, CpuStage>{
        ...builtinCpuShaders(),
        'ExampleStripes': const CpuStage.fragment(ExampleStripesShader()),
      }),
    );
