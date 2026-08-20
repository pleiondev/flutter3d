import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:gamepad/gamepad.dart' show Deadzone;
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

  /// Starts listening for [action], or stops when handed null.
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
                for (final action in actions)
                  _Binding(
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
                const _Heading('Accessibility'),
                const SizedBox(height: 8),
                _Setting(
                  label: 'Camera motion',
                  value: config.settingOf('a11y.cameraMotion', 1.0),
                  max: 1.0,
                  // A camera that flinches on every landing is what makes some
                  // players ill, and the following is the game. This turns down
                  // the first and leaves the second.
                  onChanged: (double value) =>
                      onSetting('a11y.cameraMotion', value),
                ),
                _Switch(
                  label: 'Hold to sprint',
                  // Reads as the thing being turned off, because that is what a
                  // player looks for: they know they cannot hold a key.
                  on: config.settingOf('a11y.toggleSprint', 0.0) < 0.5,
                  onChanged: (bool hold) =>
                      onSetting('a11y.toggleSprint', hold ? 0.0 : 1.0),
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
    return MergeSemantics(
      child: Row(
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
    ),
    );
  }
}

/// One action, what it is bound to, and a way to change it.
class _Binding extends StatelessWidget {
  const _Binding({
    required this.action,
    required this.sources,
    required this.waiting,
    required this.onTap,
  });

  final GameAction action;
  final List<InputSource> sources;
  final bool waiting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String bound;
    if (waiting) {
      bound = 'press a key or a button';
    } else if (sources.isEmpty) {
      // Worth saying out loud rather than showing an empty space: an action
      // bound to nothing is a verb the player cannot reach, which is the exact
      // condition this screen exists to fix.
      bound = 'nothing';
    } else {
      bound = sources.map(_describe).join(', ');
    }

    return MergeSemantics(
      child: Semantics(
        button: true,
        label: '${action.name}, bound to $bound',
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(action.name, style: const TextStyle(color: Colors.white)),
                Flexible(
                  child: Text(
                    bound,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: waiting
                          ? Colors.amber
                          : Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Keys whose label is not a thing to put on screen.
  ///
  /// **`LogicalKeyboardKey.debugName` would have answered all of these and is
  /// deliberately not used**: it is stripped in a release build, so a panel
  /// built on it reads perfectly in development and shows nothing to a player.
  /// `keyLabel` is the supported one, and for space it is a space — which is why
  /// this table exists rather than a fallback.
  ///
  /// `static final` rather than `const` because a key's id is not a constant
  /// expression. Only the keys this game binds; anything else falls through to
  /// its label.
  static final Map<int, String> _keyNames = <int, String>{
    LogicalKeyboardKey.space.keyId: 'Space',
    LogicalKeyboardKey.shiftLeft.keyId: 'Left Shift',
    LogicalKeyboardKey.shiftRight.keyId: 'Right Shift',
    LogicalKeyboardKey.controlLeft.keyId: 'Left Ctrl',
    LogicalKeyboardKey.controlRight.keyId: 'Right Ctrl',
    LogicalKeyboardKey.altLeft.keyId: 'Left Alt',
    LogicalKeyboardKey.altRight.keyId: 'Right Alt',
    LogicalKeyboardKey.escape.keyId: 'Escape',
    LogicalKeyboardKey.tab.keyId: 'Tab',
    LogicalKeyboardKey.enter.keyId: 'Enter',
    LogicalKeyboardKey.arrowUp.keyId: 'Up',
    LogicalKeyboardKey.arrowDown.keyId: 'Down',
    LogicalKeyboardKey.arrowLeft.keyId: 'Left',
    LogicalKeyboardKey.arrowRight.keyId: 'Right',
  };

  /// What to call a source on screen.
  ///
  /// The **identifier** is what gets saved and `key:32` is not a thing anybody
  /// can read, so this is the one place that translates — and it translates for
  /// showing only, never for storing. A pad button keeps its position name,
  /// because that is what it is: `face.south` is where the button sits, and
  /// there is no way to know what is printed on it.
  static String _describe(InputSource source) {
    if (source.id.startsWith(InputSource.padPrefix)) {
      return 'pad ${source.id.substring(InputSource.padPrefix.length)}';
    }
    if (!source.id.startsWith('key:')) return source.id;
    final id = int.tryParse(source.id.substring(4));
    if (id == null) return source.id;
    final named = _keyNames[id];
    if (named != null) return named;
    final label = LogicalKeyboardKey.findKeyByKeyId(id)?.keyLabel ?? '';
    return label.trim().isEmpty ? source.id : label;
  }
}

/// A setting that is on or off.
class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.on,
    required this.onChanged,
  });

  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
            ),
          ),
          Switch(value: on, onChanged: onChanged),
        ],
      ),
    );
  }
}
