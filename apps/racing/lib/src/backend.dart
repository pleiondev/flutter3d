/// What this game asks of whichever backend it was built against.
///
/// **The choosing is not here any more.** The conditional import and
/// `openDevice` were three files here and the same three in the other two
/// games; they live in `flutter3d_backend` now. What stays is what was never
/// shared, and this game has more of it than the other two: a smaller frame and
/// a smaller shadow atlas in a browser.
library;

import 'package:flutter3d_backend/flutter3d_backend.dart';

export 'package:flutter3d_backend/flutter3d_backend.dart';

/// 960×540 in a browser, lower than the other two demos.
///
/// It does not go far enough. This scene runs at well under one frame a second
/// in a browser, and dropping to 480×270 with a single 512 shadow tile changed
/// nothing measurable, so the cost is not fill rate. Until it is found, the
/// browser build of this game renders correctly and is not playable; the desktop
/// build is.
///
/// Read only when [kFixedResolution].
const int kRenderWidth = 960;
const int kRenderHeight = 540;

/// The shadow atlas this build can afford.
///
/// The atlas is `resolution × cascades` wide. A desktop asks for 3 × 2048, which
/// is a 6144-pixel HDR texture; two tiles of 1024 is a twelfth of the fill and
/// still covers the near road, which is the only part a chase camera sees in any
/// detail.
///
/// **Branched on [kFixedResolution] rather than on `kIsWeb`.** They are true
/// together, and the question being asked is the one the backend already
/// answers: a build that renders to a fixed internal target is the build whose
/// fill rate is worth economising. Asking `kIsWeb` would be asking a second
/// question that has to keep agreeing with the first.
const int kShadowCascades = kFixedResolution ? 2 : 3;
const int kShadowResolution = kFixedResolution ? 1024 : 2048;
