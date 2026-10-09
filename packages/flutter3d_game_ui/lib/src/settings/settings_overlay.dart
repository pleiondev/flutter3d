import 'package:flutter/material.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

import '../l10n/game_localizations.dart';
import '../theme/game_ui_theme.dart';
import 'settings_panel.dart';
import 'settings_sections.dart';

/// The gear, and the panel it opens. The mouse twin of `settingsKeys`.
///
/// **All three games had written this out, and the copies had drifted.** The
/// same forty lines: a builder over the settings, a gear eighteen from the
/// right and sixteen from the top, and a panel with a dozen arguments — of
/// which the racing game got one wrong for as long as it had a panel.
///
/// What a game answers differently is [sections] — what it lets a player
/// change, whose work it credits — and what has to happen before a panel
/// appears, [opening]. Everything else the [GameSettingsController] knows.
///
/// It is [Positioned], so it belongs to a [Stack] — the same one the game's own
/// heads-up display is in.
class SettingsOverlay extends StatelessWidget {
  const SettingsOverlay({
    super.key,
    required this.settings,
    required this.sections,
    required this.opening,
    this.canOpen = true,
  });

  final GameSettingsController settings;

  /// What the panel shows; `SettingsSection.standard(...)` for the panel
  /// every game had.
  final List<SettingsSection> sections;

  /// Everything that has to happen before a panel is on screen: letting the
  /// pointer go, and letting the held keys go. The same callback
  /// `settingsKeys` takes, and for the same reasons — a panel opened by a gear
  /// and a panel opened by Escape have to arrive in the same state.
  final void Function() opening;

  /// Whether the gear is offered at all. False on a screen that carries the
  /// same settings itself: the platformer's title card, where a stray gear has
  /// nothing to add.
  ///
  /// An open panel stays open regardless — a game that reaches its title card
  /// with the settings up should not have them vanish.
  final bool canOpen;

  @override
  Widget build(BuildContext context) {
    // The panel and the gear are the same piece of state seen twice, so they
    // are built from it rather than from two flags that have to be kept
    // opposite.
    return ValueListenableBuilder<SettingsState>(
      valueListenable: settings,
      builder: (BuildContext context, SettingsState state, Widget? _) {
        if (state.isOpen) {
          return SettingsPanel(settings: settings, sections: sections);
        }
        if (!canOpen) return const SizedBox.shrink();
        // **Inside a `SafeArea`, which it was not.** `right: 18, top: 16` is
        // measured from the window, and on a notched handset held in
        // landscape the window's corner is under the cutout — so the only
        // way into the settings was a control the player could not see or
        // press.
        return Positioned.fill(
          child: SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 18.0, top: 16.0),
                child: IconButton(
                  tooltip: Flutter3dGameLocalizations.of(context).settings,
                  onPressed: () {
                    opening();
                    settings.show();
                  },
                  icon: Icon(
                    Icons.settings,
                    color: GameUiTheme.of(context).label,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
