/// The card for the last thing that was done, with its parameters still
/// editable.
///
/// **This is the persistent document's one visible payoff, and it is worth
/// saying why.** An extrusion is a command with a distance in it, and the
/// history keeps the document as it was before that command ran. So changing
/// the distance is not "undo, then extrude again" — it is running the same
/// command with a different number against the same starting point, which is
/// what `ModelHistory.amend` does. The stack does not grow, the model does not
/// flicker through an intermediate state, and a person can drag the number
/// until it looks right.
///
/// **The fields come from the command's own arguments.** Every `ModelCommand`
/// writes itself down as a map of numbers for the journal and for an agent's
/// tool call, and `modelCommandFromJson` reads one back — so a card that edits
/// the map and reads a new command out of it needs to know nothing about which
/// command it is holding. A card with a `switch` over command types would be a
/// third place that has to learn every new one.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'number_field.dart';
import 'theme.dart';

/// The last operation, or nothing when there has not been one.
class OperationCard extends StatelessWidget {
  const OperationCard({
    super.key,
    required this.command,
    required this.onAmend,
  });

  /// What is at the top of the history's stack.
  final ModelCommand? command;

  /// Called with the command as it should now be. The caller hands it to
  /// `ModelHistory.amend`, which re-runs it against the document as it was.
  final ValueChanged<ModelCommand> onAmend;

  /// The arguments worth showing: the numbers.
  ///
  /// **Numbers only, and that is a decision rather than a limit.** An id is an
  /// argument too and editing it would mean "do this to a different object",
  /// which is not an adjustment — it is a different command, and the person
  /// asking for it is asking to select something else. A name is a text field
  /// and belongs to `ui-08`'s rename row.
  static Map<String, num> numbersOf(ModelCommand command) => <String, num>{
    for (final MapEntry<String, Object?> each in command.arguments.entries)
      if (each.value is num && each.key != 'id') each.key: each.value! as num,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ModelCommand? last = command;
    if (last == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'nothing done yet',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final Map<String, num> numbers = numbersOf(last);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: ModelerMetrics.row,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(last.says, style: theme.textTheme.titleSmall),
          ),
        ),
        if (numbers.isEmpty)
          Text(
            'nothing to adjust',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final MapEntry<String, num> each in numbers.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: NumberField(
                label: each.key,
                value: each.value.toDouble(),
                onChanged: (double to) => _amend(last, each.key, to),
              ),
            ),
      ],
    );
  }

  void _amend(ModelCommand last, String argument, double to) {
    // Through the command's own JSON, so this knows nothing about which command
    // it is holding. An integer argument — `cuts`, `segments` — goes back as an
    // integer, because that is what `fromJson` matches on and a `2.0` where a
    // `2` was expected reads back as null.
    final Object? was = last.arguments[argument];
    final Map<String, Object?> json = <String, Object?>{
      ...last.toJson(),
      argument: was is int ? to.round() : to,
    };
    final ModelCommand? amended = modelCommandFromJson(json);
    if (amended != null) onAmend(amended);
  }
}
