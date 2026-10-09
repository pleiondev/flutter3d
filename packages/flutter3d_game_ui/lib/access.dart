/// Accessibility for a game on flutter3d, past what the engine's settings
/// already do: rings in the colour a player chose for what they mean, roles
/// moved apart for the player's colour vision, and what happens in the game
/// spoken to a screen reader.
///
/// - [RoleRings]: the high-contrast look's ring colour for a role, read from
///   the player's settings every frame.
/// - [RolesApart]: which palette colour each colliding role should take, so
///   the roles seen together stay apart for the player's deficiency.
/// - [SpokenEvents]: a view plugin that says the events of a table aloud
///   through Flutter's semantics, once each, rate-limited by step.
///
/// The correction of the whole picture (`ColorVisionLook`), the role table
/// (`ColorRoles`) and the settings a player picks them in are
/// `flutter3d_game`'s, and this library builds on them rather than repeating
/// them.
library;

export 'src/access/role_rings.dart';
export 'src/access/roles_apart.dart';
export 'src/access/spoken_events.dart';
