/// Play from a level editor: the game a level belongs to, run with
/// `flutter run --machine`, reloaded, restarted and stopped, and handed a
/// level as soon as it is saved.
///
/// Used by the editor application's toolbar and by `flutter3d_editor_mcp`,
/// so an agent's Play is a person's Play. A browser imports `attach.dart`
/// instead, which is everything here that starts no process.
library;

export 'attach.dart';
export 'src/devices.dart';
export 'src/flutter_run.dart';
