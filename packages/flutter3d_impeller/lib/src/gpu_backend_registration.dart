/// Impeller as a backend an engine can open.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'gpu_device.dart';

/// Adds Impeller to [registry] — preferred over anything added before it —
/// with the presenter that shows its frames. The registration takes both
/// out again. Since 1.0 it is added to the engine's own registry rather than
/// to a global one (it was `ensureGpuBackendRegistered`).
Registration registerGpuBackend(DeviceRegistry registry) {
  final opener = registry.addBackend(
    'Impeller',
    ({required int width, required int height}) => GpuRenderBackend.open(),
  );
  final presenter = registry.addPresenter<GpuRenderBackend>(
    (
      GraphicsDevice device,
      TextureHandle frame, {
      BoxFit fit = BoxFit.fill,
      FilterQuality quality = FilterQuality.none,
    }) => GpuFrameImage(frame: frame, fit: fit, quality: quality),
  );
  return Registration(() {
    opener.cancel();
    presenter.cancel();
  });
}
