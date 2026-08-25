/// Monsters: what they are, and the one brain this game gives them.
///
/// This was `flutter3d_game/lib/shooter.dart` — a file the game layer's barrel
/// deliberately did not export, so that a game had to ask for it by name. That
/// worked as a rule and not as a boundary: the file still sat in the engine's
/// package, and so did the weapons, the inventory and the step order it needs.
/// Now the boundary is the package, and the rule is enforced by resolution
/// rather than by discipline.
///
/// What the engine keeps is in its `actors/`: a body that walks, health that
/// runs out, turning, steering round corners, a line-of-sight test, and a
/// [Brain] that decides. This is one brain.
library;

export 'bestiary.dart';
export 'chase_brain.dart';
export 'monster_def.dart';
