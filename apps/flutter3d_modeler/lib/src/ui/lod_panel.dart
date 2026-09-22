/// Screen 17's own right-hand panel — `pro-lod-04`'s other half: a card per
/// level, what the object covers on screen right now, and the three things a
/// person can do about the list.
///
/// **Dumb, the way `BakePanel` and `UvUnwrapPanel` are.** It is handed rows of
/// numbers and four callbacks. What a ratio means to the document is
/// `SetLodRatio`'s business, reached through whoever built this; what a row's
/// triangle count is came out of `LodMeshCache` before it got here. Nothing in
/// this file knows there is a project.
///
/// **No threshold field on a card, and that is not an oversight.** The
/// threshold is what `LodZoneBar` under the three pictures is for — a marker
/// on an axis, next to the other markers it has to stay in order with. A
/// number box here would be a second place to set the same thing with none of
/// that context, so a card *says* its threshold and the strip *sets* it.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';

import '../../l10n/app_localizations.dart';
import 'status_line.dart' show grouped;

/// One level, as a card shows it.
typedef LodLevelRow = ({
  /// `LodSpec.ratio`: the share of the base mesh's triangles this level
  /// keeps, from just above nought to one.
  double ratio,

  /// `LodSpec.maxScreenFraction`: the share of the screen's height below
  /// which this level is drawn.
  double maxScreenFraction,

  /// How many triangles the simplified mesh actually came out at — not
  /// `ratio` times the base, which is what was asked for. Null when there is
  /// no mesh to count: a parametric shape nobody has converted yet.
  int? triangles,
});

/// The smallest ratio a card's slider offers. `SetLodRatio` refuses nought,
/// and a twentieth is already a silhouette.
const double kLodRatioFloor = 0.05;

/// Screen 17's panel.
final class LodPanel extends StatelessWidget {
  const LodPanel({
    super.key,
    required this.objectName,
    required this.levels,
    required this.onRatio,
    required this.onAddLevel,
    required this.onRegenerate,
    required this.onClose,
    this.now,
    this.refusal,
  });

  /// Whose levels these are — the heading, so that the panel says which
  /// object the three pictures beside it are of.
  final String objectName;

  final List<LodLevelRow> levels;

  /// A card's slider was let go at a new ratio. Once per drag, not once per
  /// pixel of it: `RangeSliderField` reports when the thumb is released,
  /// which is what makes a drag one step of undo rather than sixty.
  final void Function(int lodIndex, double ratio) onRatio;

  final VoidCallback onAddLevel;
  final VoidCallback onRegenerate;

  /// Back to the object's own inspector.
  final VoidCallback onClose;

  /// What the object covers in the main viewport right now, and which level
  /// that answers to — already a sentence, already translated. Null hides
  /// the line, which is what a caller with no camera to measure against
  /// wants.
  final String? now;

  /// Why a level cannot be added, or null. Shown above the button it
  /// disables — `BakePanel.refusal`'s own bargain.
  final String? refusal;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey<String>('lodClose'),
              onPressed: onClose,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: Text(l.lodClose),
            ),
          ),
          SectionLabel(l.propLods),
          Text(
            objectName,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          if (now != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                now!,
                key: const ValueKey<String>('lodNow'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (levels.isEmpty)
            Text(
              l.lodNoLevels,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            )
          else
            for (var i = 0; i < levels.length; i++)
              _LevelCard(
                key: ValueKey<String>('lodLevel-$i'),
                index: i,
                level: levels[i],
                onRatio: (double to) => onRatio(i, to),
              ),
          const SizedBox(height: 8),
          if (refusal != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                refusal!,
                key: const ValueKey<String>('lodRefusal'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          FilledButton.tonalIcon(
            key: const ValueKey<String>('lodAddLevel'),
            onPressed: refusal == null ? onAddLevel : null,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l.lodAddLevel),
          ),
          TextButton(
            key: const ValueKey<String>('lodRegenerate'),
            onPressed: levels.isEmpty ? null : onRegenerate,
            child: Text(l.lodRegenerate),
          ),
        ],
      ),
    );
  }
}

/// One level: its name, how much of the mesh it keeps, what that came to,
/// and where on the screen it takes over.
final class _LevelCard extends StatelessWidget {
  const _LevelCard({
    super.key,
    required this.index,
    required this.level,
    required this.onRatio,
  });

  final int index;
  final LodLevelRow level;
  final ValueChanged<double> onRatio;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle? quiet = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(l.lodLevel(index), style: theme.textTheme.labelLarge),
              RangeSliderField(
                label: l.lodRatio,
                value: level.ratio.clamp(kLodRatioFloor, 1.0),
                min: kLodRatioFloor,
                max: 1,
                step: 0.05,
                onChanged: onRatio,
              ),
              if (level.triangles case final int count)
                Text(l.lodTriangles(grouped(count)), style: quiet),
              Text(
                l.lodUpTo((level.maxScreenFraction * 100).round()),
                style: quiet,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
