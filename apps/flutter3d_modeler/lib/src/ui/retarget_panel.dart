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

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' show BoneMap;

import '../../l10n/app_localizations.dart';
import 'bone_map_table.dart';

/// Where a retargeted clip's own root motion ends up — the hand-off's own
/// "В анимации" (baked into the clip, the ordinary state right after
/// [retargetClip] runs) versus "Кодом" (extracted through
/// `ExtractRootMotion` so a character controller reads it instead).
enum RetargetRootMotion {
  /// Left baked into the retargeted clip — what retargeting does anyway.
  inAnimation('In animation'),

  /// Extracted from the clip, for a character controller to read instead.
  inCode('In code');

  const RetargetRootMotion(this.label);

  /// What the choice's chip says. English whatever the locale: unlike the
  /// panel's other strings it does not go through the localizations.
  final String label;
}

/// Screen 14's right panel: the bone map, the root-motion choice, the foot
/// corrections, and Apply.
class RetargetPanel extends StatelessWidget {
  /// The panel over [boneMap]; every edit goes out through its callback.
  const RetargetPanel({
    super.key,
    required this.sourceNames,
    required this.boneMap,
    required this.onAutoMap,
    this.targetNames = const <String>[],
    this.onMapBone,
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

  /// Every joint on the source clip's rig, the left column of the bone map.
  final List<String> sourceNames;

  /// Which source joint drives which target joint, as it stands.
  final BoneMap boneMap;

  /// Fill the bone map from the joint names, replacing what is there.
  final VoidCallback onAutoMap;

  /// Where the retargeted clip's root motion is to end up.
  final RetargetRootMotion rootMotion;

  /// The root-motion choice was changed.
  final ValueChanged<RetargetRootMotion> onRootMotionChanged;

  /// Whether each foot is snapped back to [groundY] after retargeting. Off
  /// greys out [groundY] and [footTolerance].
  final bool lockFeet;

  /// The foot-lock box was ticked or cleared.
  final ValueChanged<bool> onLockFeetChanged;

  /// The height of the floor the feet are locked to, in metres.
  final double groundY;

  /// A new floor height was typed, in metres.
  final ValueChanged<double> onGroundYChanged;

  /// How far, in metres, an ankle may sit off [groundY] before the foot lock
  /// moves it: an ankle closer than this is left alone.
  final double footTolerance;

  /// A new foot tolerance was typed, in metres.
  final ValueChanged<double> onFootToleranceChanged;

  /// Whether `retarget.apply`/[onApply] has everything it needs — a source
  /// clip chosen and a rigged target selected. Read here rather than
  /// derived from [sourceNames]/[boneMap] alone: an empty [boneMap] is a
  /// legitimate "nothing has been mapped yet" the button should still
  /// refuse, but so is "no target object is even selected", which neither
  /// of those two says anything about.
  final bool canApply;

  /// Runs the retarget. Only called while [canApply] holds; the button is
  /// disabled otherwise.
  final VoidCallback? onApply;

  /// Every joint on the rig being retargeted onto — `ux-46`. Empty leaves
  /// the bone map read-only.
  final List<String> targetNames;

  /// A bone-map row was pointed somewhere else — `ux-46`.
  final void Function(String source, String? target)? onMapBone;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        BoneMapTable(
          sourceNames: sourceNames,
          boneMap: boneMap,
          onAutoMap: onAutoMap,
          // `ux-46`: the rig being retargeted onto, so a row can only be
          // pointed at a bone that is there.
          targetNames: targetNames,
          onMapBone: onMapBone,
        ),
        SectionLabel(l.retargetRootMotion),
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
        SectionLabel(l.retargetCorrections),
        CheckboxListTile(
          key: const ValueKey<String>('retargetLockFeetCheckbox'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            l.retargetLockFeet,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          value: lockFeet,
          onChanged: (bool? v) => onLockFeetChanged(v ?? false),
        ),
        NumberField(
          label: l.retargetGroundY,
          value: groundY,
          onChanged: onGroundYChanged,
          enabled: lockFeet,
        ),
        NumberField(
          label: l.retargetFootTolerance,
          value: footTolerance,
          onChanged: onFootToleranceChanged,
          enabled: lockFeet,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: canApply ? onApply : null,
          icon: const Icon(Icons.check_circle_outlined, size: 16),
          label: Text(l.retargetApply),
        ),
      ],
    );
  }
}
