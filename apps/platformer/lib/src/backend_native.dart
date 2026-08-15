/// The desktop and mobile backend: `flutter_gpu`, through Impeller.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';

/// Whether this build renders at a fixed internal resolution.
///
/// False here: Impeller allocates its frame targets at whatever size the
/// widget was laid out at, so the picture is native resolution on any window.
const bool kFixedResolution = false;

/// The size to render at when [kFixedResolution]. Unused here, and present so
/// that the caller needs no conditional of its own.
const int kRenderWidth = 0;
const int kRenderHeight = 0;

/// Opens the backend, or throws with something worth putting on screen.
///
/// [width] and [height] are ignored: this backend sizes itself per frame.
Future<GraphicsDevice> openDevice({
  required int width,
  required int height,
}) =>
    GpuRenderBackend.create();
