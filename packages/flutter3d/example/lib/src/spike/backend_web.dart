/// The browser backends, on the web.
library;

import 'package:flutter/widgets.dart' show BoxFit, FilterQuality;
import 'package:flutter3d_app/flutter3d_app.dart' show openDevice;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';

import 'golden_store.dart';

/// Which browser backend the page asked for, defaulting to WebGL2.
///
/// Read from the URL, exactly the way the golden scene and the record/compare
/// direction are read, and for exactly the same arithmetic: one dart2js run
/// serves 96 scenes because the scene is a query parameter, and one
/// dart2js run serves the browser backends because this is one too. A
/// `--dart-define` here would be a build per backend, which is the whole saving
/// of the browser golden stand spent on a single word.
///
/// The default is WebGL2 because that is what a build opened by hand should
/// draw with — the browser backend that has a recorded reference set behind it.
String get _requestedBackend {
  final name = Uri.base.queryParameters['backend'];
  return (name == null || name.isEmpty) ? 'webgl' : name;
}

/// Builds the device this application draws through.
///
/// The size is the canvas the browser will composite. Unlike Impeller, both
/// backends here own a surface and have to be told how big it is.
/// The `Future` used to be for the Impeller build's benefit alone; WebGPU needs
/// it for real, because `requestAdapter` and `requestDevice` are promises and
/// no constructor can wait on them.
///
/// A backend this build cannot make is refused rather than quietly substituted,
/// and that is now a rule about *names* rather than about WebGPU: the stand
/// records what it is told it drew, so answering `?backend=vulkan` with a WebGL2
/// frame would write one backend's pictures into another's reference set — and a
/// reference set that describes the wrong device is worse than an absent one,
/// because it passes.
Future<GraphicsDevice> createBackend({
  required int width,
  required int height,
}) async {
  final requested = _requestedBackend;
  try {
    return switch (requested) {
      'webgl' => _openWebGl(width: width, height: height),
      'webgpu' => await openDevice(
        width: width,
        height: height,
        registry: _webGpuOnly(),
      ),
      _ => throw StateError(
        'the page asked for the "$requested" backend and this build draws '
        'through webgl and webgpu. Refusing rather than drawing the wrong '
        'picture under the right name.',
      ),
    };
  } catch (error) {
    // A browser has no exit code, so a golden run says what happened by posting
    // a line, and the stand is waiting for one about this scene. Left to the
    // error panel alone, a device that will not open reaches the stand as a
    // ninety-second stall with no reason in it — which is a worse answer than
    // the same one given at once. Every way of failing here goes through this,
    // not just a name nobody recognises: a browser with no `navigator.gpu` and
    // a machine whose GPU is blocklisted both fail inside `WebGpuDevice.open`, and
    // those are the two a WebGPU run will actually meet.
    final scene = sceneOverride;
    if (scene != null) reportLine('GOLDEN $scene: $error');
    rethrow;
  }
}

/// A registry of WebGPU alone, with its presenter, to open the device from.
///
/// `flutter3d_app` registers a WebGPU presenter only in a build that asks for
/// WebGPU at compile time, and this one picks the backend from the URL, so
/// nothing had: every frame of a WebGPU page threw from `presentFrame` and the
/// canvas stayed empty, while the golden run, which reads the frame back
/// rather than looking at the canvas, passed. A device `openDevice` opened
/// remembers the registry, so `presentFrame` finds the presenter here. WebGL2
/// needs nothing, because `flutter3d_app` always registers it.
DeviceRegistry _webGpuOnly() => DeviceRegistry()
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

/// WebGL2, over the canvas it creates for itself. Throws a
/// `DeviceUnavailableException` where there is no WebGL2 context: this build
/// needs it, and there is no software path.
GraphicsDevice _openWebGl({required int width, required int height}) =>
    WebGlDevice.open(width: width, height: height);

/// What to call this build in a diagnostic.
///
/// A getter now, where it was a constant: one build can be asked for either
/// browser backend, so which one it is, is a fact about the page's URL rather
/// than about the compile. The Impeller side has answered this with a getter
/// for the same kind of reason since the software rasteriser joined it.
String get kBackendName => _requestedBackend;

/// What the browser refused while this device drew, or null when it refused
/// nothing.
///
/// **A refused call draws nothing and says nothing to the page.** WebGL2
/// rejects a draw with a GL error and moves on, and WebGPU drops a whole
/// submit over one invalid pipeline; either way the frame reads back as a
/// picture, only the wrong one. The golden stand recorded three such frames as
/// references before anybody looked at the console, so a golden run asks here
/// and refuses a frame drawn with errors, whatever it looks like.
Future<String?> deviceErrors(GraphicsDevice device) async => switch (device) {
  final WebGlDevice gl => gl.debugDrainErrors('WebGL2'),
  final WebGpuDevice gpu => await gpu.debugDrainErrors('WebGPU'),
  _ => null,
};
