/// The half of a shooter that needs the renderer.
///
/// `flutter3d_game_shooter.dart` is the simulation and imports nothing from
/// `flutter3d`; this is where the two meet for the one thing only a shooter
/// wants — the weapon in the player's hands, drawn in its own pass with its own
/// field of view. It sat in `flutter3d_bridge` until the genres became
/// packages, where it made the bridge know what a weapon was.
library;

export 'src/weapon_view.dart';
