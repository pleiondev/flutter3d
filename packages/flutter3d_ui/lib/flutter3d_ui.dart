/// The screens a game has that are not the game.
///
/// Settings, volumes, rebinding, and where a licence's attribution goes: the
/// parts a player uses before playing, after playing, and when something has to
/// change. None of it draws a frame or steps a simulation.
///
/// **Extracted when the second game wanted it**, which is this repository's
/// habit rather than a new rule — `CameraRig` says the same thing about itself,
/// and `flutter3d_bridge` exists for the same reason. What triggered it was
/// accessibility: rebinding a control is the accommodation that matters most,
/// the platformer had grown one, and the alternative was four hundred lines of
/// panel copied into the crypt to give it the same.
///
/// What is deliberately **not** here is anything a particular game says. The
/// credits are a widget the caller hands in, the list of rebindable actions is
/// the caller's, and the panel has never known what a coin or a monster is.
library;

export 'src/credits.dart';
export 'src/owned_bindings.dart';
export 'src/pad_presses.dart';
export 'src/rebinding.dart';
export 'src/save_file.dart';
export 'src/settings_cubit.dart';
export 'src/settings_file.dart';
export 'src/settings_keys.dart';
export 'src/settings_overlay.dart';
export 'src/settings_panel.dart';
export 'src/storage/storage.dart';
export 'src/volumes.dart';
