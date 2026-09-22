/// A sentence pinned to a corner of the picture — screen 06's own "Seams · 4
/// edges", and the retopology mode's count of corners placed.
///
/// **A card over the viewport rather than a segment of the status line.**
/// The status line says what the document is; this says what the *picture*
/// is showing right now, and belongs where the eye already is while a person
/// is clicking edges. `WeightLegend` and `MeasurementReportOverlay` are the
/// same idea in the two other corners, and this takes their surface and
/// radius so that three cards over one picture read as one family.
///
/// Dumb: it is handed the sentence already translated, and positions
/// nothing — the caller's own `Positioned` decides the corner, since which
/// corners are free depends on what else the mode has pinned there.
library;

import 'package:flutter/material.dart';

/// One short line on the panel surface, for a corner of the viewport.
final class ViewportChip extends StatelessWidget {
  const ViewportChip(this.said, {super.key});

  /// What it says, in the language the interface is in.
  final String said;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          said,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
