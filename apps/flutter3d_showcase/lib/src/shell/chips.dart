/// The small marks in a page's header: the version it appeared in, and what
/// this device makes of it.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_showcase/src/catalog/feature.dart';

/// "since 0.5.0", coloured by the minor version so a run of pages reads as a
/// timeline. The tooltip is the line of the CHANGELOG the tag was read from.
class VersionChip extends StatelessWidget {
  const VersionChip(this.feature, {super.key});

  final Feature feature;

  @override
  Widget build(BuildContext context) {
    final int minor = int.tryParse(feature.since.split('.')[1]) ?? 0;
    final Color colour = HSLColor.fromAHSL(
      1,
      (minor * 47.0) % 360,
      0.55,
      Theme.of(context).brightness == Brightness.dark ? 0.62 : 0.38,
    ).toColor();
    final String label = feature.approximate
        ? 'since ${feature.since} or earlier'
        : 'since ${feature.since}';
    return Tooltip(
      message: '${feature.evidenceFile}: ${feature.evidence}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: colour),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colour,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A line that says what this device cannot do for the page, or nothing.
class BackendNotice extends StatelessWidget {
  const BackendNotice({super.key, required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colors.tertiaryContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: colors.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              lines.join(' '),
              style: TextStyle(color: colors.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
