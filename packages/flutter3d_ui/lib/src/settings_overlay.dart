import 'package:flutter/material.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'settings_cubit.dart';
import 'settings_panel.dart';

/// The gear, and the panel it opens. The mouse twin of `settingsKeys`.
///
/// **All three games had written this out, and the copies had drifted.** The
/// same forty lines: a `BlocBuilder`, a gear eighteen from the right and
/// sixteen from the top, and a [SettingsPanel] with a dozen arguments — of
/// which the racing game got one wrong for as long as it had a panel, telling
/// it there was no controller connected while the other two asked the pad.
/// That is what three copies of a widget cost: not the lines, but the one line
/// in one copy that nobody was comparing against anything.
///
/// The parameters that remain are the ones a game genuinely answers
/// differently — what it lets a player rebind, whose work it credits, and what
/// has to happen before a panel appears. Everything else the cubit already
/// knows, so the volume, the setting, the rebind and the close are wired here
/// rather than in three `main.dart`s that each forwarded them by hand.
///
/// It is [Positioned], so it belongs to a [Stack] — the same one the game's own
/// heads-up display is in.
class SettingsOverlay extends StatelessWidget {
  const SettingsOverlay({
    super.key,
    required this.settings,
    required this.mixer,
    required this.bindings,
    required this.config,
    required this.padConnected,
    required this.actions,
    required this.defaultBindings,
    required this.opening,
    this.credits,
    this.canOpen = true,
  });

  final SettingsCubit settings;

  final Mixer mixer;
  final Bindings bindings;
  final GameConfig config;

  /// Whether a controller answered this frame.
  ///
  /// **Asked, not assumed.** A game that passes a constant here is a game whose
  /// panel says "none connected" over the sliders that set a stick's dead zone,
  /// and nothing fails — the screen simply lies.
  final bool padConnected;

  /// What this game lets a player rebind, in the order the panel lists it.
  final List<GameAction> actions;

  /// The table this game ships, for the day somebody wants it back.
  final Bindings Function() defaultBindings;

  /// Everything that has to happen before a panel is on screen: letting the
  /// pointer go, and letting the held keys go. The same callback
  /// `settingsKeys` takes, and for the same reasons — a panel opened by a gear
  /// and a panel opened by Escape have to arrive in the same state.
  final void Function() opening;

  /// What the game owes the people whose work it ships, if anything.
  final Widget? credits;

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
    return BlocBuilder<SettingsCubit, SettingsState>(
      bloc: settings,
      builder: (BuildContext context, SettingsState state) {
        if (!state.isOpen) {
          if (!canOpen) return const SizedBox.shrink();
          return Positioned(
            right: 18,
            top: 16,
            child: IconButton(
              tooltip: 'Settings',
              onPressed: () {
                opening();
                settings.show();
              },
              icon: const Icon(Icons.settings, color: Colors.white70),
            ),
          );
        }
        return SettingsPanel(
          mixer: mixer,
          bindings: bindings,
          config: config,
          padConnected: padConnected,
          actions: actions,
          waitingFor: state.waitingFor,
          credits: credits,
          onVolume: (AudioBus bus, double volume) =>
              settings.setVolume(bus.name, volume),
          onSetting: settings.setSetting,
          onRebind: settings.rebind,
          onResetControls: () => settings.resetControls(defaultBindings()),
          // Cancelling a waiting rebind is the cubit's, because a panel closed
          // any other way — Escape, the pad — has to do the same thing and used
          // not to.
          onClose: settings.hide,
        );
      },
    );
  }
}
