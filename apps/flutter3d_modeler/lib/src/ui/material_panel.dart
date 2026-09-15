/// `mat-04`'s own full "Панель «Материал»": every field `SurfaceMaterial`
/// carries, not `mat-04a-n`'s cut of base colour, metallic, roughness and one
/// texture slot.
///
/// **A list of the project's whole table, not of the object's own paint.**
/// [ModelObject.materialSlots] holds at most one row today (`AssignMaterial`
/// never writes more), so "the object's materials" and "the row it is
/// assigned" are the same fact; what a person needs a list *for* is picking
/// a different one to assign, which means seeing every material there is.
///
/// **The shader picker shows [LightingModel.builtIn]'s six models, not a
/// custom shader.** `SurfaceMaterial.lightingModel` can carry one a `.fmat`
/// named on its own — that value round-trips, it just has no row here to
/// pick it from, since a picker can only offer what it can name.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide EnumHint;

import '../material_editing.dart';
import 'color_field.dart';
import 'theme.dart';

/// [lighting]'s own name among [LightingModel.builtIn], or null when it is a
/// custom shader none of the six are — the dropdown's own `value` must be
/// one of its `items` or null, and a custom shader has no item to match.
String? _builtInShaderName(LightingModel lighting) {
  for (final LightingModel model in LightingModel.builtIn) {
    if (model.shaderName == lighting.shaderName) return model.shaderName;
  }
  return null;
}

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
          width: 96,
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

/// What one texture slot needs: what it is called today, and how to change
/// or clear it — the same trio `mat-04a-n` gave the base colour slot alone,
/// generalised over [MaterialPanel.textureSlots]' five keys instead of one
/// hand-written parameter each.
typedef TextureSlotController = ({
  String? name,
  VoidCallback onChoose,
  VoidCallback? onClear,
});

/// One texture slot's own row: a label, the image it holds (or none), and
/// the choose/clear pair [MaterialPanel.textureSlots] hands it.
class _TextureSlotRow extends StatelessWidget {
  const _TextureSlotRow({required this.label, required this.controller});

  final String label;
  final TextureSlotController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.bodySmall),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  controller.name ?? 'None',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: controller.name == null
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
              TextButton(
                onPressed: controller.onChoose,
                child: const Text('Choose…'),
              ),
              if (controller.onClear != null)
                TextButton(
                  onPressed: controller.onClear,
                  child: const Text('Clear'),
                ),
            ],
          ),
        ],
      ),
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
    required this.textureSlots,
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
  /// `roughness`, `emissive`, `emissiveStrength`, `normalScale`,
  /// `occlusionStrength`, `alphaMode`, `alphaCutoff`, `lightingModel`).
  final void Function(String field, Object? value) onSetField;

  /// Whether the metallic slider should respond — false for a shader with no
  /// metallic parameter (Lambert and friends), from
  /// [metallicIsMeaningful] in `material_editing.dart`.
  final bool metallicEnabled;

  /// One controller per [SetTexture] slot name — `albedo`, `normal`,
  /// `metallicRoughness`, `occlusion`, `emissive` — the same five
  /// `writeFmat` names under `textures`. A slot missing from the map is not
  /// drawn, rather than drawn disabled, since every caller today supplies
  /// all five.
  final Map<String, TextureSlotController> textureSlots;

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
    final ColorHint emissiveHint =
        builtInMaterialHints['emissive']!.kind as ColorHint;
    final RangeHint normalScaleHint =
        builtInMaterialHints['normalScale']!.kind as RangeHint;
    final RangeHint occlusionStrengthHint =
        builtInMaterialHints['occlusionStrength']!.kind as RangeHint;
    final EnumHint alphaModeHint =
        builtInMaterialHints['alphaMode']!.kind as EnumHint;
    final EnumHint lightingModelHint =
        builtInMaterialHints['lightingModel']!.kind as EnumHint;

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
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              SizedBox(
                width: 96,
                child: Text(
                  builtInMaterialHints['lightingModel']!.label ?? 'Shader',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: DropdownButton<String>(
                  key: const ValueKey<String>('lightingModelDropdown'),
                  isDense: true,
                  isExpanded: true,
                  value: _builtInShaderName(lightingModelOf(surface)),
                  items: <DropdownMenuItem<String>>[
                    for (final value in lightingModelHint.values)
                      DropdownMenuItem<String>(
                        value: value.value,
                        child: Text(value.label),
                      ),
                  ],
                  onChanged: (String? shader) {
                    if (shader != null) onSetField('lightingModel', shader);
                  },
                ),
              ),
            ],
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
          Text(
            builtInMaterialHints['emissive']!.label ?? 'Emissive',
            style: theme.textTheme.bodySmall,
          ),
          ColorField(
            value: <double>[
              surface.emissive.x,
              surface.emissive.y,
              surface.emissive.z,
            ],
            channels: emissiveHint.channels,
            // Stored the same way `baseColor` is — see that field's own
            // comment; nothing in this engine's writers gamma-corrects
            // either on the way in or out.
            linear: false,
            onChanged: (List<double> next) => onSetField('emissive', next),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              SizedBox(
                width: 96,
                child: Text(
                  builtInMaterialHints['alphaMode']!.label ?? 'Alpha',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: DropdownButton<String>(
                  key: const ValueKey<String>('alphaModeDropdown'),
                  isDense: true,
                  isExpanded: true,
                  value: surface.alphaMode.name,
                  items: <DropdownMenuItem<String>>[
                    for (final value in alphaModeHint.values)
                      DropdownMenuItem<String>(
                        value: value.value,
                        child: Text(value.label),
                      ),
                  ],
                  onChanged: (String? mode) {
                    if (mode != null) onSetField('alphaMode', mode);
                  },
                ),
              ),
            ],
          ),
          if (surface.alphaMode == SurfaceAlphaMode.mask)
            _SliderRow(
              label: 'Cutoff',
              value: surface.alphaCutoff,
              min: 0.0,
              max: 1.0,
              onChanged: (double v) => onSetField('alphaCutoff', v),
            ),
          for (final entry in textureSlots.entries)
            _TextureSlotRow(
              label: switch (entry.key) {
                'albedo' => 'Base colour texture',
                'normal' => 'Normal map',
                'metallicRoughness' => 'Metallic-roughness map',
                'occlusion' => 'Occlusion map',
                'emissive' => 'Emissive map',
                _ => entry.key,
              },
              controller: entry.value,
            ),
          const SizedBox(height: 4),
          _MaterialAdvancedSection(
            normalScale: surface.normalTexture == null
                ? null
                : (
                    min: normalScaleHint.min,
                    max: normalScaleHint.max,
                    value: surface.normalScale,
                    onChanged: (double v) => onSetField('normalScale', v),
                  ),
            occlusionStrength: surface.occlusionTexture == null
                ? null
                : (
                    min: occlusionStrengthHint.min,
                    max: occlusionStrengthHint.max,
                    value: surface.occlusionStrength,
                    onChanged: (double v) => onSetField('occlusionStrength', v),
                  ),
            emissiveStrength: (
              min: 0.0,
              max: 8.0,
              value: surface.emissiveStrength,
              onChanged: (double v) => onSetField('emissiveStrength', v),
            ),
            doubleSided: (
              value: surface.doubleSided,
              onChanged: (bool v) => onSetField('doubleSided', v),
            ),
          ),
        ],
      ],
    );
  }
}

