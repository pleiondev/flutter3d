import 'package:flutter/material.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

import '../l10n/game_localizations.dart';
import '../theme/game_ui_theme.dart';
import 'settings_sections.dart';

/// The settings, over the top of the paused game: a heading, [sections] one
/// under another, a line when the last save was refused, and the way back.
///
/// Flutter widgets, which is the one thing this stack gets for nothing: a
/// settings screen in a C++ engine is a small project of its own, and here it
/// is a `Slider` and a `Column`.
///
/// **What it offers is [sections]**, `SettingsSection.standard(...)` for the
/// panel every game had. The panel had a dozen arguments of which each game
/// used some, and a game that wanted one row more had to write the whole
/// screen again.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.sections,
  });

  /// What the sections read and change, and what is waiting and failed.
  final GameSettingsController settings;

  /// What the panel shows, in order.
  final List<SettingsSection> sections;

  @override
  Widget build(BuildContext context) {
    final words = Flutter3dGameLocalizations.of(context);
    final theme = GameUiTheme.of(context);
    // Rebuilt on every change, so a slider follows the value it set.
    return ValueListenableBuilder<SettingsState>(
      valueListenable: settings,
      builder: (BuildContext context, SettingsState state, Widget? _) =>
          ColoredBox(
            color: theme.scrim,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        words.settings,
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      for (final (index, section)
                          in sections.indexed) ...<Widget>[
                        if (index > 0) const SizedBox(height: 12),
                        section.build(context, settings, state),
                      ],
                      const SizedBox(height: 20),
                      // A write fails when a browser's quota has run out or a
                      // disk has filled; a player who moved every slider on a
                      // full disk is told, rather than losing them silently.
                      if (state.lastWriteFailed)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Text(
                            words.settingsNotSaved,
                            style: TextStyle(color: theme.warning),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          // Cancelling a waiting rebind is the controller's,
                          // because a panel closed any other way has to do
                          // the same thing.
                          onPressed: settings.hide,
                          child: Text(words.backToTheGame),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }
}
