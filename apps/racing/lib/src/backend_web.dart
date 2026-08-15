/// The browser backend: WebGL2, over a canvas the browser composites.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';

/// Whether this build renders at a fixed internal resolution.
///
/// True here, and it is a property of the backend rather than a choice: a
/// `WebGlDevice` owns the canvas it was created with, and a WebGL canvas resets
/// its drawing buffer when it is resized. So the frame is drawn at one size and
/// the element is stretched to the layout by CSS — which is also why `present`
/// takes a `BoxFit`.
const bool kFixedResolution = true;

/// 720p, which is the trade this demo is making.
///
/// Every pixel here is blitted to the canvas and then scaled by the browser, so
/// this is the resolution the picture actually has however large the window is.
/// Higher costs fill rate on a software-composited surface; lower reads as
/// blurry the moment anybody opens it on a laptop.
const int kRenderWidth = 1280;
const int kRenderHeight = 720;

/// Opens the backend, or throws with something worth putting on screen.
Future<GraphicsDevice> openDevice({
  required int width,
  required int height,
}) async {
  final device = WebGlDevice.create(
    width: width,
    height: height,
    // GLSL ES 3.00, translated from `flutter3d_shaders` by
    // `flutter3d_webgl/tool/generate_shaders.dart`. There is no compiled
    // bundle on this backend: a browser compiles GLSL itself, so a "bundle" is
    // a map from the engine's entry point names to source text.
    sources: engineShaders,
  );
  if (device == null) {
    throw StateError(
      'WebGL2 is not available in this browser. The engine needs WebGL2 '
      '(not WebGL1) and EXT_color_buffer_float for its HDR target.',
    );
  }
  return device;
}
