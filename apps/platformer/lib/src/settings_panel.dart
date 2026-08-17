import 'package:flutter/material.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:gamepad/gamepad.dart' show Deadzone;

import 'credits.dart';

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

  /// **Music was missing here**, and a commit message claimed it was not. The
  /// mixer has had the bus since the soundtrack landed and the application was
  /// already restoring its saved volume; the panel simply never offered it, so
  /// the one slider a player reaches for first was the one that did not exist.
  static const List<AudioBus> _buses = <AudioBus>[
    AudioBus.master,
    AudioBus.music,
    AudioBus.sfx,
  ];

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
                  _Heading(bus.name),
                  Slider(
                    value: mixer.volumeOf(bus),
                    onChanged: (double value) => onVolume(bus, value),
                  ),
                ],
                const SizedBox(height: 12),
                const _Heading('Controls'),
                const SizedBox(height: 8),
                // Read from the same table the keyboard reads, so a rebinding
                // that never reached the game cannot look as though it did.
                for (final action in GameAction.common)
                  _Binding(
                    action: action.name,
                    sources: bindings.sourcesFor(action).length,
                  ),
                const SizedBox(height: 12),
                _Heading(
                  padConnected ? 'Gamepad' : 'Gamepad (none connected)',
                ),
                const SizedBox(height: 8),
                _Setting(
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
                _Setting(
                  label: 'Look speed',
                  value: config.settingOf(
                    'pad.look',
                    PadRoutes.defaultLookRate,
                  ),
                  min: 200.0,
                  max: 2600.0,
                  onChanged: (double value) => onSetting('pad.look', value),
                ),
                const SizedBox(height: 18),
                const CreditsSection(),
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

/// A section label, spelled once instead of four times.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.75),
          letterSpacing: 2,
          fontSize: 12,
        ),
      );
}

/// A slider over a number that is not a fraction, showing what it says.
///
/// The value is printed because these two cannot be judged by the position of a
/// handle: a dead zone is a hundredth of a stick's travel, and a look speed is
/// only meaningful next to the number a player had before they touched it.
class _Setting extends StatelessWidget {
  const _Setting({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    required this.max,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            max <= 1.0 ? value.toStringAsFixed(2) : value.round().toString(),
            textAlign: TextAlign.right,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ),
      ],
    );
  }
}

class _Binding extends StatelessWidget {
  const _Binding({required this.action, required this.sources});

  final String action;
  final int sources;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(action, style: const TextStyle(color: Colors.white)),
          Text(
            // Not "keys": the table holds a controller's buttons too now, and a
            // row saying "2 keys" for a key and a face button would be a lie in
            // the one place a player goes to find out what is bound.
            sources == 1 ? '1 control' : '$sources controls',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
