/// The browser backend: WebGL2, over a canvas the browser composites.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';

/// Whether this build renders at a fixed internal resolution.
///
/// True here, and it is a property of the backend rather than a choice: a
/// `WebGlDevice` owns the canvas it was created with, and a WebGL canvas resets
/// its drawing buffer when it is resized. So the frame is drawn at one size and
/// the element is stretched to the layout by CSS — which is also why `present`
/// takes a `BoxFit`.
const bool kFixedResolution = true;

/// 960×540, lower than the other two demos.
///
/// It does not go far enough. This scene runs at well under one frame a second
/// in a browser, and dropping to 480×270 with a single 512 shadow tile changed
/// nothing measurable, so the cost is not fill rate. Until it is found, the
/// browser build of this game renders correctly and is not playable; the
/// desktop build is.
const int kRenderWidth = 960;
const int kRenderHeight = 540;

/// The shadow atlas this build can afford.
///
/// The atlas is `resolution × cascades` wide. Desktop asks for 3 × 2048, which
/// is a 6144-pixel HDR texture; two tiles of 1024 is a twelfth of the fill and
/// still covers the near road, which is the only part a chase camera sees in
/// any detail.
const int kShadowCascades = 2;
const int kShadowResolution = 1024;

/// Opens the backend, or throws with something worth putting on screen.
///
/// The whole of it is `flutter3d_webgl`'s: what a browser has to provide is
/// that package's knowledge, and three games had been repeating it.
Future<GraphicsDevice> openDevice({
  required int width,
  required int height,
}) =>
    openWebGl(width: width, height: height);
