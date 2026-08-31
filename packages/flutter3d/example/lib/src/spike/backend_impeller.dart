/// The Impeller backend, on the platforms that have it.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';

import 'backend_cpu.dart';

/// Builds the device this application draws through.
///
/// [width] and [height] are ignored here: Impeller renders into textures the
/// engine allocates and Flutter composites the result, so there is no surface
/// to size. The WebGL implementation needs them, because there the surface is a
/// canvas it creates itself.
/// Asynchronous because loading the shader bundle is, since flutter_gpu 3.47.
/// The CPU path has nothing to wait for and says so by returning immediately;
/// the signature is shared with `backend_web.dart` because a conditional import
/// picks between them, so both answer a `Future` whether they need one or not.
Future<GraphicsDevice> createBackend({
  required int width,
  required int height,
}) async =>
    kUseCpuBackend
        ? createCpuBackend(width: width, height: height)
        : await GpuRenderBackend.create();

/// What to call this build in a diagnostic.
String get kBackendName => kUseCpuBackend ? 'cpu' : 'impeller';
