/// The label a transform carries beside the pointer — `ux-11`.
///
/// **Beside the pointer, not in the status line.** A person dragging a vertex
/// is looking at the vertex, and a number two hundred pixels below the picture
/// is a number they read after the drag rather than during it — which is the
/// half of the feedback that would have let them stop at 0.35 instead of
/// undoing and trying again. The status line still says the same thing, for
/// anyone who looks there and for the test that already reads it.
///
/// **It flips rather than runs off the edge.** A label pinned to the pointer's
/// lower right disappears the moment somebody drags into the bottom-right
/// corner, which is exactly where a model being scaled up tends to go.
library;

import 'package:flutter/material.dart';

/// [readout] over [hints], carried at [at] inside a picture of [within].
class TransformReadout extends StatelessWidget {
  const TransformReadout({
    super.key,
    required this.readout,
    required this.at,
    required this.within,
    this.hints,
  });

  /// "Move · X · 0.35 m".
  final String readout;

  /// The keys worth naming under it, or null for none.
  final String? hints;

  /// Where the pointer is, in the picture's own logical pixels.
  final Offset at;

  /// The picture, so the label can stay inside it.
  final Size within;

  /// How far from the pointer the label sits, in logical pixels — far enough
  /// not to be under the cursor's own arrow, near enough to be read without
  /// looking away from what is moving.
  static const double gap = 18;

  /// What the label is allowed to be, so the flip below can be decided
  /// before it is laid out.
  static const double maxWidth = 260;
  static const double _assumedHeight = 52;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool toTheLeft = at.dx + gap + maxWidth > within.width;
    final bool above = at.dy + gap + _assumedHeight > within.height;
    return Positioned(
      left: toTheLeft ? null : at.dx + gap,
      right: toTheLeft ? within.width - at.dx + gap : null,
      top: above ? null : at.dy + gap,
      bottom: above ? within.height - at.dy + gap : null,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.92,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    readout,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFeatures: const <FontFeature>[
                        // The number changes on every frame of a drag, and a
                        // proportional font makes the whole label twitch as
                        // the digits change width.
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  if (hints case final String said)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: <Widget>[
                          for (final String chip in said.split(' · '))
                            _SnapChip(chip),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One key and what it is worth right now — "Ctrl snap 0.1 m".
///
/// A chip rather than a run of grey text, because these are four separate
/// facts and a sentence reads as one.
class _SnapChip extends StatelessWidget {
  const _SnapChip(this.said);

  final String said;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          said,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
