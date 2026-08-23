/// The desktop and mobile backend: `flutter_gpu`, through Impeller — with a
/// software rasteriser to fall back to if Impeller will not start.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';

/// Whether this build renders at a fixed internal resolution.
///
/// False here: Impeller allocates its frame targets at whatever size the widget
/// was laid out at, so the picture is native resolution on any window.
///
/// A caller reads this rather than asking which backend it got, which is the
/// difference between branching on a property and branching on a name. It is
/// also, deliberately, a compile-time constant — `kShadowCascades`-style
/// declarations in a game's own `backend.dart` depend on being able to fold it
/// at compile time. The software fallback [openDevice] can reach for is a
/// runtime decision and cannot update this: a fallback frame is drawn at a
/// fixed size too, and that is a known limit of [kFixedResolution] being a
/// constant, not something this file resolves.
const bool kFixedResolution = false;

/// Opens the backend, or throws with something worth putting on screen.
///
/// [width] and [height] are ignored by Impeller, which sizes itself per frame.
/// They are still in the signature because the other half of the conditional
/// needs them — and because the software rasteriser, the one this backend
/// falls back to, cannot size itself per frame and needs them for real.
///
/// **Falling back is a runtime decision because it has to be.** `flutter_gpu`
/// ships with the Flutter SDK, so it is always there to import; whether
/// Impeller actually starts depends on the platform and how the engine was
/// launched, and no `dart.library.*` check can see that. Trying is the only
/// way to find out, which is why this is a `try`/`catch` inside the native half
/// of the conditional export rather than a third branch of it.
Future<GraphicsDevice> openDevice({
  required int width,
  required int height,
}) async {
  try {
    return await GpuRenderBackend.create();
  } catch (error) {
    debugPrint('flutter3d_backend: Impeller would not start ($error), '
        'falling back to the software rasteriser');
    return CpuDevice(
      width: width,
      height: height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
  }
}
