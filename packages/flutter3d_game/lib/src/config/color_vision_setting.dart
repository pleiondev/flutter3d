import 'package:flutter3d/flutter3d.dart';

import 'game_config.dart';

// The choices' names are words a player reads, so they are
// `Flutter3dGameLocalizations.colorVisionChoices`, in the player's language.

/// The correction [config] asks for, or null for none.
///
/// **A correction, never a simulation.** A player picks what they see; the
/// picture of how somebody else sees is for the developer, who asks for it
/// with `ColorVision.simulate` directly.
ColorVision? colorVisionOf(GameSettings config) {
  final chosen = config.valueOf(GameSettingKeys.colorVision);
  if (chosen < 1 || chosen > ColorVisionDeficiency.values.length) return null;
  return ColorVision.correct(ColorVisionDeficiency.values[chosen - 1]);
}

/// The look a frame is drawn with for the player's colour vision.
///
/// Holds a colour table per kind once one has been asked for, and hands the
/// one the setting names to [LookSettings.lut] — at most three tables for
/// the life of the device, since `GraphicsDevice` has no way to let one go
/// and a table made on every change of mind would be a leak.
final class ColorVisionLook {
  ColorVisionLook(this.device);

  final GraphicsDevice device;

  final Map<ColorVisionDeficiency, TextureHandle?> _tables =
      <ColorVisionDeficiency, TextureHandle?>{};

  /// [base] with the correction [config] asks for. A [base] with a table of
  /// its own keeps it: a grade and a correction compose into one table with
  /// `ColorVision.toStrip(grade:)`, which a game with a grade does itself.
  LookSettings of(
    GameSettings config, [
    LookSettings base = const LookSettings(),
  ]) {
    final vision = colorVisionOf(config);
    if (vision == null || base.lut != null) return base;
    final table = _tables.putIfAbsent(
      vision.deficiency,
      () => vision.upload(device),
    );
    return table == null ? base : base.copyWith(lut: table);
  }
}
