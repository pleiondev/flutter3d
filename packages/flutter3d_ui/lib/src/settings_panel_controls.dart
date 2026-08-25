import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter3d_game/flutter3d_game.dart';

/// A section label, spelled once instead of four times.
class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.text, {super.key});

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
class SettingsValueSlider extends StatelessWidget {
  const SettingsValueSlider({
    super.key,
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
class SettingsBindingRow extends StatelessWidget {
  const SettingsBindingRow({
    super.key,
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
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
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
