/// The browser's backend: whatever `flutter3d_app` opens for a game.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_app/flutter3d_app.dart' as app;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// The size a browser frame is drawn at before CSS stretches it to the
/// window: `kFixedResolution` is true on the web, and the reason is the
/// canvas's rather than the editor's — see `flutter3d_app`'s
/// `backend_web.dart`. 720p, as in the crypt, because the editor's viewport
/// is the crypt's picture with panels over it.
const int kEditorFrameWidth = 1280;
const int kEditorFrameHeight = 720;

/// Opens WebGPU, or WebGL2 where WebGPU will not start, or throws with
/// something worth putting on screen.
Future<GraphicsDevice> openEditorDevice() =>
    app.openDevice(width: kEditorFrameWidth, height: kEditorFrameHeight);

/// The widget that shows [frame], for whichever device [openEditorDevice]
/// actually opened.
Widget presentEditorFrame(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.fill,
  FilterQuality quality = FilterQuality.none,
}) => app.presentFrame(device, frame, fit: fit, quality: quality);
