/// Screen 14's own bone-map table: source name → target name, with every
/// row `looseAutoMap` (or `retarget.autoMap`'s own rail button) could not
/// answer for drawn in the hand-off's own warning colours — `anim-18`'s
/// row, `ui/bone_map_table.dart` in the plan's own words.
///
/// **Read-only, on purpose.** The hand-off names one way to change a row:
/// "Сопоставить автоматически" (map automatically), which is
/// [onAutoMap]/`retarget.autoMap`. There is no per-row picker in the design
/// to build a second one out of, and a table nobody asked for would be a
/// second, silently divergent way to build a [BoneMap] this pass does not
/// need.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' show BoneMap;

/// One row: [source]'s own bone name, and whatever [boneMap] answers for
/// it.
class BoneMapTable extends StatelessWidget {
  const BoneMapTable({
    super.key,
    required this.sourceNames,
    required this.boneMap,
    required this.onAutoMap,
  });

  /// Every joint name on the source skeleton — `retargetRigOf`'s own read
  /// of `RetargetSource.skeleton.joints`, resolved to names by whatever
  /// built this table.
  final List<String> sourceNames;

  final BoneMap boneMap;

  /// `retarget.autoMap`'s own rail button, reachable a second way from
  /// here — the hand-off's own "Сопоставить автоматически" link.
  final VoidCallback onAutoMap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int mapped = <int>[
      for (final String name in sourceNames)
        if (boneMap.targetOf(name) != null) 1,
    ].length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel('Bone map'),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                sourceNames.isEmpty
                    ? 'Import a source clip to map its bones'
                    : '$mapped of ${sourceNames.length} bones mapped',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: sourceNames.isEmpty ? null : onAutoMap,
              child: const Text('Map automatically'),
            ),
          ],
        ),
        for (final String name in sourceNames)
          _BoneMapRow(source: name, target: boneMap.targetOf(name)),
      ],
    );
  }
}

class _BoneMapRow extends StatelessWidget {
  const _BoneMapRow({required this.source, this.target});

  final String source;
  final String? target;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final bool unmapped = target == null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: unmapped ? scheme.tertiaryContainer : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              source,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: unmapped ? scheme.tertiary : null,
              ),
            ),
          ),
          Icon(
            Icons.arrow_forward,
            size: 12,
            color: unmapped ? scheme.tertiary : scheme.outline,
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                if (unmapped)
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 14,
                    color: scheme.tertiary,
                  ),
                if (unmapped) const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    target ?? 'unmapped',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: unmapped ? scheme.tertiary : null,
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
