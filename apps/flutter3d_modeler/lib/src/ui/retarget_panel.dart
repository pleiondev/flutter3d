/// Screen 14's own right panel: the bone-map table, root motion, and the
/// retarget corrections — `anim-18`'s row, `ui/retarget_panel.dart` in the
/// plan's own words. `PropertiesSection.retarget`'s whole content.
///
/// **Height-fit is not a control here.** `retargetClip` scales a root
/// translation by the two rigs' own standing heights unconditionally — see
/// `retarget.dart`'s own class comment — so there is nothing for this panel
/// to switch on or off; only `lockFeet`/`groundY`/`footTolerance`, which
/// change what [retargetClip] does on top of that, are exposed.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_rig/flutter3d_rig.dart' show BoneMap;

import 'bone_map_table.dart';

/// Where a retargeted clip's own root motion ends up — the hand-off's own
/// "В анимации" (baked into the clip, the ordinary state right after
/// [retargetClip] runs) versus "Кодом" (extracted through
/// `ExtractRootMotion` so a character controller reads it instead).
enum RetargetRootMotion {
  inAnimation('In animation'),
  inCode('In code');

  const RetargetRootMotion(this.label);

  final String label;
}

class RetargetPanel extends StatelessWidget {
  const RetargetPanel({
    super.key,
    required this.sourceNames,
    required this.boneMap,
    required this.onAutoMap,
    required this.rootMotion,
    required this.onRootMotionChanged,
    required this.lockFeet,
    required this.onLockFeetChanged,
    required this.groundY,
    required this.onGroundYChanged,
    required this.footTolerance,
    required this.onFootToleranceChanged,
    required this.canApply,
    required this.onApply,
  });

  final List<String> sourceNames;
  final BoneMap boneMap;
  final VoidCallback onAutoMap;

  final RetargetRootMotion rootMotion;
  final ValueChanged<RetargetRootMotion> onRootMotionChanged;

  final bool lockFeet;
  final ValueChanged<bool> onLockFeetChanged;
  final double groundY;
  final ValueChanged<double> onGroundYChanged;
  final double footTolerance;
  final ValueChanged<double> onFootToleranceChanged;

  /// Whether `retarget.apply`/[onApply] has everything it needs — a source
  /// clip chosen and a rigged target selected. Read here rather than
  /// derived from [sourceNames]/[boneMap] alone: an empty [boneMap] is a
  /// legitimate "nothing has been mapped yet" the button should still
  /// refuse, but so is "no target object is even selected", which neither
  /// of those two says anything about.
  final bool canApply;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      BoneMapTable(
        sourceNames: sourceNames,
        boneMap: boneMap,
        onAutoMap: onAutoMap,
      ),
      SectionLabel('Root motion'),
      SegmentedButton<RetargetRootMotion>(
        showSelectedIcon: false,
        segments: <ButtonSegment<RetargetRootMotion>>[
          for (final RetargetRootMotion mode in RetargetRootMotion.values)
            ButtonSegment<RetargetRootMotion>(
              value: mode,
              label: Text(mode.label),
            ),
        ],
        selected: <RetargetRootMotion>{rootMotion},
        onSelectionChanged: (Set<RetargetRootMotion> picked) =>
            onRootMotionChanged(picked.first),
      ),
      SectionLabel('Corrections'),
      CheckboxListTile(
        key: const ValueKey<String>('retargetLockFeetCheckbox'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text('Lock feet', style: Theme.of(context).textTheme.bodySmall),
        value: lockFeet,
        onChanged: (bool? v) => onLockFeetChanged(v ?? false),
      ),
      NumberField(
        label: 'Ground Y',
        value: groundY,
        onChanged: onGroundYChanged,
        enabled: lockFeet,
      ),
      NumberField(
        label: 'Foot tolerance',
        value: footTolerance,
        onChanged: onFootToleranceChanged,
        enabled: lockFeet,
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: canApply ? onApply : null,
        icon: const Icon(Icons.check_circle_outlined, size: 16),
        label: const Text('Apply the retarget'),
      ),
    ],
  );
}
