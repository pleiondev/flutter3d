import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;

/// The numbers WCAG 2.2 at level AA asks of what this package draws, and
/// the arithmetic they are checked with.
///
/// **Numbers from the specification, not taste.** A game's own screens sit
/// over a picture nobody can predict, so "readable" has to be a ratio that
/// holds over any frame rather than a look somebody liked on one level. The
/// theme's tokens are held to these by [ContrastPair]; the widgets take the
/// platform's text size and stay whole at [textScale]; a full-screen change
/// of brightness goes through a `FlashLimit`.
abstract final class Wcag {
  /// The least contrast ratio body text needs against what is behind it
  /// (success criterion 1.4.3), a ratio of relative luminances each plus
  /// 0.05, from 1 to 21.
  static const double textContrast = 4.5;

  /// The least contrast ratio large text needs (1.4.3): 18 points, or 14
  /// bold, and up. A ratio, as [textContrast]. No pair of this theme is
  /// held to it, since a token is drawn at every size; it is for a game
  /// that checks a title of its own with a [ContrastPair].
  static const double largeTextContrast = 3.0;

  /// The least contrast ratio the parts of a control a player needs to find
  /// it by need against what is next to them (1.4.11). A ratio, as
  /// [textContrast].
  static const double nonTextContrast = 3.0;

  /// How large the text has to be able to grow without anything being lost
  /// (1.4.4), as a factor of the size it was written at.
  static const double textScale = 2.0;

  /// The smallest side of a target a pointer has to hit (2.5.8), in logical
  /// pixels.
  static const double targetSize = 24.0;

  /// The most flashes anything may make in any one second (2.3.1).
  static const int flashesPerSecond = 3;

  /// How far a change of brightness has to go to count as one half of a
  /// flash (2.3.1's general flash threshold: ten percent of the relative
  /// luminance), as a fraction of the whole range from nought to one.
  static const double flashLuminanceChange = 0.1;

  /// The relative luminance of [color]'s red, green and blue, from nought
  /// for black to one for white, ignoring its alpha (WCAG 2.x's definition,
  /// from linearised sRGB).
  static double luminance(Color color) {
    double linear(double channel) => channel <= 0.04045
        ? channel / 12.92
        : Portable.pow((channel + 0.055) / 1.055, 2.4);
    return 0.2126 * linear(color.r) +
        0.7152 * linear(color.g) +
        0.0722 * linear(color.b);
  }

  /// The contrast ratio between two opaque colours, from 1 (the same) to 21
  /// (black on white), whichever way round they are given.
  static double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// [top] drawn over the opaque [under], in sRGB as a canvas blends it:
  /// the colour a reader actually sees.
  static Color over(Color top, Color under) => Color.from(
    alpha: 1.0,
    red: top.a * top.r + (1 - top.a) * under.r,
    green: top.a * top.g + (1 - top.a) * under.g,
    blue: top.a * top.b + (1 - top.a) * under.b,
  );
}

/// Two of a theme's colours a player has to tell apart, and how far apart
/// they have to be.
///
/// **Over any frame, because the frame is the game's.** A heads-up line is
/// drawn on a translucent panel over whatever the camera sees, so its
/// contrast is not one number: it is the worst of all the pictures that can
/// be behind it. [worstRatio] composites [background] over every grey from
/// black to white, [foreground] over that, and keeps the lowest ratio.
///
/// **A control may be found by its rim.** A dark translucent face vanishes
/// over a dark frame, and a light rim vanishes over a light one; a player
/// finds the control by whichever of the two stands out, so a pair with an
/// [edge] counts, at each frame, the better of the face and the rim.
final class ContrastPair {
  const ContrastPair(
    this.name, {
    required this.foreground,
    this.background = const Color(0x00000000),
    this.minimum = Wcag.textContrast,
    this.edge,
  });

  /// What the pair is, in the theme's words: `faint on scrim`.
  final String name;

  /// What is read or found: text, a dot, a control's face.
  final Color foreground;

  /// What [foreground] is drawn on, itself over the game's frame; clear for
  /// a control drawn straight onto the frame.
  final Color background;

  /// The ratio the pair has to keep: [Wcag.textContrast] for text,
  /// [Wcag.largeTextContrast] for large text, [Wcag.nonTextContrast] for a
  /// control or a mark on a map. A ratio, from 1 to 21.
  final double minimum;

  /// A rim drawn round [foreground] onto the frame, which carries the
  /// contrast where the face meets a frame of its own shade; null for none.
  final Color? edge;

  /// The ratio over the opaque [frame]: [foreground] against [background],
  /// both as drawn over it, or the rim against the frame where that is
  /// better. A ratio, from 1 to 21.
  double ratioOver(Color frame) {
    final behind = Wcag.over(background, frame);
    final face = Wcag.contrast(Wcag.over(foreground, behind), behind);
    final rim = edge;
    if (rim == null) return face;
    return math.max(face, Wcag.contrast(Wcag.over(rim, frame), frame));
  }

  /// The lowest [ratioOver] any grey frame from black to white gives, in
  /// steps of five levels of 255. A ratio, from 1 to 21.
  double get worstRatio => <double>[
    for (var level = 0; level <= 255; level += 5)
      ratioOver(Color.fromARGB(255, level, level, level)),
  ].reduce(math.min);

  /// Whether [worstRatio] reaches [minimum].
  bool get isMet => worstRatio >= minimum;

  @override
  String toString() =>
      'ContrastPair($name, ${worstRatio.toStringAsFixed(2)} of $minimum)';
}
