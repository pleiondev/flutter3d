/// WebGL2 as a backend an engine can open.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/backend.dart' show MaterialCompilerRegistry;

import 'webgl_device.dart';
import 'webgl_frame_presenter.dart';
import 'webgl_section_compiler.dart';

/// Adds WebGL2 to [registry] as its fallback — what a browser without
/// WebGPU still draws with — with the presenter that shows its frames. The
/// registration takes both out again. Since 1.0 it is added to the engine's
/// own registry rather than to a global one (it was
/// `ensureWebGlBackendRegistered`).
///
/// Given [compilers] (D26), the registry `RuntimeShaders` and a build find a
/// backend's material compiler in, the [WebGlSectionCompiler] is registered
/// there as well and taken out with the rest.
Registration registerWebGlBackend(
  DeviceRegistry registry, {
  MaterialCompilerRegistry? compilers,
}) {
  final opener = registry.addBackend(
    'WebGL2',
    (DeviceRequest request) =>
        WebGlDevice.open(width: request.width, height: request.height),
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
  final compiler = compilers?.register(const WebGlSectionCompiler());
  return Registration(() {
    compiler?.cancel();
    opener.cancel();
    presenter.cancel();
  });
}
