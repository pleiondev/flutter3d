/// The desktop and mobile backend: `flutter_gpu`, through Impeller — with a
/// software rasteriser to fall back to if Impeller will not start.
///
/// **Neither backend is named here.** Each adds itself to a
/// `flutter3d_hardware` device registry — see
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
import 'materials/material_language_stage.dart';
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
/// fixed size too, and that is a known limit of [fixedResolution] being a
/// constant, not something this file resolves.
const bool fixedResolution = false;

/// A registry holding this platform's backends: Impeller, preferred, and the
/// software rasteriser as the fallback, each with its presenter.
///
/// **A new registry each call**, which an engine owns — a `Flutter3dView`
/// makes one, two engines in one isolate make two — so nothing one adds is
/// another's (API review A.4). [openDevice] without a registry makes one for
/// the call; there is no registry for the whole process to add to, since
/// 1.0 (`defaultDevices` was one). A test that wants a fake in front of the
/// real backends adds it to a registry of its own and hands that over.
DeviceRegistry<FramePresenter> platformDevices() {
  final registry = DeviceRegistry<FramePresenter>();
  registerGpuBackend(registry);
  // `P8`: a bundle built from a `.f3dmat` draws here with no Dart of its own.
  registerCpuBackend(registry, materialCompiler: materialLanguageCompiler);
  // The one presenter this file adds directly: `CpuFrame` moved here from
  // `flutter3d_cpu` once that package went flat (mcp-02n), so nowhere else
  // can build it.
  registry.addPresenter<CpuDevice>(
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
  return registry;
}

/// The registry each device [openDevice] opened came from, so [presentFrame]
/// finds its presenter without being handed the registry again.
final Expando<DeviceRegistry> _openedFrom = Expando<DeviceRegistry>(
  'the registry a device was opened from',
);

/// This platform's presenters, for [presentFrame] asked about a device that
/// [openDevice] did not open and handed no registry. Nothing outside this
/// file can add to it: a backend or presenter of one's own goes into a
/// registry the caller owns, from [platformDevices], and is passed.
DeviceRegistry<FramePresenter> get _platformPresenters =>
    _presenters ??= platformDevices();
DeviceRegistry<FramePresenter>? _presenters;

/// Opens the backend, or throws with something worth putting on screen.
///
/// **Sugar, and nothing else**: `(registry ?? platformDevices()).open(width:,
/// height:)`, printing each backend that refused before the next is tried,
/// with the device remembering its registry. Every backend opens in that one
/// shape since 1.0 — asynchronous, given the size — so this adds no way of
/// opening of its own.
///
/// [width] and [height] are not held by Impeller, which sizes itself per
/// frame; the software rasteriser it falls back to draws at them.
///
/// With no [registry], this platform's backends ([platformDevices], made for
/// the call); hand one over to try a backend of your own first — a test's
/// fake, say. The device remembers the registry it came from, so
/// [presentFrame] finds its presenter there.
Future<GraphicsDevice> openDevice({
  required int width,
  required int height,
  DeviceRegistry? registry,
}) async {
  final from = registry ?? platformDevices();
  final device = await from.open(
    width: width,
    height: height,
    onFallback: (message) => debugPrint('flutter3d_app: $message'),
  );
  _openedFrom[device] = from;
  return device;
}

/// The widget that shows [frame], for whichever [device] this build's
/// [openDevice] actually returned — or for any other [GraphicsDevice] a
/// caller added with `DeviceRegistry.addPresenter`, native backend or not.
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
  DeviceRegistry? registry,
}) {
  final from = registry ?? _openedFrom[device] ?? _platformPresenters;
  return switch (from.presenterFor(device)) {
    final FramePresenter present => present(
      device,
      frame,
      fit: fit,
      quality: quality,
    ),
    null => throw ArgumentError(
      'presentFrame: no presenter added for ${device.runtimeType} — call '
      'registry.addPresenter<${device.runtimeType}>(...) on the registry the '
      'device came from, before presenting a frame from this backend',
    ),
    final Object other => throw ArgumentError(
      'presentFrame: the presenter added for ${device.runtimeType} is a '
      '${other.runtimeType}, not a FramePresenter — make the registry a '
      'DeviceRegistry<FramePresenter> (platformDevices() is one), so a '
      'presenter of another type is refused where it is added',
    ),
  };
}
