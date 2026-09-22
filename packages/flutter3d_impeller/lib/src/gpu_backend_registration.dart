/// Registers this backend with `flutter3d_hardware`'s device registry, so an
/// assembly layer can open and present it without naming it.
///
/// **Idempotent and called from [ensureGpuBackendRegistered], not run at
/// library load.** Dart only runs a top-level initializer when something
/// reads it, so registering *this* backend still needs one line at the call
/// site that wants it available — the difference from naming the backend
/// directly is that the line says "make sure Impeller can be chosen" rather
/// than "here is how Impeller opens and here is its widget", which stays
/// exactly here.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'gpu_device.dart';

bool _registered = false;

/// Registers [GpuRenderBackend] as an opener and a frame presenter, once.
///
/// Not a fallback: Impeller is the backend a native build prefers, and
/// whatever calls this registers the software rasteriser as the fallback
/// separately.
void ensureGpuBackendRegistered() {
  if (_registered) return;
  _registered = true;
  registerBackendOpener(
    'Impeller',
    ({required int width, required int height}) => GpuRenderBackend.create(),
  );
  registerDevicePresenter<GpuRenderBackend>(
    (
      GraphicsDevice device,
      TextureHandle frame, {
      BoxFit fit = BoxFit.fill,
      FilterQuality quality = FilterQuality.none,
    }) => GpuFrameImage(frame: frame, fit: fit, quality: quality),
  );
}
