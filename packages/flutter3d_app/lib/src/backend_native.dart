/// The desktop and mobile backend: `flutter_gpu`, through Impeller — with a
/// software rasteriser to fall back to if Impeller will not start.
///
/// **Neither backend is named here.** Each registers itself with
/// `flutter3d_hardware`'s device registry — see
/// `flutter3d_impeller/src/gpu_backend_registration.dart` and
/// `flutter3d_cpu/src/cpu_backend_registration.dart` — and this file only
/// makes sure both have, then asks the registry to open one. A third,
/// native backend registers itself the same way, from its own package;
/// nothing here would have to change for it to be tried.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';

import 'cpu_frame_presenter.dart';
import 'surface/scene_surface.dart';

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

bool _registered = false;
void _ensureRegistered() {
  if (_registered) return;
  _registered = true;
  ensureGpuBackendRegistered();
  ensureCpuBackendRegistered();
  // The one presenter this file still registers directly: `CpuFrame` moved
  // here from `flutter3d_cpu` once that package went flat (mcp-02n), so
  // nowhere else can build it.
  registerDevicePresenter<CpuDevice>(
    (
      GraphicsDevice device,
      TextureHandle frame, {
      BoxFit fit = BoxFit.fill,
      FilterQuality quality = FilterQuality.none,
    }) => CpuFrame(
      texture: frame.backend as CpuTexture,
      fit: fit,
      quality: quality,
    ),
  );
}

/// Opens the backend, or throws with something worth putting on screen.
///
/// [width] and [height] are ignored by Impeller, which sizes itself per frame.
/// They are still in the signature because the other half of the conditional
/// needs them — and because the software rasteriser, the one this backend
/// falls back to, cannot size itself per frame and needs them for real.
Future<GraphicsDevice> openDevice({required int width, required int height}) {
  _ensureRegistered();
  return openRegisteredDevice(
    width: width,
    height: height,
    onFallback: (message) => debugPrint('flutter3d_app: $message'),
  );
}

/// The widget that shows [frame], for whichever [device] this build's
/// [openDevice] actually returned — or for any other [GraphicsDevice] a
/// caller registered with `registerDevicePresenter`, native backend or not.
///
/// A registry lookup rather than a `switch` on a sealed type, because
/// `GraphicsDevice` cannot be sealed: its implementations live in separate
/// packages, and Dart requires every subtype of a sealed type in the same
/// library. See `flutter3d_hardware/src/device_registry.dart` for why the
/// registry itself lives there rather than here.
Widget presentFrame(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.fill,
  FilterQuality quality = FilterQuality.none,
}) {
  _ensureRegistered();
  final presenter = lookUpDevicePresenter(device) as FramePresenter?;
  if (presenter == null) {
    throw ArgumentError(
      'presentFrame: no presenter registered for ${device.runtimeType} — '
      'call registerDevicePresenter<${device.runtimeType}>(...) once, '
      'before presenting a frame from this backend',
    );
  }
  return presenter(device, frame, fit: fit, quality: quality);
}
