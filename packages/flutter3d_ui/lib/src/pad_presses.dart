import 'package:flutter3d_game/flutter3d_game.dart';

import 'settings_cubit.dart';

/// The pad, as a screen reads it rather than as the game does.
///
/// **Two things no simulation has a verb for**: taking down a title card and
/// starting a finished run over. All three games read them off the pad by hand,
/// and none of them bound them to actions — deliberately, so the binding table
/// holds only words the game logic actually reads. What they did not agree on
/// was the rest of it.
///
/// A press is an **edge**. A player who dies with a thumb on Start would
/// otherwise restart for ever, sixty times a second, and never see the screen
/// that told them they died. The platformer and the racing game each kept a
/// `_padPressing` flag for this; the dungeon kept one too and then offered the
/// rebinding a *held* button rather than a pressed one, so a controller resting
/// against something bound itself to whatever the panel was waiting for.
///
/// The settings are asked first, for the reason `settingsKeys` gives about the
/// keyboard: a controller has to be remappable from the controller, which is
/// the whole point for a player who has one of the two devices.
final class PadPresses {
  bool _held = false;

  /// Offers this frame's press to [settings], and says whether anything is
  /// left over for the screen.
  ///
  /// False while a button is held, false on the frame the settings took the
  /// press, and false when nothing is pressed at all — so a caller's own clause
  /// reads as `if (presses.offer(pad, settings)) …` and cannot fire twice for
  /// one thumb.
  ///
  /// Which button it was stays on the pad: a caller that cares asks
  /// [PadInput.heldButtons], and a caller that does not — a title card, where
  /// **any** button begins, which is also how a browser reveals the pad to the
  /// page in the first place — does not have to.
  bool offer(PadInput pad, SettingsCubit settings) {
    final held = pad.heldButtons;
    final pressing = held.isNotEmpty;
    final wasPressing = _held;
    _held = pressing;
    if (!pressing || wasPressing) return false;

    if (settings.state.waitingFor != null) {
      settings.capture(InputSource.pad(held.first.id));
      return false;
    }
    return true;
  }
}
