/// What a game on this engine is as an application.
///
/// Not the simulation — that is `flutter3d_game` and the three genre packages.
/// Not the screens a player uses — that is `flutter3d_ui`. This is the part in
/// between that every one of the three games turned out to have written for
/// itself: the seam a rendered frame reaches Flutter through, and the run being
/// played.
///
/// **It exists because neither of its two neighbours can hold it.** A session
/// reads a level (which needs `flutter3d_bridge`, and therefore the renderer)
/// and writes a save (which needs `flutter3d_ui`, and therefore storage), and
/// those two packages do not know about each other and should not. A package
/// that depends on both is the honest answer; growing either one to hold the
/// other's job is not.
///
/// **What is deliberately not here.**
///
/// * *The title card and the screen a player sees when they lose.* Those are
///   the face of a particular game, and three identical title screens would be
///   a loss rather than a saving.
/// * *`backend.dart` and its two halves*, which all three games carry and which
///   are near enough byte-identical. The conditional import there chooses
///   between `flutter3d_impeller` and `flutter3d_webgl`, so a shared copy would
///   have to depend on both — against the decision written into `flutter3d.dart`
///   itself: "an application picks one and depends on one by name". Three files
///   of a dozen lines is cheaper than every game carrying both backends.
/// * *A state-management choice.* [RunSession] is an ordinary class. Two of the
///   three games wrap it in a cubit; a package that made that decision for them
///   would be a package deciding something it cannot see.
library;

export 'src/frame_clock.dart';
export 'src/run_session.dart';
export 'src/scene_surface.dart';
