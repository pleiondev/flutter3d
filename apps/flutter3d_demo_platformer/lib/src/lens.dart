import 'package:flutter3d/flutter3d.dart' show PerspectiveProjection;
import 'package:flutter3d_game_ui/screens.dart' show Lens;

/// The lens this game is played through.
///
/// **Sixty degrees, not the engine's forty-five**, and a far plane of 220 m
/// rather than a kilometre. The levels are 120 by 260 metres: a kilometre of
/// depth range is spent on nothing while the near end pays for it in precision,
/// and a narrow lens in a third-person platformer hides the ledge you are
/// aiming at just as you commit to the jump.
///
/// **Why this is a [Lens] and not two numbers on the camera.** The camera's
/// projection is rebuilt every frame to fold in the speed widening, so
/// something has to say what it widens *from*. For the whole life of the game
/// that something was a second, bare `PerspectiveProjection()` living beside
/// the camera — so both numbers above were overwritten on the first frame and
/// never seen again. One base and one operation, so there is no second base
/// to disagree with the first; `Lens` itself is `flutter3d_game_ui/screens.dart`'.
const Lens ascentLens = Lens(PerspectiveProjection(fovY: 1.05, far: 220.0));
