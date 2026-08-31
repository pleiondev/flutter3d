import 'package:flutter/material.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:pad_input/pad_input.dart' show Deadzone;
import 'settings_panel_controls.dart';
import 'volumes.dart';

/// Volume sliders and the keys, over the top of the paused game.
///
/// Flutter widgets, which is the one thing this stack gets for nothing: a
/// settings screen in a C++ engine is a small project of its own, and here it
/// is a `Slider` and a `Column`.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.mixer,
    required this.bindings,
    required this.config,
    required this.padConnected,
    required this.onVolume,
    required this.onSetting,
    required this.onClose,
    required this.actions,
    required this.waitingFor,
    required this.onRebind,
    required this.onResetControls,
    this.credits,
  });

  final Mixer mixer;
  final Bindings bindings;

  /// Read for the numbers that are not volumes, and written by [onSetting].
  final GameConfig config;

  /// Whether a controller answered this frame, so the panel can say when a
  /// slider has nothing to act on.
  final bool padConnected;

  final void Function(AudioBus bus, double volume) onVolume;
  final void Function(String name, double value) onSetting;
  final VoidCallback onClose;

  /// What can be rebound, in the order a player reads it. The game's list, not
  /// the engine's: this one has a dash and a drop-through in it.
  final List<GameAction> actions;

  /// Which action is listening for its new control, if any.
  final GameAction? waitingFor;

  /// Starts listening for `action`, or stops when handed null.
  final void Function(GameAction? action) onRebind;

  final VoidCallback onResetControls;

  /// What the game owes the people whose work it ships, if anything.
  ///
  /// A widget rather than a list, because what a credit *is* differs per game —
  /// one has models under CC BY and one has an author it cannot trace — and this
  /// screen's only job is to be somewhere a player reliably reaches. A game with
  /// nothing to declare passes nothing.
  final Widget? credits;

  /// **Music was missing here**, and a commit message claimed it was not. The
  /// mixer has had the bus since the soundtrack landed and the application was
  /// already restoring its saved volume; the panel simply never offered it, so
  /// the one slider a player reaches for first was the one that did not exist.
  /// The list lives in `volumes.dart` now, beside the call that applies them —
  /// see [settableBuses] for the day these two disagreed.
  static const List<AudioBus> _buses = settableBuses;

  /// A dead zone above this is a controller with a hole in the middle of it.
  ///
  /// The range matters more than the default: the point of the slider is that
  /// **a dead zone can only be chosen with a controller in hand**, and a range
  /// too narrow to reach the player's own stick would make the slider a
  /// decoration.
  static const double _maxDeadzone = 0.4;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                for (final bus in _buses) ...<Widget>[
                  SettingsHeading(bus.name),
                  Slider(
                    value: mixer.volumeOf(bus),
                    onChanged: (double value) => onVolume(bus, value),
                  ),
                ],
                const SizedBox(height: 12),
                const SettingsHeading('Controls'),
                const SizedBox(height: 8),
                // Read from the same table the keyboard reads, so a rebinding
                // that never reached the game cannot look as though it did.
                for (final action in actions)
                  SettingsBindingRow(
                    action: action,
                    sources: bindings.sourcesFor(action).toList(),
                    waiting: waitingFor == action,
                    onTap: () => onRebind(waitingFor == action ? null : action),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onResetControls,
                    child: const Text('Reset controls'),
                  ),
                ),
                const SizedBox(height: 12),
                const SettingsHeading('Accessibility'),
                const SizedBox(height: 8),
                SettingsValueSlider(
                  label: 'Camera motion',
                  value: config.settingOf('a11y.cameraMotion', 1.0),
                  max: 1.0,
                  // A camera that flinches on every landing is what makes some
                  // players ill, and the following is the game. This turns down
                  // the first and leaves the second.
                  onChanged: (double value) =>
                      onSetting('a11y.cameraMotion', value),
                ),
                SettingsSwitchRow(
                  label: 'Hold to sprint',
                  // Reads as the thing being turned off, because that is what a
                  // player looks for: they know they cannot hold a key.
                  on: config.settingOf('a11y.toggleSprint', 0.0) < 0.5,
                  onChanged: (bool hold) =>
                      onSetting('a11y.toggleSprint', hold ? 0.0 : 1.0),
                ),
                const SizedBox(height: 12),
                SettingsHeading(
                  padConnected ? 'Gamepad' : 'Gamepad (none connected)',
                ),
                const SizedBox(height: 8),
                SettingsValueSlider(
                  label: 'Dead zone',
                  value: config.settingOf(
                    'pad.deadzone.stick',
                    const Deadzone().stick,
                  ),
                  max: _maxDeadzone,
                  // Left of the mark a resting stick drifts; right of it there
                  // is a hole in the middle of the travel. Both are visible in
                  // seconds, which is the only way to settle the number.
                  onChanged: (double value) =>
                      onSetting('pad.deadzone.stick', value),
                ),
                SettingsValueSlider(
                  label: 'Look speed',
                  value: config.settingOf(
                    'pad.look',
                    PadRoutes.defaultLookRate,
                  ),
                  min: 200.0,
                  max: 2600.0,
                  onChanged: (double value) => onSetting('pad.look', value),
                ),
                if (credits != null) ...<Widget>[
                  const SizedBox(height: 18),
                  credits!,
                ],
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onClose,
                    child: const Text('Back to the game'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
