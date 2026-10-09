/// WebGL2 as a backend an engine can open.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgl_device.dart';
import 'webgl_frame_presenter.dart';

/// Adds WebGL2 to [registry] as its fallback — what a browser without
/// WebGPU still draws with — with the presenter that shows its frames. The
/// registration takes both out again. Since 1.0 it is added to the engine's
/// own registry rather than to a global one (it was
/// `ensureWebGlBackendRegistered`).
Registration registerWebGlBackend(DeviceRegistry registry) {
  final opener = registry.addBackend(
    'WebGL2',
    ({required int width, required int height}) async =>
        WebGlDevice.open(width: width, height: height),
    asFallback: true,
  );
  final presenter = registry.addPresenter<WebGlDevice>(
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
  return Registration(() {
    opener.cancel();
    presenter.cancel();
  });
}
