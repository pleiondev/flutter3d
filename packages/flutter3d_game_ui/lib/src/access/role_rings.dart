import 'dart:ui' show Color;

import 'package:flutter3d_game/flutter3d_game.dart'
    show ColorRoles, GameSettings, outlineColorOf;
import 'package:vector_math/vector_math.dart' show Vector3;

/// The colour of the ring the high-contrast look draws round something that
/// matters, by what it means: `'threat'`, `'pickup'`, `'key.brass'`.
///
/// **The game's question is what matters; this is the colour it is in.** The
/// engine rings whatever node carries an outline colour, and a game's
/// visuals hand one over for an actor or a fixture through `outlineOf`. What
/// a game decides is which of them are worth a ring at all, and under which
/// role; what this decides is that the role's colour is the one the player
/// chose for it in the settings, read from [settings] every time, so a change
/// in the panel is the ring's colour on the next frame.
///
/// ```dart
/// final rings = RoleRings(myColours, () => controller.settings);
/// visuals.outlineOf ??= (Actor actor) =>
///     actor.isAlive ? rings.of('threat', fallback: vermillion) : null;
/// ```
final class RoleRings {
  const RoleRings(this.roles, this.settings);

  /// The colours the game gives meanings to.
  final ColorRoles roles;

  /// The player's settings as they are now: asked on every [of], since a
  /// [GameSettings] is a value and a change makes a new one.
  final GameSettings Function() settings;

  /// The ring colour of the role called [role]: the player's choice, its own
  /// colour, or [fallback] when [roles] has no such role.
  Vector3 of(String role, {required Color fallback}) =>
      outlineColorOf(roles.colorOf(role, settings(), fallback: fallback));

  /// Whether [roles] has a role called [role]: a key that has a colour of its
  /// own is ringed in it, and one that has none in the colour of its kind.
  bool has(String role) => roles.named(role) != null;
}
