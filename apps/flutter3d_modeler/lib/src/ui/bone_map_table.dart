/// Screen 14's own bone-map table: source name → target name, with every
/// row `looseAutoMap` (or `retarget.autoMap`'s own rail button) could not
/// answer for drawn in the hand-off's own warning colours — `anim-18`'s
/// row, `ui/bone_map_table.dart` in the plan's own words.
///
/// **Editable per row since `ux-46`.** It was read-only on the argument that
/// the hand-off names one way to change a map — "Сопоставить автоматически",
/// which is [onAutoMap] — and that held until somebody tried it on a rig
/// whose bones are named anything but the convention `looseAutoMap` knows.
/// Automatic mapping gets most of a humanoid and misses the two that matter,
/// and a table that can only be regenerated leaves "the left hand went to
/// the right elbow" as a thing to fix by renaming bones in another
/// application.
///
/// The picker offers the *target* rig's own joint names, so a row cannot be
/// pointed at a bone that is not there; [onMapBone] reports the pair and
/// nothing more, the same way every other panel here reports rather than
/// edits.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' show BoneMap;

import '../../../l10n/app_localizations.dart';

/// One row: [source]'s own bone name, and whatever [boneMap] answers for
/// it.
class BoneMapTable extends StatelessWidget {
  const BoneMapTable({
    super.key,
    required this.sourceNames,
    required this.boneMap,
    required this.onAutoMap,
    this.targetNames = const <String>[],
    this.onMapBone,
  });

  /// Every joint name on the source skeleton — `retargetRigOf`'s own read
  /// of `RetargetSource.skeleton.joints`, resolved to names by whatever
  /// built this table.
  final List<String> sourceNames;

  final BoneMap boneMap;

  /// `retarget.autoMap`'s own rail button, reachable a second way from
  /// here — the hand-off's own "Сопоставить автоматически" link.
  final VoidCallback onAutoMap;

  /// Every joint on the rig being retargeted *onto* — what a row may be
  /// pointed at. Empty leaves every row read-only, which is what a caller
  /// that has not been taught this row still gets.
  final List<String> targetNames;

  /// A row was pointed at [target], or at nothing when it is null —
  /// `ux-46`. Null here leaves the table read-only.
  final void Function(String source, String? target)? onMapBone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    final int mapped = <int>[
      for (final String name in sourceNames)
        if (boneMap.targetOf(name) != null) 1,
    ].length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel(l.boneMapTitle),
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
              child: Text(l.boneMapAuto),
            ),
          ],
        ),
        for (final String name in sourceNames)
          _BoneMapRow(
            source: name,
            target: boneMap.targetOf(name),
            targetNames: targetNames,
            onMapBone: targetNames.isEmpty ? null : onMapBone,
          ),
      ],
    );
  }
}

class _BoneMapRow extends StatelessWidget {
  const _BoneMapRow({
    required this.source,
    this.target,
    this.targetNames = const <String>[],
    this.onMapBone,
  });

  final String source;
  final String? target;
  final List<String> targetNames;
  final void Function(String source, String? target)? onMapBone;

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
                  child: onMapBone == null
                      ? Text(
                          target ?? 'unmapped',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: unmapped ? scheme.tertiary : null,
                          ),
                        )
                      // `ux-46`: the target rig's own joints, and "unmapped"
                      // as a real choice rather than only a state — a bone
                      // automatic mapping got wrong is one somebody wants to
                      // take *off* as often as move.
                      : DropdownButton<String?>(
                          key: ValueKey<String>('bone-map-$source'),
                          isExpanded: true,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          value: target,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: unmapped ? scheme.tertiary : null,
                          ),
                          items: <DropdownMenuItem<String?>>[
                            const DropdownMenuItem<String?>(
                              child: Text('unmapped'),
                            ),
                            for (final String name in targetNames)
                              DropdownMenuItem<String?>(
                                value: name,
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (String? to) => onMapBone!(source, to),
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
