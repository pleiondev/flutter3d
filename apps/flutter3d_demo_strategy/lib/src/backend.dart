/// What this game asks of whichever backend it was built against.
///
/// **The choosing is not here.** The conditional import and `openDevice` were
/// three files in each of the other demos before they were one file in
/// `flutter3d_backend`, reached through the `flutter3d_app` barrel this file
/// re-exports rather than naming `flutter3d_backend` directly. What is left is
/// the part no two games share: the size this one draws at, and the shadow
/// atlas it can afford, when the backend renders to a fixed internal target.
library;

import 'package:flutter3d_app/flutter3d_app.dart';

export 'package:flutter3d_app/flutter3d_app.dart';

/// 960×540 in a browser, the frame the racer settled on.
///
/// A map camera looks down on a hundred and sixty metres of hillside, and from
/// up there a unit is a few pixels wide whichever number goes here — nothing in
/// this game is read at the scale a chase camera reads a kerb at. What the
/// smaller frame buys is fill rate, and this game spends fill rate over more
/// surfaces than the others: the ground, the crowd on it, and the fog drawn on
/// top of both.
///
/// Read only when [kFixedResolution]; a desktop build draws at whatever size the
/// widget was laid out at.
const int kRenderWidth = 960;
const int kRenderHeight = 540;

/// The shadow atlas this build can afford.
///
/// **The number that mattered turned out not to be the frame.** The racer went
/// looking for its browser frame rate in fill rate and did not find it there —
/// shrinking the picture to a ninth of the pixels changed nothing measurable.
/// The cost was the cube shadow atlas, whose tile came from
/// `ShadowSettings.resolution`, the number a game picks for the *sun*: a
/// desktop's 1024 came out as a 201 MB texture, and there are two of them, on a
/// platform where a whole tab has less.
///
/// The same reason lands harder here, because this game arrives at a browser
/// with the budget already spent. The fog is 1681 lattice cells over a
/// 160-metre map, drawn as two instanced batches of boxes standing on top of
/// the ground and the crowd; anything a frame *allocates* is allocated against
/// that. Two tiles of 1024 is a twelfth of the fill of a desktop's three of
/// 2048, and it covers the ground the camera is over, which from above is the
/// only ground that reads.
///
/// **Branched on [kFixedResolution] rather than on `kIsWeb`.** They are true
/// together, and the question being asked is the one the backend already
/// answers: a build that renders to a fixed internal target is the build whose
/// fill rate is worth economising. Asking `kIsWeb` would be asking a second
/// question that has to keep agreeing with the first.
const int kShadowCascades = kFixedResolution ? 2 : 3;
const int kShadowResolution = kFixedResolution ? 1024 : 2048;
