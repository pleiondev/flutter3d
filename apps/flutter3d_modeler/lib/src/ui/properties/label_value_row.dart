/// A label and a value, on one row of the height the design names.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A label and a value, on one row of the height the design names.
class LabelValueRow extends StatelessWidget {
  /// A row saying [label] on the left and [value] on the right.
  const LabelValueRow(this.label, this.value, {super.key});

  /// What the value is, on the left.
  final String label;

  /// The value, already formatted, on the right.
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: rowHeightOf(context),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
