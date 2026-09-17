/// Screen 13's own right panel: brush parameters, the selected vertex's own
/// influences, and how many vertices each bone currently holds — `anim-12`'s
/// row, `ui/weight_paint_panel.dart` in the plan's own words.
///
/// **`weights.paint`/`weights.assign` are two rail tools (`ui/tools.dart`),
/// and [WeightPaintPanel.mode]/[WeightPaintPanel.onModeChanged] here are a
/// second way to the same armed tool** — the same convenience this panel's
/// sibling sections already give the shading mode and the lens at the top of
/// every properties panel, both also reachable from menus of their own.
/// Pressing either segment changes `ModelerReady.tool`, never a value this
/// widget owns.
///
/// **Mirror and normalize are read at the moment a stroke opens, not stored
/// on the document.** Neither flag has anything of its own to undo — a
/// stroke painted with mirror on is the pair of paints `PaintWeights.mirror`
/// itself records, and turning the flag off afterwards changes nothing about
/// a stroke already painted.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

import '../../l10n/app_localizations.dart';

/// The brush parameters, the held vertex's own influences, and the skeleton's
/// own bone list — screen 13's whole right panel.
class WeightPaintPanel extends StatelessWidget {
  const WeightPaintPanel({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.radius,
    required this.onRadiusChanged,
    required this.strength,
    required this.onStrengthChanged,
    required this.mirror,
    required this.onMirrorChanged,
    required this.normalize,
    required this.onNormalizeChanged,
    required this.objects,
    required this.skeleton,
    this.mesh,
    this.selectedVertex,
    this.selectedJoint,
    this.onSelectJoint,
  });

  /// Whether the armed brush overwrites (`assign`) or accumulates (`paint`)
  /// — `weights.paint`'s and `weights.assign`'s own two rail tools.
  final PaintWeightsMode mode;
  final ValueChanged<PaintWeightsMode> onModeChanged;

  /// In logical pixels — what a stroke's own `radiusPixels` reads.
  final double radius;
  final ValueChanged<double> onRadiusChanged;

  /// 0 to 1, `PaintWeights.strength`'s own range.
  final double strength;
  final ValueChanged<double> onStrengthChanged;

  final bool mirror;
  final ValueChanged<bool> onMirrorChanged;
  final bool normalize;
  final ValueChanged<bool> onNormalizeChanged;

  /// Every object in the project — read only for a joint's own
  /// `ModelObject.name`, the same lookup `SkeletonTree.objects` takes a
  /// plain list for rather than a whole `ModelProject`.
  final List<ModelObject> objects;

  /// The held object's own skeleton, or null when it has none bound yet —
  /// draws the bone list empty rather than refusing to build at all, since
  /// picking a mesh to rig is a step this sub-mode's own screen is reached
  /// well before finishing.
  final ProjectSkeleton? skeleton;

  /// The mesh being painted, when the held object has one — null draws both
  /// the influences card and the bone list empty, the honest answer for
  /// "nothing to paint yet".
  final EditMesh? mesh;

  /// The vertex nearest the brush's last hit, or null before a stroke has
  /// ever touched the mesh.
  final int? selectedVertex;

  /// Which joint a stroke paints onto — the row this highlights in "Bones".
  final int? selectedJoint;

  /// A row of "Bones" was tapped: paint a different joint from here, the
  /// same selection `SkeletonTree.onSelectJoint` already offers the pose
  /// sub-mode.
  final ValueChanged<int>? onSelectJoint;

