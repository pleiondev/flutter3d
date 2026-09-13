/// Registers this backend with `flutter3d_hardware`'s device registry — see
/// `flutter3d_impeller/src/gpu_backend_registration.dart` for why this is a
/// guarded function rather than code that runs at library load.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'open.dart';
import 'webgl_device.dart';
import 'webgl_frame_presenter.dart';

bool _registered = false;

/// Registers [WebGlDevice] as the web fallback opener and a frame presenter,
/// once.
///
/// A fallback rather than a preferred opener: WebGL2 is what an ordinary web
/// build draws through, and the one browser backend the engine has a
/// recorded reference set for — whatever else is registered ahead of it
/// (WebGPU, tried only when a build asks), this is the backend still
/// standing when nothing else starts.
void ensureWebGlBackendRegistered() {
  if (_registered) return;
  _registered = true;
  registerBackendOpener('WebGL2', openWebGl, asFallback: true);
  registerDevicePresenter<WebGlDevice>(
    (
      GraphicsDevice device,
      TextureHandle frame, {
      BoxFit fit = BoxFit.fill,
      FilterQuality quality = FilterQuality.none,
    }) => WebGlFramePresenter(
      device: device as WebGlDevice,
      frame: frame,
      fit: fit,
      quality: quality,
    ),
  );
}
