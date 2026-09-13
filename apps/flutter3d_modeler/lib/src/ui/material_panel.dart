/// `mat-04a-n`'s own cut of the full "Панель «Материал»" row: a list of the
/// project's materials, a way to paint the held object with one of them, and
/// — for the material it is painted with — base colour, metallic,
/// roughness, and one texture slot.
///
/// **A list of the project's whole table, not of the object's own paint.**
/// [ModelObject.materialSlots] holds at most one row today (`AssignMaterial`
/// never writes more), so "the object's materials" and "the row it is
/// assigned" are the same fact; what a person needs a list *for* is picking
/// a different one to assign, which means seeing every material there is.
///
/// **Alpha, emissive, the other four texture slots and a shader picker are
/// `mat-04`'s fuller row**, the one this cut stands in for while the
/// scenario `doc-25`'s own row names — clean a mesh, fix its material,
/// export to GLB — waits on nothing bigger.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'color_field.dart';
import 'theme.dart';

/// A number bound to one material field, committing once per drag the same
/// way [ColorField] does — [Slider.onChanged] only ever updates what is
/// drawn, and [Slider.onChangeEnd] is the one call that reaches
/// [MaterialPanel.onSetField].
class _SliderRow extends StatefulWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  double? _dragging;

  @override
  void didUpdateWidget(_SliderRow old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) _dragging = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double shown = _dragging ?? widget.value;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 64,
          child: Text(
            widget.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: widget.enabled ? null : theme.disabledColor,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            // Keyed by label so a test can tell the metallic slider from the
            // roughness one — and from `ColorField`'s own three sliders,
            // which sit right above these in the same panel.
            key: ValueKey<String>('slider-${widget.label}'),
            value: shown.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            onChanged: widget.enabled
                ? (double v) => setState(() => _dragging = v)
                : null,
            onChangeEnd: widget.enabled
                ? (double v) {
                    setState(() => _dragging = null);
                    widget.onChanged(v);
                  }
                : null,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            shown.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: widget.enabled ? null : theme.disabledColor,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// The selected object's materials, and the fields of whichever it is
/// painted with.
class MaterialPanel extends StatelessWidget {
  const MaterialPanel({
    super.key,
    required this.materials,
    required this.activeIndex,
    required this.onAssign,
    required this.onAddMaterial,
    required this.onSetField,
    this.metallicEnabled = true,
    required this.onChooseBaseColorTexture,
    this.onClearBaseColorTexture,
    this.textureName,
  });

  /// Every material the project has, so a person can paint the held object
  /// with one that is not already its own.
  final List<ProjectMaterial> materials;

  /// The row the held object is painted with, or null when it has none.
  final int? activeIndex;

  /// A row was tapped: paint the held object with it, or — the row already
  /// active — take the paint off.
  final ValueChanged<int?> onAssign;

  final VoidCallback onAddMaterial;

  /// A field of [activeIndex]'s own material committed —
  /// [SetMaterialField]'s own vocabulary (`baseColor`, `metallic`,
  /// `roughness`).
  final void Function(String field, Object? value) onSetField;

  /// Whether the metallic slider should respond — false for a shader with no
  /// metallic parameter (Lambert and friends), from
  /// [metallicIsMeaningful] in `material_editing.dart`.
  final bool metallicEnabled;

  /// "Choose an image…" was pressed for the base colour slot.
  final VoidCallback onChooseBaseColorTexture;

  /// Null when the slot is already empty — nothing to clear.
  final VoidCallback? onClearBaseColorTexture;

  /// What the base colour slot's own image is called, or null for an empty
  /// slot.
  final String? textureName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ProjectMaterial? active =
        (activeIndex != null &&
            activeIndex! >= 0 &&
            activeIndex! < materials.length)
        ? materials[activeIndex!]
        : null;
    final SurfaceMaterial? surface = active?.surface;
    final ColorHint baseColorHint =
        builtInMaterialHints['baseColor']!.kind as ColorHint;
    final RangeHint metallicHint =
        builtInMaterialHints['metallic']!.kind as RangeHint;
    final RangeHint roughnessHint =
        builtInMaterialHints['roughness']!.kind as RangeHint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (materials.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'No materials',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          for (var i = 0; i < materials.length; i++)
            _MaterialRow(
              key: ValueKey<int>(i),
              name: materials[i].surface.name ?? 'Material ${i + 1}',
              selected: i == activeIndex,
              onTap: () => onAssign(i == activeIndex ? null : i),
            ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onAddMaterial,
              child: const Text('Add material'),
            ),
          ),
        ),
        if (surface != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            builtInMaterialHints['baseColor']!.label ?? 'Base colour',
            style: theme.textTheme.bodySmall,
          ),
          ColorField(
            value: <double>[
              surface.baseColor.x,
              surface.baseColor.y,
              surface.baseColor.z,
              surface.baseColor.w,
            ],
            channels: baseColorHint.channels,
            // `SurfaceMaterial.baseColor`'s own doc comment: "as authored,
            // i.e. non-linear" — so a hex box reads and writes it straight,
            // with no gamma decode in between.
            linear: false,
            onChanged: (List<double> next) => onSetField('baseColor', next),
          ),
          const SizedBox(height: 4),
          _SliderRow(
            label: builtInMaterialHints['metallic']!.label ?? 'Metallic',
            value: surface.metallic,
            min: metallicHint.min,
            max: metallicHint.max,
            enabled: metallicEnabled,
            onChanged: (double v) => onSetField('metallic', v),
          ),
          _SliderRow(
            label: builtInMaterialHints['roughness']!.label ?? 'Roughness',
            value: surface.roughness,
            min: roughnessHint.min,
            max: roughnessHint.max,
            onChanged: (double v) => onSetField('roughness', v),
          ),
          const SizedBox(height: 6),
          Text('Base colour texture', style: theme.textTheme.bodySmall),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  textureName ?? 'None',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: textureName == null
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
              TextButton(
                onPressed: onChooseBaseColorTexture,
                child: const Text('Choose…'),
              ),
              if (onClearBaseColorTexture != null)
                TextButton(
                  onPressed: onClearBaseColorTexture,
                  child: const Text('Clear'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One line of the material list.
class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    super.key,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: name,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: ModelerMetrics.row,
            child: Row(
              children: <Widget>[
                Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: selected
                        ? theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          )
                        : theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
