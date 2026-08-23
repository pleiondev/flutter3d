/// The desktop and mobile backend: `flutter_gpu`, through Impeller.
library;

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';

/// Whether this build renders at a fixed internal resolution.
///
/// False here: Impeller allocates its frame targets at whatever size the widget
/// was laid out at, so the picture is native resolution on any window.
///
/// A caller reads this rather than asking which backend it got, which is the
/// difference between branching on a property and branching on a name.
const bool kFixedResolution = false;

/// Opens the backend, or throws with something worth putting on screen.
///
/// [width] and [height] are ignored here: this backend sizes itself per frame.
/// They are still in the signature because the other half of the conditional
/// needs them, and a caller that had to know which one it got would be a caller
/// doing the choosing all over again.
Future<GraphicsDevice> openDevice({
  required int width,
  required int height,
}) =>
    GpuRenderBackend.create();
