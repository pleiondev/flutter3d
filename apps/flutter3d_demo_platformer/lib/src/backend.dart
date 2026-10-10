/// What this game asks of whichever backend it was built against.
///
/// **The choosing is not here any more.** The conditional import, `openDevice`
/// and `fixedResolution` were three files in this game and the same three,
/// byte for byte, in the crypt — down to the paragraph explaining why a
/// conditional import rather than a runtime branch. They live in
/// `flutter3d_app` now, reached through the same barrel this file
/// re-exports, and the game's `Flutter3dView` opens the device through them:
/// at 720p where a backend renders to a fixed internal resolution, which is
/// the trade this demo makes in a browser, and at whatever size the view is
/// laid out at everywhere else.
library;

export 'package:flutter3d_app/flutter3d_app.dart';
