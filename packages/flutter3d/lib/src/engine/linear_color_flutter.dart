/// The crossing between Flutter's `Color` and the engine's [LinearColor].
///
/// Decision 11 of `tasks/1.0-api-review.md`: the engine has one colour type,
/// linear, and Flutter's `Color` appears only in widgets. A widget that takes
/// a colour from a theme or a picker hands it to the engine through
/// [ColorToLinear.toLinear]; one that shows an engine colour back to a person
/// takes it through [LinearColorToFlutter.toColor]. `flutter3d_plugin_api`
/// cannot hold either, because it does not depend on Flutter.
library;

import 'dart:ui' show Color, ColorSpace;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;

/// A Flutter [Color] decoded into linear light.
extension ColorToLinear on Color {
  /// This colour as a [LinearColor], for a caller passing a colour a person
  /// picked (a theme, a swatch, a hex literal) into the engine.
  ///
  /// A `Color` holds encoded values, so each channel goes through the exact
  /// sRGB curve. A Display P3 colour is first converted to extended sRGB, so
  /// a colour outside the sRGB gamut keeps its negative or above-1 channels
  /// rather than being clipped; alpha is copied as it is.
  LinearColor toLinear() {
    final srgb = colorSpace == ColorSpace.displayP3
        ? withValues(colorSpace: ColorSpace.extendedSRGB)
        : this;
    return LinearColor.fromSrgb(srgb.r, srgb.g, srgb.b, srgb.a);
  }
}

/// A [LinearColor] encoded as a Flutter [Color].
extension LinearColorToFlutter on LinearColor {
  /// This colour as a Flutter [Color], for a caller showing an engine colour
  /// in a widget.
  ///
  /// The channels are encoded with the sRGB curve. A colour inside 0..1 comes
  /// back in [ColorSpace.sRGB]; one brighter than white or outside the gamut
  /// comes back in [ColorSpace.extendedSRGB], so nothing is clipped before the
  /// widget decides how to draw it.
  Color toColor() {
    final srgb = toSrgb();
    final inGamut = <double>[
      srgb.r,
      srgb.g,
      srgb.b,
    ].every((double c) => c >= 0 && c <= 1);
    return Color.from(
      alpha: a.clamp(0, 1).toDouble(),
      red: srgb.r,
      green: srgb.g,
      blue: srgb.b,
      colorSpace: inGamut ? ColorSpace.sRGB : ColorSpace.extendedSRGB,
    );
  }
}
