/// The browser backend: WebGPU tried first, and WebGL2 over a canvas the
/// browser composites where WebGPU will not start — or where a build says
/// it does not want WebGPU at all.
///
/// **WebGL2 is not named here either** — it registers itself with
/// `flutter3d_hardware`'s device registry, the same way the native half's
/// two backends do; see `flutter3d_webgl/src/webgl_backend_registration.dart`.
/// **WebGPU is the one backend this file still registers directly**, and
/// deliberately: registering it from inside `flutter3d_webgpu` itself would
/// make the `--dart-define=FLUTTER3D_WEBGPU=true` flag pointless, since the
/// registration call would still reach `WebGpuDevice.open` and keep the whole
/// backend reachable — and reachable code is code dart2js ships — in every
/// web build, flag or not. See [_tryWebGpu] for the measurement.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';

import 'surface/scene_surface.dart';

/// Whether this build renders at a fixed internal resolution.
///
/// True here, and it is a property of the backend rather than a choice: a
/// `WebGlDevice` owns the canvas it was created with, and a WebGL canvas resets
/// its drawing buffer when it is resized. So the frame is drawn at one size and
/// the element is stretched to the layout by CSS — which is also why
/// [presentFrame] takes a `BoxFit`.
///
/// It stays true when [_tryWebGpu] is on, and for a related but not identical
/// reason: a `WebGpuDevice` draws into textures of its own and *copies* the
/// finished frame into a canvas, so the canvas could in principle be
/// reconfigured on a resize while the WebGL2 one cannot. What it renders is
/// still a fixed-size target, so the answer a caller needs — is the picture
/// drawn at a size I chose — is the same either way, and the constant does not
/// have to become a runtime question to stay honest.
///
/// **What size** is the application's, not this file's: 720p in the crypt and
/// the platformer, 960×540 in the racing game, each with its own reason written
/// where the number is.
const bool fixedResolution = true;

/// Whether this build may try WebGPU before settling for WebGL2.
///
///     flutter build web --dart-define=FLUTTER3D_WEBGPU=false   # WebGL2 only
///
/// **On by default since 0.9.0**, when WebGPU's golden set held every scene
/// the other three hold (nothing left in `cross_backend_test.dart`'s
/// `_provisional`) — decision 18's condition for a backend a build reaches
/// without asking. Where a browser hands out no adapter, the registry's
/// fallback opens WebGL2, as it always did for a build that asked.
///
/// **The define stays, and it is a decision about bundle size rather than
/// about WebGPU.** The probe cannot be a compile-time choice the way
/// web-or-native is:
/// whether a browser hands out a WebGPU adapter depends on the browser, the
/// driver and the machine's blocklist, none of which anything at compile time
/// can see — so finding out means trying, and trying means the WebGPU device is
/// reachable code. A define is what keeps that from being every game's problem:
/// `bool.fromEnvironment` folds to a constant, the branch below folds with it,
/// and a build that did not ask carries one backend rather than two. Turn it on
/// and the build carries both, plus one adapter request before the first frame.
///
/// **376,649 bytes**, measured rather than assumed, and measured again on the
/// day this sentence was last edited: `flutter build web --release` on
/// `apps/flutter3d_demo_strategy` writes a 2,529,865-byte `main.dart.js` with
/// this off and a 2,906,514-byte one with it on — 14.9% more script, and 368 KiB
/// on the whole of `build/web`. That is the WebGPU device, its encoder, its
/// pipeline cache and its WGSL arriving in a bundle that will never open them.
/// So the flag is the price tag, and a game that would rather not pay it —
/// a small one, served where WebGL2 is all its players have — turns it off;
/// the same shape as the resolution and the shadow budget this package
/// already refuses to decide. The figure is re-measured rather than
/// carried forward, because both halves grow: the reading before this one was
/// 372,686 bytes over a tree eleven thousand bytes smaller.
///
/// It was off until the pictures were in: a default that moved every
/// browser build onto a backend whose references were still being recorded
/// would have changed what three shipped games look like with nothing to
/// say whether it changed them for the worse.
const bool _tryWebGpu = bool.fromEnvironment(
  'FLUTTER3D_WEBGPU',
  defaultValue: true,
);

/// A registry holding this platform's backends: WebGL2 as the fallback and,
/// unless `FLUTTER3D_WEBGPU=false`, WebGPU preferred, each with its
/// presenter. A new registry each call, which an engine owns; see the native
/// half's doc.
DeviceRegistry platformDevices() {
  final registry = DeviceRegistry();
  registerWebGlBackend(registry);
  if (_tryWebGpu) {
    registry
      ..addBackend(
        'WebGPU',
        ({required int width, required int height}) =>
            WebGpuDevice.open(width: width, height: height),
      )
      ..addPresenter<WebGpuDevice>(
        (
          GraphicsDevice device,
          TextureHandle frame, {
          BoxFit fit = BoxFit.fill,
          FilterQuality quality = FilterQuality.none,
        }) => WebGpuFramePresenter(
          device: device as WebGpuDevice,
          frame: frame,
          fit: fit,
          quality: quality,
        ),
      );
  }
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
DeviceRegistry get _platformPresenters => _presenters ??= platformDevices();
DeviceRegistry? _presenters;

/// Opens the backend, or throws with something worth putting on screen.
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
/// caller registered with `registerDevicePresenter`, web backend or not.
///
/// A registry lookup rather than a `switch` on a sealed type — see
/// `backend_native.dart`'s twin for why.
Widget presentFrame(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.fill,
  FilterQuality quality = FilterQuality.none,
  DeviceRegistry? registry,
}) {
  final presenter =
      (registry ?? _openedFrom[device] ?? _platformPresenters).presenterFor(
            device,
          )
          as FramePresenter?;
  if (presenter == null) {
    throw ArgumentError(
      'presentFrame: no presenter added for ${device.runtimeType} — call '
      'registry.addPresenter<${device.runtimeType}>(...) on the registry the '
      'device came from, before presenting a frame from this backend',
    );
  }
  return presenter(device, frame, fit: fit, quality: quality);
}
