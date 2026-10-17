/// Impeller as a backend an engine can open.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/backend.dart' show MaterialCompilerRegistry;

import 'gpu_device.dart';
import 'impeller_section_compiler.dart';

/// Adds Impeller to [registry] — preferred over anything added before it —
/// with the presenter that shows its frames. The registration takes both
/// out again. Since 1.0 it is added to the engine's own registry rather than
/// to a global one (it was `ensureGpuBackendRegistered`).
///
/// Given [compilers] (D26), the registry `RuntimeShaders` and a build find a
/// backend's material compiler in, the [ImpellerSectionCompiler] is
/// registered there as well — which is how a data plugin's material on this
/// backend is refused by name rather than tried — and taken out with the
/// rest.
Registration registerGpuBackend(
  DeviceRegistry registry, {
  MaterialCompilerRegistry? compilers,
}) {
  final opener = registry.addBackend(
    'Impeller',
    (DeviceRequest request) =>
        GpuRenderBackend.open(width: request.width, height: request.height),
  );
  final presenter = registry.addPresenter<GpuRenderBackend>(
    (
      GraphicsDevice device,
      TextureHandle frame, {
      BoxFit fit = BoxFit.fill,
      FilterQuality quality = FilterQuality.none,
    }) => GpuFrameImage(frame: frame, fit: fit, quality: quality),
  );
  final compiler = compilers?.register(const ImpellerSectionCompiler());
  return Registration(() {
    compiler?.cancel();
    opener.cancel();
    presenter.cancel();
  });
}
