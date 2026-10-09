import 'dart:ui' show Color;

import 'package:flutter3d_core/flutter3d_core.dart'
    show ColorVision, ColorVisionDeficiency;
import 'package:flutter3d_game/flutter3d_game.dart'
    show ColorRoles, GameSettingKeys, GameSettings, colorVisionOf;

/// Colour roles moved apart for the player's colour vision: the palette
/// choice each colliding role should take so that the roles seen together
/// stay apart for the eyes the player said they have.
///
/// **What the engine already does, and what this adds.** `flutter3d_game`
/// corrects the whole picture for a deficiency (`ColorVisionLook`), lets a
/// player pick each role's colour from Okabe and Ito's eight (`ColorRoles`),
/// and finds the pairs a deficiency runs together (`ColorRoles.confusions`).
/// What none of them does is answer the next question, the one the player
/// is left with: *which* colour to pick. This answers it, as a settings
/// panel's "choose for me" would.
///
/// **Only the player's own deficiency**, read from
/// [GameSettingKeys.colorVision]; with
/// none set there is nothing to move. Roles are settled in the order given,
/// so the first of two colliding roles keeps its colour and the second moves.
final class RolesApart {
  const RolesApart(this.roles, {this.within = 20.0});

  /// The colours the game gives meanings to.
  final ColorRoles roles;

  /// How far apart two roles must look to the player, in CIE 1976 ΔE units —
  /// the same threshold `ColorVision.confusions` uses.
  final double within;

  /// The deficiency [config] names, or null for none.
  static ColorVisionDeficiency? deficiencyOf(GameSettings config) =>
      colorVisionOf(config)?.deficiency;

  /// For each of [names] that runs into one settled before it, the choice
  /// (an index into `ColorRoles.choices`, the value of its setting) that
  /// keeps it apart from all of them; empty when [config] names no
  /// deficiency or nothing collides. A role no choice can save is left out:
  /// it needs a second cue, a letter or a shape, rather than a third colour.
  Map<String, int> choicesFor(Iterable<String> names, GameSettings config) {
    final deficiency = deficiencyOf(config);
    if (deficiency == null) return const <String, int>{};
    final sees = ColorVision.simulate(deficiency);
    (double, double, double) seen(Color c) => sees.applyEncoded(c.r, c.g, c.b);
    bool apart(Color a, Color b) =>
        ColorVision.difference(seen(a), seen(b)) >= within;

    final settled = <Color>[];
    final moved = <String, int>{};
    for (final name in names) {
      final role = roles.named(name);
      if (role == null) continue;
      final current = roles.of(role, config);
      if (settled.every((Color other) => apart(current, other))) {
        settled.add(current);
        continue;
      }
      final options = ColorRoles.choices(role);
      final pick = _firstApart(options, settled, apart);
      if (pick == null) {
        settled.add(current);
        continue;
      }
      moved[name] = pick;
      settled.add(options[pick]);
    }
    return moved;
  }

  /// [config] with [choicesFor] written in: each moved role's setting set
  /// to its choice. The roles it moved are [choicesFor]'s.
  GameSettings apply(Iterable<String> names, GameSettings config) =>
      choicesFor(names, config).entries.fold(
        config,
        (GameSettings settings, MapEntry<String, int> moved) =>
            settings.withValue(roles.named(moved.key)!.setting, moved.value),
      );

  static int? _firstApart(
    List<Color> options,
    List<Color> settled,
    bool Function(Color a, Color b) apart,
  ) {
    for (var i = 0; i < options.length; i++) {
      if (settled.every((Color other) => apart(options[i], other))) return i;
    }
    return null;
  }
}
