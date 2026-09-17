/// Screen 15's own right panel: one row per shape key — a name, a slider,
/// its live weight and a key dot — with the corrective drivers that bend it
/// automatically listed below the shape they belong to, `anim-19`'s app half
/// and the panel row `anim-34d` left for this pass to build.
///
/// **The key dot is one fact about the object, not one per shape.**
/// [KeyShape] records every one of an object's own shape weights into one
/// keyframe at one instant (`shape_commands.dart`'s own doc comment), so
/// [MorphsPanel.hasKeyAtCurrentFrame] answers the same thing for every row —
/// see `shape_key_state.dart`'s own `hasShapeKeyAtFrame`, which is how a
/// caller computes it.
///
/// **What is not here.** Shape *sets* — the hand-over's own "Face · 12 /
/// Body · 3" chips — are not built; `anim-34d`'s own row already says there
/// is no such thing in the model, only a flat list of shape keys. Adding a
/// new shape key from the current mesh ([AddShapeFromMesh]) is mesh mode's
/// own sculpting workflow, not this sub-mode's panel, so this draws only the
/// keys an object already has.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

import '../../l10n/app_localizations.dart';
import 'named_button.dart';
import 'theme.dart';

/// Radians as degrees — [ShapeDriver.from]/[ShapeDriver.to] are stored in
/// radians all the way through (`shape_commands.dart`'s own
/// [SetShapeDriverField] doc comment); this panel is the one edge that shows
/// degrees, so the conversion lives here rather than in the document.
double _degreesOf(double radians) => radians * 180.0 / math.pi;

double _radiansOf(double degrees) => degrees * math.pi / 180.0;

/// The shape list, its driver rows, and the per-row key dot — screen 15's
/// whole right panel.
class MorphsPanel extends StatelessWidget {
  const MorphsPanel({
    super.key,
    required this.object,
    required this.objects,
    required this.skeleton,
    required this.hasKeyAtCurrentFrame,
    required this.onSetWeight,
    required this.onKeyShape,
    this.selectedShape,
    required this.onSelectShape,
    required this.onAddDriver,
    required this.onRemoveDriver,
    required this.onSetDriverField,
  });

  /// The held object, or null with nothing to draw shapes for.
  final ModelObject? object;

  /// Every object in the project — read only for a driver's own
  /// [ShapeDriver.jointId] name, the same lookup `WeightPaintPanel.objects`
  /// takes a plain list for rather than a whole `ModelProject`.
  final List<ModelObject> objects;

  /// The held object's own skeleton, or null when it has none bound yet —
  /// the bones a driver row's own picker offers. Null draws that picker
  /// empty rather than refusing to draw the row at all, the same "nothing to
  /// rig yet" honesty `WeightPaintPanel.skeleton` already answers with.
  final ProjectSkeleton? skeleton;

  /// Whether [object]'s own `weights` track carries a key on the timeline's
  /// current frame — one boolean for every row, see this file's own class
  /// comment.
  final bool hasKeyAtCurrentFrame;

  /// A shape's own slider was dragged to a new weight.
  final void Function(int shapeIndex, double weight) onSetWeight;

  /// Any row's own key dot was tapped — `KeyShape` at the current frame, for
  /// every shape on the object at once.
  final VoidCallback onKeyShape;

  /// Which shape a person tapped — the row this highlights, and the marker
  /// the viewport's own overlay draws `secondary` rather than `primary` for.
  final int? selectedShape;
  final ValueChanged<int> onSelectShape;

  /// "Add driver" was pressed under shape [shapeIndex]'s own row.
  final ValueChanged<int> onAddDriver;

  /// A driver's own remove icon was pressed — [driverIndex] into
  /// [ModelObject.shapeDrivers], not into any one shape's own sub-list.
  final ValueChanged<int> onRemoveDriver;

  /// A driver's own field was committed — [SetShapeDriverField]'s own
  /// vocabulary (`'jointId'`, `'axis'`, `'from'`, `'to'`), [driverIndex]
  /// again into [ModelObject.shapeDrivers].
  final void Function(int driverIndex, String field, Object? value)
  onSetDriverField;

  String _nameOf(int objectId) {
    for (final ModelObject candidate in objects) {
      if (candidate.id == objectId) return candidate.name;
    }
    return 'object $objectId';
  }

