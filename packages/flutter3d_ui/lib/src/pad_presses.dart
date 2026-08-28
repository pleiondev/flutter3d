import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:pad_input/pad_input.dart' show PadButton;

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
  /// What was down last frame, so an edge is per button.
  final Set<PadButton> _held = <PadButton>{};

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
  /// [menuButton] opens and closes [settings], and is what makes the panel
  /// reachable at all for a player who has no keyboard.
  ///
  /// **`settingsKeys` takes a `KeyEvent`.** Its own doc says Escape exists so
  /// that "a player on a controller, who never took the pointer, has a way
  /// in" — and Escape is a key. Nothing here had a path to `settings.toggle`,
  /// and no game bound one, so on a television, on a phone with a pad, or at a
  /// desk with the keyboard pushed aside, the only way into the panel was the
  /// on-screen gear and the only way out was the same.
  ///
  /// Null keeps the old behaviour exactly, for a caller that wants every
  /// button to mean "begin".
  bool offer(PadInput pad, SettingsCubit settings, {PadButton? menuButton}) {
    final held = pad.heldButtons;

    // **Per button, not over the whole held set.** `_held` used to be "is
    // anything down", so a player who died holding the accelerator had to let
    // go of everything before Start would register — the edge had already been
    // spent by the button they were still holding.
    final pressed = held.where((PadButton it) => !_held.contains(it)).toList();
    _held
      ..clear()
      ..addAll(held);
    if (pressed.isEmpty) return false;

    if (settings.state.waitingFor != null) {
      settings.capture(InputSource.pad(pressed.first.id));
      return false;
    }

    if (menuButton != null && pressed.contains(menuButton)) {
      settings.toggle();
      return false;
    }
    return true;
  }
}
