/// The browser backend: WebGL2 over a canvas the browser composites, and —
/// only when a build asks for it — WebGPU tried first.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';

/// Whether this build renders at a fixed internal resolution.
///
/// True here, and it is a property of the backend rather than a choice: a
/// `WebGlDevice` owns the canvas it was created with, and a WebGL canvas resets
/// its drawing buffer when it is resized. So the frame is drawn at one size and
/// the element is stretched to the layout by CSS — which is also why `present`
/// takes a `BoxFit`.
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
const bool kFixedResolution = true;

/// Whether this build may try WebGPU before settling for WebGL2.
///
///     flutter build web --dart-define=FLUTTER3D_WEBGPU=true
///
/// **Off by default, and that is a decision about bundle size rather than about
/// WebGPU.** The probe cannot be a compile-time choice the way web-or-native is:
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
/// So the flag is the price tag, and whether a particular game pays it is that
/// game's call — the same shape as the resolution and the shadow budget this
/// package already refuses to decide. The figure is re-measured rather than
/// carried forward, because both halves grow: the reading before this one was
/// 372,686 bytes over a tree eleven thousand bytes smaller.
///
/// What is *not* a call anybody makes per game is that WebGL2 is what an
/// ordinary web build draws through. WebGPU is the newer API and the one whose
/// reference pictures are still being recorded, and a default that quietly
/// moved every browser build onto it would change what three shipped games look
/// like without anybody having asked for it.
const bool _tryWebGpu = bool.fromEnvironment('FLUTTER3D_WEBGPU');

/// Opens the backend, or throws with something worth putting on screen.
///
/// The whole of it is the backend packages': what a browser has to provide is
/// their knowledge, and three games had been repeating it.
///
/// **The fall back is a `try`/`catch` for the same reason the native half's
/// is.** There, `flutter_gpu` is always importable and only trying says whether
/// Impeller starts; here, `navigator.gpu` may be absent, or present and hand
/// back no adapter because the machine's GPU is blocklisted. `openWebGpu`
/// already turns both of those into one [StateError], so this catches it and
/// says on the console which backend the frame is actually coming from —
/// silence would leave a WebGL2 picture being read as a WebGPU one.
Future<GraphicsDevice> openDevice({
  required int width,
  required int height,
}) async {
  if (_tryWebGpu) {
    try {
      return await openWebGpu(width: width, height: height);
    } catch (error) {
      debugPrint(
        'flutter3d_backend: WebGPU would not start ($error), '
        'falling back to WebGL2',
      );
    }
  }
  return openWebGl(width: width, height: height);
}
