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
///
/// **Stateful for one reason: dismissal.** `ui-09`'s own "крестик" (an X) hides
/// this card's own detail without touching `ModelHistory` at all — the
/// operation stays exactly where it was on the stack, only this widget's own
/// display collapses. That is state belonging to the card, not to the
/// document, so it lives here rather than as another field threaded through
/// `_ModelerScreenState`. A new command arriving re-opens it: dismissing last
/// operation's card should not also hide the next one.
class OperationCard extends StatefulWidget {
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
  State<OperationCard> createState() => _OperationCardState();
}

class _OperationCardState extends State<OperationCard> {
  bool _dismissed = false;

  @override
  void didUpdateWidget(OperationCard old) {
    super.didUpdateWidget(old);
    // A different command than last frame's — by identity, since two
    // `LoopCut`s with the same numbers are still two different operations —
    // means a new step landed on top of the one that was dismissed, and it
    // gets its own card rather than inheriting the old one's hidden state.
    if (!identical(widget.command, old.command)) _dismissed = false;
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
    if (amended != null) widget.onAmend(amended);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ModelCommand? last = widget.command;
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

    final header = SizedBox(
      height: ModelerMetrics.row,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(last.says, style: theme.textTheme.titleSmall),
          ),
          // **Dismisses the card, not the operation.** `_dismissed` is this
          // widget's own state; nothing here calls `onAmend` or reaches
          // `ModelHistory` at all, so the step this card describes stays
          // exactly where it was on the stack.
          IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: 'Hide this card without undoing it',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _dismissed = true),
          ),
        ],
      ),
    );

    final Map<String, num> numbers = OperationCard.numbersOf(last);
    final Map<String, ParamHint> hints = last.hints;
    final body = _dismissed
        ? header
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              header,
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
                    child: _paramControl(
                      label: each.key,
                      value: each.value.toDouble(),
                      hint: hints[each.key],
                      onChanged: (double to) => _amend(last, each.key, to),
                    ),
                  ),
            ],
          );

    // **The design hand-over's own KEY REQUIREMENT**: a card, not a section
    // that reads like every other one in the panel around it — the whole
    // point is that a person can tell at a glance "this is still editable"
    // apart from "this is just information."
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: body,
    );
  }

  /// A field for [label], or — when [hint] gives both ends of a range — a
  /// slider beside it.
  ///
  /// **The slider is `ui-09`'s own acceptance, and `amend` is what makes it
  /// safe to call on every frame of a drag.** `ModelHistory.amend` replaces
  /// the top step rather than pushing one, so `onChanged` firing sixty times
  /// during one drag is sixty re-applications of the same step, not sixty new
  /// ones — the field beside it stays available for a person who would rather
  /// type an exact number than drag toward one.
  Widget _paramControl({
    required String label,
    required double value,
    required ParamHint? hint,
    required ValueChanged<double> onChanged,
  }) {
    final (double min, double max)? range = switch (hint) {
      DoubleHint(:final min?, :final max?) => (min, max),
      IntHint(:final min?, :final max?) => (min.toDouble(), max.toDouble()),
      _ => null,
    };
    if (range == null) {
      return NumberField(label: label, value: value, onChanged: onChanged);
    }
    final (double min, double max) = range;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 90,
          child: NumberField(label: label, value: value, onChanged: onChanged),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            // Without this a screen reader announces a bare number — the
            // hand-over's own KEY REQUIREMENT for this exact control, and a
            // slider has no adjacent label the way `NumberField` does to
            // fall back on.
            label: NumberField.show(value.clamp(min, max)),
            semanticFormatterCallback: (double v) =>
                '$label ${NumberField.show(v)}',
          ),
        ),
      ],
    );
  }
}
