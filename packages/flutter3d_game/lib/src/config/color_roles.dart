import 'dart:ui' show Color;

import 'package:flutter3d/flutter3d.dart'
    show ColorVision, ColorVisionDeficiency;

import 'game_config.dart';

/// A colour that means something: what it is for, what the panel calls it,
/// and what it is until the player says otherwise.
final class ColorRole {
  const ColorRole(this.name, this.label, this.colour);

  /// What the setting is stored under, `colour.<name>`.
  final String name;

  /// What the settings panel calls it.
  final String label;

  /// What it is by default.
  final Color colour;

  /// The setting this role's choice is kept in.
  String get setting => 'colour.$name';
}

/// The colours a game gives meanings to, and the ones a player has chosen
/// in their place.
///
/// **A meaning, not a colour, is what a HUD asks for.** A key's mark asks
/// for "the brass key" and is given whatever the player has picked for it,
/// so a player who cannot tell two marks apart changes one of them rather
/// than turning down the whole picture.
///
/// The choice is from [choices]: the role's own colour, or one of the eight
/// of Okabe and Ito's palette, chosen to stay apart for every common kind of
/// colour blindness — a short list a player can go through, rather than a
/// picker in which most of the colours are the problem.
final class ColorRoles {
  ColorRoles(List<ColorRole> roles)
    : roles = List<ColorRole>.unmodifiable(roles);

  final List<ColorRole> roles;

  /// Okabe and Ito's eight, in their order: black, orange, sky blue, bluish
  /// green, yellow, blue, vermillion, reddish purple.
  static const List<Color> palette = <Color>[
    Color(0xFF000000),
    Color(0xFFE69F00),
    Color(0xFF56B4E9),
    Color(0xFF009E73),
    Color(0xFFF0E442),
    Color(0xFF0072B2),
    Color(0xFFD55E00),
    Color(0xFFCC79A7),
  ];

  /// What [role] may be: its own colour first, then [palette].
  static List<Color> choices(ColorRole role) => <Color>[
    role.colour,
    ...palette,
  ];

  /// The role called [name], or null.
  ColorRole? named(String name) {
    for (final role in roles) {
      if (role.name == name) return role;
    }
    return null;
  }

  /// The colour [role] is in [config]: the player's choice, or its own.
  Color of(ColorRole role, GameConfig config) {
    final chosen = config.settingOf(role.setting, 0.0).round();
    final options = choices(role);
    return chosen > 0 && chosen < options.length
        ? options[chosen]
        : role.colour;
  }

  /// The colour of the role called [name], or [fallback] when there is none.
  Color colourOf(String name, GameConfig config, {required Color fallback}) {
    final role = named(name);
    return role == null ? fallback : of(role, config);
  }

  /// Of [names] — the roles that are seen together, a level's keys — the
  /// pairs someone missing a cone runs together, in the colours [config]
  /// gives them. See [ColorVision.confusions].
  List<({String a, String b, ColorVisionDeficiency by, double distance})>
  confusions(Iterable<String> names, GameConfig config) =>
      ColorVision.confusions(<String, (double, double, double)>{
        for (final name in names)
          if (named(name) case final ColorRole role)
            name: (of(role, config).r, of(role, config).g, of(role, config).b),
      });
}
