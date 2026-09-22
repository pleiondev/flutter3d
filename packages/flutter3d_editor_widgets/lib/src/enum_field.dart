/// One of a finite set of named values, offered as a dropdown.
///
/// **What is bound is always somewhere in the list, even when [EnumField]'s
/// own [EnumField.options] does not itself offer it.** A material written by
/// a newer build may name an alpha mode this build has never heard of, and a
/// picker that could not display it would show the wrong mode and write the
/// wrong one the moment anybody touched anything else on the panel. So the
/// bound value joins the list, saying plainly what it is — the level
/// editor's own rule for this row.
///
/// **A null [EnumField.value] falls back to the first of [EnumField.options]
/// rather than refusing to draw anything.** The texture graph panel's own
/// enum row already followed that rule for a field a document has not set: a
/// dropdown has to show something, and the first option is a better guess
/// than one nothing has selected.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart' show EnumHintValue;

/// A dropdown offering [options], with [value] selected.
final class EnumField extends StatelessWidget {
  const EnumField({
    super.key,
    this.value,
    required this.options,
    required this.onChanged,
    this.unknownLabel,
  });

  /// What is bound right now, or null for a field nothing has set.
  final String? value;

  /// What a person may choose between.
  final List<EnumHintValue> options;

  /// Called with the [EnumHintValue.value] of whatever was picked.
  final ValueChanged<String> onChanged;

  /// How to word an option [value] carries that [options] does not list — a
  /// material written by a newer build, say. Defaults to naming the value
  /// itself and saying plainly that this build does not offer it.
  final String Function(String value)? unknownLabel;

  @override
  Widget build(BuildContext context) {
    final String? current = value;
    final bool offered =
        current != null &&
        options.any((EnumHintValue option) => option.value == current);
    final String? effective = current ?? _firstOrNull(options);

    return DropdownButton<String>(
      value: effective,
      isDense: true,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      items: <DropdownMenuItem<String>>[
        for (final EnumHintValue option in options)
          DropdownMenuItem<String>(
            value: option.value,
            child: Text(option.label),
          ),
        if (current != null && !offered)
          DropdownMenuItem<String>(
            value: current,
            child: Text(
              unknownLabel?.call(current) ??
                  '$current — not one this build offers',
            ),
          ),
      ],
      onChanged: (String? next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

String? _firstOrNull(List<EnumHintValue> options) =>
    options.isEmpty ? null : options.first.value;
