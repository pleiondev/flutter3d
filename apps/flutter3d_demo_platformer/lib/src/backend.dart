/// What this game asks of whichever backend it was built against.
///
/// **The choosing is not here any more.** The conditional import, `openDevice`
/// and `kFixedResolution` were three files in this game and the same three,
/// byte for byte, in the crypt — down to the paragraph explaining why a
/// conditional import rather than a runtime branch. They live in
/// `flutter3d_backend` now, reached through the `flutter3d_app` barrel this
/// file re-exports rather than naming `flutter3d_backend` directly, since the
/// app's own pubspec no longer lists it by name either.
///
/// What stays is the part that was never shared: the size this game draws at
/// when the backend renders to a fixed internal resolution.
library;

import 'package:flutter3d_app/flutter3d_app.dart';

export 'package:flutter3d_app/flutter3d_app.dart';

/// 720p, which is the trade this demo makes in a browser.
///
/// Every pixel is blitted to the canvas and then scaled by the browser, so this
/// is the resolution the picture actually has however large the window is.
/// Higher costs fill rate on a software-composited surface; lower reads as
/// blurry the moment anybody opens it on a laptop.
///
/// Read only when [kFixedResolution]; a desktop build draws at whatever size the
/// widget was laid out at.
const int kRenderWidth = 1280;
const int kRenderHeight = 720;
