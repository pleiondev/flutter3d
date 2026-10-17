/// Every part of flutter3d_game_physics, in one import.
///
/// The gameplay parts that need the native physics core, kept apart from
/// `flutter3d_game_kit` so a game that uses none of them compiles no C and
/// downloads nothing for it. Each is also a library of its own:
/// `ragdoll.dart`, `wrecks.dart`, `party.dart` and `elements.dart`.
library;

export 'elements.dart';
export 'party.dart';
export 'ragdoll.dart';
export 'wrecks.dart';