/// One `(min, max, value, onChanged)` quadruple for an advanced slider — the
/// two texture-modulated ones only applying while the map they modulate is
/// actually bound, [MaterialPanel.build] decides; emissive strength has no
/// [builtInMaterialHints] entry of its own, so this carries its own bounds
/// rather than a [RangeHint] every slider would otherwise need one of.
typedef _AdvancedSlider = ({
  double min,
  double max,
  double value,
  ValueChanged<double> onChanged,
});

/// A checkbox's own value and setter, the same shape [_AdvancedSlider] is.
typedef _AdvancedToggle = ({bool value, ValueChanged<bool> onChanged});

/// The parameters a material rarely needs to touch, behind one disclosure —
/// `mat-04`'s own "«Дополнительно»": [normalScale] and [occlusionStrength]
/// only mean anything once their own map is bound, and
/// [SurfaceMaterial.doubleSided] is a flag most materials never set.
class _MaterialAdvancedSection extends StatelessWidget {
  const _MaterialAdvancedSection({
    required this.normalScale,
    required this.occlusionStrength,
    required this.emissiveStrength,
    required this.doubleSided,
  });

  final _AdvancedSlider? normalScale;
  final _AdvancedSlider? occlusionStrength;
  final _AdvancedSlider emissiveStrength;
  final _AdvancedToggle doubleSided;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey<String>('materialAdvanced'),
        tilePadding: EdgeInsets.zero,
        title: Text('Advanced', style: theme.textTheme.bodySmall),
        childrenPadding: EdgeInsets.zero,
        children: <Widget>[
          _SliderRow(
            label: 'Emissive strength',
            value: emissiveStrength.value,
            min: emissiveStrength.min,
            max: emissiveStrength.max,
            onChanged: emissiveStrength.onChanged,
          ),
          if (normalScale != null)
            _SliderRow(
              label: 'Normal scale',
              value: normalScale!.value,
              min: normalScale!.min,
              max: normalScale!.max,
              onChanged: normalScale!.onChanged,
            ),
          if (occlusionStrength != null)
            _SliderRow(
              label: 'Occlusion strength',
              value: occlusionStrength!.value,
              min: occlusionStrength!.min,
              max: occlusionStrength!.max,
              onChanged: occlusionStrength!.onChanged,
            ),
          CheckboxListTile(
            key: const ValueKey<String>('doubleSidedCheckbox'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('Double-sided', style: theme.textTheme.bodySmall),
            value: doubleSided.value,
            onChanged: (bool? v) => doubleSided.onChanged(v ?? false),
          ),
        ],
      ),
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
