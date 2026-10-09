import 'package:flutter/painting.dart' show Color;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_ui/access.dart' show RoleRings;
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'hud.dart';

/// What the crypt rings under the high-contrast look, and in which colour —
/// `N9`. The engine draws a ring round whatever carries a colour, the
/// visuals put the colour on, and [RoleRings] reads the colour the player
/// chose for a role; this is the game's half, the one question of what
/// matters.
///
/// Read from [settings] every frame, so a role colour the player changes in the
/// settings is the ring's colour on the next one.
final class CryptRings {
  CryptRings(this.settings) : _rings = RoleRings(dungeonColours, settings);

  /// The player's settings as they are now.
  final GameSettings Function() settings;
  final RoleRings _rings;

  /// A living monster, in the monsters' colour. The dead are not ringed: a
  /// corpse cannot hurt anybody, and a ring left on it would be one more
  /// thing in the room to rule out.
  Vector3? actor(Actor actor) => actor.isAlive
      ? _rings.of('monster', fallback: const Color(0xFFD55E00))
      : null;

  /// A pickup still on the floor: a key in its own colour, anything else in
  /// the pickups'. Doors, lifts and torches are the room, not the quarry.
  Vector3? fixture(Fixture fixture) {
    final mechanism = fixture.mechanism;
    if (mechanism is! Pickup || mechanism.isTaken) return null;
    final key = 'key.${mechanism.detail}';
    return _rings.has(key)
        ? _rings.of(key, fallback: const Color(0xFFFFFFFF))
        : _rings.of('pickup', fallback: const Color(0xFF009E73));
  }
}
