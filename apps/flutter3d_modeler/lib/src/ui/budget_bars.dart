/// Screen 19's own four budget bars — triangles, joints, texture memory and
/// influences, each `ProfileBudgetReport`'s own [BudgetUsage], drawn as a
/// 5lp-tall bar coloured `success` when it fits and `tertiary` when it does
/// not.
///
/// **No fifth "Materials" bar.** The hand-over's own screen 19 draws one, and
/// `ProfileBudgetReport`'s own doc comment says why this file does not: there
/// is no `maxMaterials` field on `ProjectProfile` for a bar to read, and
/// inventing one to fill a row the design shows would be a budget nobody
/// measures against anything. `S9`'s own written gap, not an oversight.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;

import 'status_line.dart' show grouped;
import 'theme.dart';

/// One row's own bar, findable by [rowKey] for a test that wants its
/// fraction or colour without reading pixels.
Key rowKey(String label) => ValueKey<String>('budget-bar-$label');

/// `human()`-formatted bytes for the texture row — `mat-33d`'s own units, so
/// a person reads "12.0 MB" rather than a byte count seven digits long.
String _bytes(int n) {
  const double kb = 1024;
  const double mb = kb * 1024;
  if (n >= mb) return '${(n / mb).toStringAsFixed(1)} MB';
  if (n >= kb) return '${(n / kb).toStringAsFixed(1)} KB';
  return '$n B';
}

/// Screen 19's own budget bars — four rows over a single
/// `ProfileBudgetReport`.
class BudgetBars extends StatelessWidget {
  const BudgetBars({super.key, required this.report});

  final ProfileBudgetReport report;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      _BudgetRow(
        label: 'triangles',
        title: 'Triangles',
        usage: report.triangles,
        readout:
            '${grouped(report.triangles.used)} / ${grouped(report.triangles.limit)}',
      ),
      const SizedBox(height: 8),
      _BudgetRow(
        label: 'joints',
        title: 'Joints',
        usage: report.joints,
        readout: '${report.joints.used} / ${report.joints.limit}',
      ),
      const SizedBox(height: 8),
      _BudgetRow(
        label: 'texture-bytes',
        title: 'Texture memory',
        usage: report.textureBytes,
        readout:
            '${_bytes(report.textureBytes.used)} / ${_bytes(report.textureBytes.limit)}',
      ),
      const SizedBox(height: 8),
      _BudgetRow(
        label: 'influences',
        title: 'Influences',
        usage: report.influences,
        readout: '${report.influences.used} / ${report.influences.limit}',
      ),
    ],
  );
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.label,
    required this.title,
    required this.usage,
    required this.readout,
  });

  final String label;
  final String title;
  final BudgetUsage usage;
  final String readout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ModelerColors colours = theme.extension<ModelerColors>()!;
    final Color fill = usage.over
        ? theme.colorScheme.tertiary
        : colours.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              readout,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(2.5),
          child: SizedBox(
            key: rowKey(label),
            height: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  key: fillKey(label),
                  widthFactor: usage.fraction.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    key: fillColourKey(label),
                    decoration: BoxDecoration(color: fill),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The row's own filled portion — a test reads [FractionallySizedBox
/// .widthFactor] off this key rather than [rowKey]'s outer track.
Key fillKey(String label) => ValueKey<String>('budget-bar-$label-fill');

/// The filled portion's own colour, on the innermost `DecoratedBox` — kept
/// apart from [fillKey] since that key's own widget has no `decoration` of
/// its own to read a colour off.
Key fillColourKey(String label) => ValueKey<String>('budget-bar-$label-colour');
