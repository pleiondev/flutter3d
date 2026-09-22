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

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide EnumHint;

import '../../l10n/app_localizations.dart';
import '../material_editing.dart';
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

/// What one texture slot needs: what it is called today, how to draw it, and
/// how to change or clear it — the trio `mat-04a-n` gave the base colour
/// slot alone, plus `texture_slot.dart`'s own [TextureSlotDisplay] fields
/// (`subtitle`/`badge`/`thumbnail`), generalised over
/// [MaterialPanel.textureSlots]' five keys instead of one hand-written
/// parameter each.
typedef TextureSlotController = ({
  String? name,

  /// `"256×128 · 170 KB"`, or null — straight through to
  /// [TextureSlotRow.subtitle].
  String? subtitle,

  /// A format badge — `"BC7"` — or null for a plain PNG/JPEG. Straight
  /// through to [TextureSlotRow.badge].
  String? badge,

  /// The bound file's own encoded bytes, for [TextureSlotRow]'s own
  /// thumbnail well. Null draws no thumbnail, same as an empty slot.
  Uint8List? thumbnail,
  VoidCallback onChoose,
  VoidCallback? onClear,
});

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
    this.onOpenLinkedFile,
    this.metallicEnabled = true,
    required this.textureSlots,
  });

  /// Every material the project has, so a person can paint the held object
  /// with one that is not already its own.
  final List<ProjectMaterial> materials;

  /// The row the held object is painted with, or null when it has none.
  final int? activeIndex;

  /// A row was tapped: paint the held object with it. Null is "Unassign",
  /// which is a button of its own — `ux-40`.
  final ValueChanged<int?> onAssign;

  final VoidCallback onAddMaterial;

  /// A field of [activeIndex]'s own material committed —
  /// [SetMaterialField]'s own vocabulary (`baseColor`, `metallic`,
  /// `roughness`, `emissive`, `emissiveStrength`, `normalScale`,
  /// `occlusionStrength`, `alphaMode`, `alphaCutoff`, `lightingModel`).
  final void Function(String field, Object? value) onSetField;

  /// Hands the active material's own `.fmat` to the system's editor —
  /// `ux-47`. Null where there is nothing to hand it to (the web build), and
  /// the row does not appear at all.
  final Future<bool> Function(String path)? onOpenLinkedFile;

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
    final AppLocalizations l = AppLocalizations.of(context);
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
              l.matNoMaterials,
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
              color: _dotColorOf(materials[i].surface),
              selected: i == activeIndex,
              // **`ux-40`: a second tap on the row that is already assigned
              // assigns it again, which is nothing.** It used to take the
              // paint off, so the way to see a material's own fields was to
              // click its row — and the way to look at them twice was to
              // unpaint the object. Taking the paint off is a thing somebody
              // means on purpose, so it is its own button below.
              onTap: () => onAssign(i),
            ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: <Widget>[
              TextButton(onPressed: onAddMaterial, child: Text(l.matAdd)),
              if (activeIndex != null)
                TextButton(
                  onPressed: () => onAssign(null),
                  child: Text(l.matUnassign),
                ),
            ],
          ),
        ),
        // `ux-47`: a material that defers to a file says which one, and
        // hands it to whatever the system opens `.fmat` with. **Only when
        // there is a file and somebody to open it with** — a browser has
        // neither, and a button that always refuses is worse than no button.
        if (activeIndex case final int at
            when at >= 0 &&
                at < materials.length &&
                materials[at].fmat != null &&
                onOpenLinkedFile != null) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              const Icon(Icons.link, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  materials[at].fmat!,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () => onOpenLinkedFile!(materials[at].fmat!),
                child: Text(l.matOpenInEditor),
              ),
            ],
          ),
        ],
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
                child: EnumField(
                  key: const ValueKey<String>('lightingModelDropdown'),
                  value: _builtInShaderName(lightingModelOf(surface)),
                  options: lightingModelHint.values,
                  onChanged: (String shader) =>
                      onSetField('lightingModel', shader),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          RangeSliderField(
            label: builtInMaterialHints['metallic']!.label ?? 'Metallic',
            value: surface.metallic,
            min: metallicHint.min,
            max: metallicHint.max,
            // Written bit for bit: a step here would round a drag's own
            // double before it ever reached `onSetField`, and a `.fmat`
            // this panel writes is meant to carry exactly what the slider
            // produced.
            step: null,
            enabled: metallicEnabled,
            onChanged: (double v) => onSetField('metallic', v),
          ),
          RangeSliderField(
            label: builtInMaterialHints['roughness']!.label ?? 'Roughness',
            value: surface.roughness,
            min: roughnessHint.min,
            max: roughnessHint.max,
            step: null,
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
                child: EnumField(
                  key: const ValueKey<String>('alphaModeDropdown'),
                  value: surface.alphaMode.name,
                  options: alphaModeHint.values,
                  onChanged: (String mode) => onSetField('alphaMode', mode),
                ),
              ),
            ],
          ),
          if (surface.alphaMode == SurfaceAlphaMode.mask)
            RangeSliderField(
              label: l.matCutoff,
              value: surface.alphaCutoff,
              min: 0.0,
              max: 1.0,
              step: null,
              onChanged: (double v) => onSetField('alphaCutoff', v),
            ),
          for (final entry in textureSlots.entries)
            TextureSlotRow(
              label: switch (entry.key) {
                'albedo' => 'Base colour texture',
                'normal' => 'Normal map',
                'metallicRoughness' => 'Metallic-roughness map',
                'occlusion' => 'Occlusion map',
                'emissive' => 'Emissive map',
                _ => entry.key,
              },
              name: entry.value.name,
              subtitle: entry.value.subtitle,
              badge: entry.value.badge,
              thumbnail: entry.value.thumbnail,
              onChoose: entry.value.onChoose,
              onClear: entry.value.onClear,
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
    final AppLocalizations l = AppLocalizations.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey<String>('materialAdvanced'),
        tilePadding: EdgeInsets.zero,
        title: Text(l.matAdvanced, style: theme.textTheme.bodySmall),
        childrenPadding: EdgeInsets.zero,
        children: <Widget>[
          RangeSliderField(
            label: l.matEmissiveStrength,
            value: emissiveStrength.value,
            min: emissiveStrength.min,
            max: emissiveStrength.max,
            step: null,
            onChanged: emissiveStrength.onChanged,
          ),
          if (normalScale != null)
            RangeSliderField(
              label: l.matNormalScale,
              value: normalScale!.value,
              min: normalScale!.min,
              max: normalScale!.max,
              step: null,
              onChanged: normalScale!.onChanged,
            ),
          if (occlusionStrength != null)
            RangeSliderField(
              label: l.matOcclusionStrength,
              value: occlusionStrength!.value,
              min: occlusionStrength!.min,
              max: occlusionStrength!.max,
              step: null,
              onChanged: occlusionStrength!.onChanged,
            ),
          CheckboxListTile(
            key: const ValueKey<String>('doubleSidedCheckbox'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l.matDoubleSided, style: theme.textTheme.bodySmall),
            value: doubleSided.value,
            onChanged: (bool? v) => doubleSided.onChanged(v ?? false),
          ),
        ],
      ),
    );
  }
}

/// [surface]'s own colour, for the material list's dot — its
/// [SurfaceMaterial.baseColor], sRGB as authored (that field's own doc
/// comment), always drawn fully opaque: the dot names which paint a row is,
/// it does not preview how see-through it renders.
Color _dotColorOf(SurfaceMaterial surface) => Color.fromRGBO(
  (surface.baseColor.x.clamp(0.0, 1.0) * 255).round(),
  (surface.baseColor.y.clamp(0.0, 1.0) * 255).round(),
  (surface.baseColor.z.clamp(0.0, 1.0) * 255).round(),
  1.0,
);

/// One line of the material list.
class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    super.key,
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;

  /// [SurfaceMaterial.baseColor], from [_dotColorOf] — the design
  /// hand-over's own "цветной кружок" in place of the checkbox this row used
  /// to lead with.
  final Color color;

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
            height: rowHeightOf(context),
            child: Row(
              children: <Widget>[
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    // A wider, `primary` ring marks the active row — the dot
                    // is what colour the material paints with either way, so
                    // selection has to be a second visual fact rather than a
                    // second meaning of the same one.
                    border: Border.all(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      width: selected ? 2 : 1,
                    ),
                  ),
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