  @override
  Widget build(BuildContext context) {
    final ModelObject? held = object;
    final AppLocalizations l = AppLocalizations.of(context);
    if (held == null || held.shapeSet.keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          l.morphsNoShapeKeys,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    final ShapeSet shapes = held.shapeSet;
    final List<int> bones = skeleton?.joints ?? const <int>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < shapes.keys.length; i++) ...<Widget>[
          _ShapeRow(
            name: shapes.keys[i].name,
            weight: shapes.weights.length > i ? shapes.weights[i] : 0.0,
            hasKey: hasKeyAtCurrentFrame,
            selected: selectedShape == i,
            onSelect: () => onSelectShape(i),
            onWeightChanged: (double weight) => onSetWeight(i, weight),
            onKey: onKeyShape,
          ),
          for (var d = 0; d < held.shapeDrivers.length; d++)
            if (held.shapeDrivers[d].shapeIndex == i)
              _DriverRow(
                driver: held.shapeDrivers[d],
                boneName: _nameOf(held.shapeDrivers[d].jointId),
                bones: bones,
                nameOf: _nameOf,
                onBoneChanged: (int jointId) =>
                    onSetDriverField(d, 'jointId', jointId),
                onAxisChanged: (DriverAxis axis) =>
                    onSetDriverField(d, 'axis', axis.name),
                onFromChanged: (double degrees) =>
                    onSetDriverField(d, 'from', _radiansOf(degrees)),
                onToChanged: (double degrees) =>
                    onSetDriverField(d, 'to', _radiansOf(degrees)),
                onRemove: () => onRemoveDriver(d),
              ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: TextButton(
              onPressed: () => onAddDriver(i),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: panelButtonMinimum(context),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(l.morphsAddDriver),
            ),
          ),
        ],
      ],
    );
  }
}

/// One shape key's own row: a 96-wide name, a slider, its value and the key
/// dot — `radio_button_checked` in `secondary` (`#FF458E`) when [hasKey],
/// `radio_button_unchecked` in `outlineVariant` (`#3F484A`) otherwise, the
/// hand-over's own screen 15.
class _ShapeRow extends StatelessWidget {
  const _ShapeRow({
    required this.name,
    required this.weight,
    required this.hasKey,
    required this.selected,
    required this.onSelect,
    required this.onWeightChanged,
    required this.onKey,
  });

  final String name;
  final double weight;
  final bool hasKey;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<double> onWeightChanged;
  final VoidCallback onKey;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: InkWell(
              onTap: onSelect,
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
          Expanded(
            child: RangeSliderField(
              value: weight,
              min: 0,
              max: 1,
              step: 0.01,
              onChanged: onWeightChanged,
            ),
          ),
          NamedButton(
            label: l.morphsKeyShape,
            child: IconButton(
              tooltip: l.morphsKeyShape,
              icon: Icon(
                hasKey
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: hasKey
                    ? kModelerScheme.secondary
                    : kModelerScheme.outlineVariant,
              ),
              onPressed: onKey,
            ),
          ),
        ],
      ),
    );
  }
}

/// One corrective shape's own row: which bone drives it, about which axis,
/// and the angle span that maps to a weight of 0 to 1 — built through
/// `anim-34d`'s own `SetShapeDriverField`, degrees shown here and radians
/// carried everywhere else.
class _DriverRow extends StatelessWidget {
  const _DriverRow({
    required this.driver,
    required this.boneName,
    required this.bones,
    required this.nameOf,
    required this.onBoneChanged,
    required this.onAxisChanged,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onRemove,
  });

  final ShapeDriver driver;
  final String boneName;
  final List<int> bones;
  final String Function(int objectId) nameOf;
  final ValueChanged<int> onBoneChanged;
  final ValueChanged<DriverAxis> onAxisChanged;
  final ValueChanged<double> onFromChanged;
  final ValueChanged<double> onToChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final bool boneListed = bones.contains(driver.jointId);
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButton<int>(
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  value: driver.jointId,
                  items: <DropdownMenuItem<int>>[
                    for (final int bone in bones)
                      DropdownMenuItem<int>(
                        value: bone,
                        child: Text(
                          nameOf(bone),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (!boneListed)
                      DropdownMenuItem<int>(
                        value: driver.jointId,
                        child: Text(boneName, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (int? next) {
                    if (next != null) onBoneChanged(next);
                  },
                ),
              ),
              NamedButton(
                label: l.morphsRemoveDriver,
                child: IconButton(
                  tooltip: l.morphsRemoveDriver,
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: onRemove,
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              SegmentedButton<DriverAxis>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<DriverAxis>>[
                  ButtonSegment<DriverAxis>(
                    value: DriverAxis.x,
                    label: Text('X'),
                  ),
                  ButtonSegment<DriverAxis>(
                    value: DriverAxis.y,
                    label: Text('Y'),
                  ),
                  ButtonSegment<DriverAxis>(
                    value: DriverAxis.z,
                    label: Text('Z'),
                  ),
                ],
                selected: <DriverAxis>{driver.axis},
                onSelectionChanged: (Set<DriverAxis> picked) =>
                    onAxisChanged(picked.first),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: NumberField(
                  label: l.morphsFrom,
                  value: _degreesOf(driver.from),
                  onChanged: onFromChanged,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: NumberField(
                  label: l.morphsTo,
                  value: _degreesOf(driver.to),
                  onChanged: onToChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
