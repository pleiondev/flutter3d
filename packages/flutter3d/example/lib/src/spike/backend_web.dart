/// The WebGL2 backend, on the web.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';

/// Builds the device this application draws through.
///
/// The size is the canvas the browser will composite. Unlike Impeller, this
/// backend owns a surface and has to be told how big it is.
/// The `Future` is for the Impeller build's benefit, not this one's: a
/// conditional import picks between the two and they must have one signature.
/// Nothing here waits.
Future<GraphicsDevice> createBackend({
  required int width,
  required int height,
}) async {
  final device = WebGlDevice.create(
    width: width,
    height: height,
    sources: engineShaders,
  );
  if (device == null) {
    throw StateError(
      'no WebGL2 context. This build needs it; there is no software path.',
    );
  }
  return device;
}

/// What to call this build in a diagnostic.
const String kBackendName = 'webgl';