  String _nameOf(int jointId) {
    for (final ModelObject object in objects) {
      if (object.id == jointId) return object.name;
    }
    return 'joint $jointId';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EditMesh? mesh = this.mesh;
    final int? vertex = selectedVertex;
    final List<int> joints = skeleton?.joints ?? const <int>[];
    final AppLocalizations l = AppLocalizations.of(context);

    final List<WeightPair> influences = mesh == null || vertex == null
        ? const <WeightPair>[]
        : (weightsOf(mesh, vertex).toList()..sort(
            (WeightPair a, WeightPair b) => b.weight.compareTo(a.weight),
          ));

    // How many vertices carry a real (non-zero) share of each bone —
    // `screen 13`'s own "412 в." per row — indexed the same local way
    // `weightsOf`'s own `WeightPair.joint` already is.
    final List<int> vertexCountByLocalJoint = List<int>.filled(
      joints.length,
      0,
    );
    if (mesh != null) {
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        if (!mesh.isVertexAlive(v)) continue;
        for (final WeightPair pair in weightsOf(mesh, v)) {
          if (pair.weight <= 0 ||
              pair.joint < 0 ||
              pair.joint >= vertexCountByLocalJoint.length) {
            continue;
          }
          vertexCountByLocalJoint[pair.joint]++;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel(l.weightsBrush),
        SegmentedButton<PaintWeightsMode>(
          showSelectedIcon: false,
          segments: <ButtonSegment<PaintWeightsMode>>[
            ButtonSegment<PaintWeightsMode>(
              value: PaintWeightsMode.paint,
              label: Text(l.weightsPaint),
            ),
            ButtonSegment<PaintWeightsMode>(
              value: PaintWeightsMode.assign,
              label: Text(l.weightsAssign),
            ),
          ],
          selected: <PaintWeightsMode>{mode},
          onSelectionChanged: (Set<PaintWeightsMode> picked) =>
              onModeChanged(picked.first),
        ),
        const SizedBox(height: 8),
        RangeSliderField(
          label: l.weightsRadius,
          value: radius,
          min: 4,
          max: 200,
          onChanged: onRadiusChanged,
        ),
        RangeSliderField(
          label: l.brushStrength,
          value: strength,
          min: 0,
          max: 1,
          step: 0.05,
          onChanged: onStrengthChanged,
        ),
        CheckboxListTile(
          key: const ValueKey<String>('weightMirrorCheckbox'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(l.weightsMirror, style: theme.textTheme.bodySmall),
          value: mirror,
          onChanged: (bool? v) => onMirrorChanged(v ?? false),
        ),
        CheckboxListTile(
          key: const ValueKey<String>('weightNormalizeCheckbox'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(l.weightsNormalize, style: theme.textTheme.bodySmall),
          value: normalize,
          onChanged: (bool? v) => onNormalizeChanged(v ?? false),
        ),
        SectionLabel(l.weightsSelectedVertex),
        if (vertex == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              l.weightsNoVertex,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else if (influences.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              l.weightsNoInfluences,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          for (final WeightPair pair in influences)
            _InfluenceRow(
              name: pair.joint >= 0 && pair.joint < joints.length
                  ? _nameOf(joints[pair.joint])
                  : 'joint ${pair.joint}',
              weight: pair.weight,
            ),
        SectionLabel(l.weightsBones),
        if (joints.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              l.weightsNoBones,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          for (var i = 0; i < joints.length; i++)
            _BoneRow(
              name: _nameOf(joints[i]),
              count: vertexCountByLocalJoint[i],
              selected: joints[i] == selectedJoint,
              onTap: onSelectJoint == null
                  ? null
                  : () => onSelectJoint!(joints[i]),
            ),
      ],
    );
  }
}

/// One bone's own pull on the selected vertex — a name, a mini bar 90
/// logical pixels wide, and the weight itself to two decimals, `screen 13`'s
/// own row shape.
class _InfluenceRow extends StatelessWidget {
  const _InfluenceRow({required this.name, required this.weight});

  final String name;
  final double weight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            height: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: weight.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              weight.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the bone list: a name and how many vertices currently carry a
/// real share of it — `screen 13`'s own "412 в.", highlighted when this is
/// the joint a stroke paints onto.
class _BoneRow extends StatelessWidget {
  const _BoneRow({
    required this.name,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.surfaceContainerHighest : null,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                '$count v.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
