/// The half of a shooter that meets a screen.
///
/// `flutter3d_game_shooter.dart` is the simulation and names neither
/// `flutter3d` nor Flutter; this is where the two meet for what only a shooter
/// wants — the weapon in the player's hands, drawn in its own pass with its own
/// field of view, and the readouts a game lays out over the picture. The weapon
/// sat in `flutter3d_bridge` until the genres became packages, where it made
/// the bridge know what a weapon was.
library;

export 'src/hud.dart';
export 'src/weapon_view.dart';
