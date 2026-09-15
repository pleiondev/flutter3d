/// The screens a game has that are not the game.
///
/// **This package is a compatibility shim.** Its own code — settings,
/// volumes, rebinding, credits, saves, the storage underneath them — moved
/// into `flutter3d_session` by the package-merge plan, once it turned out
/// nothing anywhere depended on this package without also depending on that
/// one. What is here now is one `export`, kept so an existing import of
/// `package:flutter3d_screens/flutter3d_screens.dart` keeps resolving to the
/// exact same declarations, unchanged, rather than asking every caller to
/// move on the same day the code did.
///
/// New code should import `package:flutter3d_session/flutter3d_session.dart`
/// directly. `native.dart` and `testing.dart` moved the same way, to the same
/// package, and are not re-exported here — see `flutter3d_session`'s own
/// copies of both.
library;

export 'package:flutter3d_session/flutter3d_session.dart';
