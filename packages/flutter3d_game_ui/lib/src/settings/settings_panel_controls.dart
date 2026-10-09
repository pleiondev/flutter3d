import 'package:flutter/material.dart';
import 'package:flutter3d_game/flutter3d_game.dart';

import '../l10n/game_localizations.dart';
import '../theme/game_ui_theme.dart';
import 'action_bindings_section.dart' show ActionBindingsSection;

/// A section label, spelled once instead of four times.
class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: GameUiTheme.of(context).heading,
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

  /// The number shown, in the setting's own unit.
  final double value;

  /// The least the slider goes to, in the setting's own unit.
  final double min;

  /// The most the slider goes to, in the setting's own unit.
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
              style: TextStyle(color: GameUiTheme.of(context).label),
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
              style: TextStyle(color: GameUiTheme.of(context).faint),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the controls: a name, what it is bound to, tap to rebind.
///
/// **A label rather than an action**, which is what lets an axis's two ends
/// be two rows and a dual axis's four directions four. It took a button
/// action and printed its identifier, which was the one kind of action the
/// old button table knew; the rows are an [ActionBindingsSection]'s now.
class SettingsBindingRow extends StatelessWidget {
  const SettingsBindingRow({
    super.key,
    required this.label,
    required this.sources,
    required this.waiting,
    this.onTap,
  });

  /// What the row is called: the action's display name, and the part.
  final String label;

  /// What reaches it, in the order bound.
  final List<InputSource> sources;

  /// Whether it is listening for its new control.
  final bool waiting;

  /// Starts or cancels the rebind; null for a row that only shows.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final words = Flutter3dGameLocalizations.of(context);
    final theme = GameUiTheme.of(context);
    // Worth saying out loud rather than showing an empty space: an action
    // bound to nothing is a verb the player cannot reach, which is the exact
    // condition this screen exists to fix.
    final bound = waiting
        ? words.pressAKeyOrButton
        : sources.isEmpty
        ? words.boundToNothing
        : sources.map(words.source).join(', ');
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        label: words.boundTo(label, bound),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(label, style: TextStyle(color: theme.text)),
                Flexible(
                  child: Text(
                    bound,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: waiting ? theme.waiting : theme.faint,
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
              style: TextStyle(color: GameUiTheme.of(context).label),
            ),
          ),
          Switch(value: on, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// One of a few named choices — a row of chips, the chosen one lit.
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    super.key,
    required this.label,
    required this.choices,
    required this.chosen,
    required this.onChanged,
  });

  final String label;
  final List<String> choices;
  final int chosen;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 140,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              label,
              style: TextStyle(color: GameUiTheme.of(context).label),
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (var i = 0; i < choices.length; i++)
                ChoiceChip(
                  label: Text(choices[i]),
                  selected: i == chosen,
                  onSelected: (_) => onChanged(i),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One of a few colours — a row of swatches, the chosen one ringed.
class SettingsColourRow extends StatelessWidget {
  const SettingsColourRow({
    super.key,
    required this.label,
    required this.choices,
    required this.chosen,
    required this.onChanged,
  });

  final String label;
  final List<Color> choices;
  final int chosen;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(color: GameUiTheme.of(context).label),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                for (var i = 0; i < choices.length; i++)
                  Semantics(
                    label: Flutter3dGameLocalizations.of(
                      context,
                    ).colorChoice(label, i),
                    selected: i == chosen,
                    button: true,
                    child: GestureDetector(
                      key: ValueKey<String>('colour:$label:$i'),
                      onTap: () => onChanged(i),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: choices[i],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: i == chosen
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.25),
                            width: i == chosen ? 2.5 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
