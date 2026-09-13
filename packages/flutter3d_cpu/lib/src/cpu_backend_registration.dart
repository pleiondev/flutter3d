/// Registers this backend's *opener* with `flutter3d_hardware`'s device
/// registry — the presenter half stays with whoever depends on Flutter,
/// since this package does not.
///
/// See `flutter3d_impeller/src/gpu_backend_registration.dart` for why this
/// is a guarded function rather than code that runs at library load, and
/// `flutter3d_app/src/cpu_frame_presenter.dart` for where `CpuFrame` — and
/// this backend's presenter registration — moved once this package went
/// flat (mcp-02n): a package that resolves without the Flutter SDK cannot
/// also build a Flutter `Widget`.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'cpu_device.dart';
import 'cpu_shaders_builtin.dart';

bool _registered = false;

/// Registers [CpuDevice] as the native fallback opener, once.
///
/// A fallback, not a preferred opener: the software rasteriser is where a
/// native build lands when nothing faster starts, not a backend a build
/// prefers.
void ensureCpuBackendRegistered() {
  if (_registered) return;
  _registered = true;
  registerBackendOpener(
    'the software rasteriser',
    ({required int width, required int height}) async => CpuDevice(
      width: width,
      height: height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    ),
    asFallback: true,
  );
}
