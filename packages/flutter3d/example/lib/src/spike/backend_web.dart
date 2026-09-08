/// The browser backends, on the web.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';

import 'golden_store.dart';

/// Which browser backend the page asked for, defaulting to WebGL2.
///
/// Read from the URL, exactly the way the golden scene and the record/compare
/// direction are read, and for exactly the same arithmetic: one dart2js run
/// serves forty-three scenes because the scene is a query parameter, and one
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
/// The size is the canvas the browser will composite. Unlike Impeller, this
/// backend owns a surface and has to be told how big it is.
/// The `Future` is for the Impeller build's benefit, not this one's: a
/// conditional import picks between the two and they must have one signature.
/// Nothing here waits.
///
/// A backend this build cannot make is refused rather than quietly substituted.
/// The stand records what it is told it drew, so a silent fall back to WebGL2
/// would write one backend's frames into another's reference set — and a
/// reference set that describes the wrong device is worse than an absent one,
/// because it passes.
Future<GraphicsDevice> createBackend({
  required int width,
  required int height,
}) async {
  final requested = _requestedBackend;
  if (requested != 'webgl') {
    final refusal =
        'the page asked for the "$requested" backend and this build only draws '
        'through WebGL2. Refusing rather than drawing the wrong picture under '
        'the right name.';
    // A browser has no exit code, so a golden run says what happened by posting
    // a line, and the stand is waiting for one about this scene. Left to the
    // error panel alone the refusal would reach the stand as a ninety-second
    // stall with no reason in it — which is a worse answer than the same one
    // given at once.
    final scene = sceneOverride;
    if (scene != null) reportLine('GOLDEN $scene: $refusal');
    throw StateError(refusal);
  }
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
///
/// A getter now, where it was a constant: one build can be asked for either
/// browser backend, so which one it is, is a fact about the page's URL rather
/// than about the compile. The Impeller side has answered this with a getter
/// for the same kind of reason since the software rasteriser joined it.
String get kBackendName => _requestedBackend;
