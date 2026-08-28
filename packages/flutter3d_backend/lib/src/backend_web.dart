/// The browser backend: WebGL2, over a canvas the browser composites.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';

/// Whether this build renders at a fixed internal resolution.
///
/// True here, and it is a property of the backend rather than a choice: a
/// `WebGlDevice` owns the canvas it was created with, and a WebGL canvas resets
/// its drawing buffer when it is resized. So the frame is drawn at one size and
/// the element is stretched to the layout by CSS — which is also why `present`
/// takes a `BoxFit`.
///
/// **What size** is the application's, not this file's: 720p in the crypt and
/// the platformer, 960×540 in the racing game, each with its own reason written
/// where the number is.
const bool kFixedResolution = true;

/// Opens the backend, or throws with something worth putting on screen.
///
/// The whole of it is `flutter3d_webgl`'s: what a browser has to provide is that
/// package's knowledge, and three games had been repeating it.
Future<GraphicsDevice> openDevice({required int width, required int height}) =>
    openWebGl(width: width, height: height);
