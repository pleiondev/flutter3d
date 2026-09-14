/// The right-hand panel: `ui-08`'s own object list, transform grid and
/// modifier stack, plus what the viewport knows about display and camera.
///
/// **No longer as thin as the row that first drew it.** An earlier draft of
/// this comment called the panel thin on purpose, waiting on `doc-03`/
/// `doc-05` before an object list or a number field could edit a
/// `ModelProject` through a command at all — both are done now, `doc-06` and
/// `doc-23` besides, and [ObjectRow]/[TransformRows]/`ModifierStackPanel`
/// below are what a panel free to write to the document actually looks like.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

import '../../display_modes.dart';
import '../../material_editing.dart';
import '../../staging.dart';
import '../../transform_fields.dart';
import '../animation_panel.dart';
import '../material_panel.dart';
import '../modifier_stack_panel.dart';
import '../operation_card.dart';
import '../properties_sections.dart';
import '../theme.dart';
import '../tools.dart';
import 'label_value_row.dart';
import 'name_field.dart';
import 'object_row.dart';
import 'pivot_space_chips.dart';
import 'transform_rows.dart';

/// The right-hand panel: the object list, transform grid and modifier stack,
/// plus what the viewport knows about display and camera.
class PropertiesPanel extends StatelessWidget {
  const PropertiesPanel({
    super.key,
    required this.mode,
    required this.stage,
    required this.project,
    required this.selection,
    required this.onSelect,
    required this.onTransform,
    required this.pivot,
    required this.onPivot,
    required this.space,
    required this.onSpace,
    required this.onRename,
    required this.onToggleModifier,
    required this.onReorderModifier,
    required this.onAddModifier,
    this.onSetModifierField,
    required this.onAssignMaterial,
    required this.onAddMaterial,
    required this.onSetMaterialField,
    required this.onChooseTexture,
    required this.onClearTexture,
    required this.onMoveKeys,
    required this.onAddClip,
    required this.onSelectAnimationClip,
    required this.onScrubAnimation,
    required this.lastCommand,
    required this.onAmend,
    required this.shading,
    required this.onShading,
    required this.lens,
    required this.onLens,
    required this.onView,
  });

  /// **`ui-04`'s own "content is replaced wholesale."** Object mode wants the
  /// object list, the transform grid and the modifier stack; mesh mode wants
  /// the last-operation card and the selection summary. Display/View/Budget
  /// are cross-mode utility — the camera and the export budget mean the same
  /// thing regardless of what is being edited — so they stay in every mode
  /// rather than disappearing along with the mode-specific sections.
  final ModelerMode mode;

  final ModelerStage stage;
  final ModelProject project;
  final ProjectSelection selection;
  final ValueChanged<int> onSelect;

  /// A number field was committed: the whole transform, as nine numbers.
  final void Function(int id, TransformFields to) onTransform;

  /// Where a rotation or a scale from [onTransform] is centred, and the chip
  /// that changes it.
  final PivotChip pivot;
  final ValueChanged<PivotChip> onPivot;

  /// Whose axes a rotation from [onTransform] is given in, and the chip that
  /// changes it.
  final TransformSpace space;
  final ValueChanged<TransformSpace> onSpace;

  /// The name box was committed.
  final void Function(int id, String to) onRename;

  /// A modifier's own enabled switch was flipped.
  final void Function(int id, int index) onToggleModifier;

  /// A modifier was dragged to a new place in the stack.
  final void Function(int id, int from, int to) onReorderModifier;

  /// The stack's own "Add" link was pressed, for the held object.
  final ValueChanged<int> onAddModifier;

  /// A modifier's own field was committed — `mat-20`'s own array `count`,
  /// today. Null draws the stack with no field control at all, the same as
  /// [ModifierStackPanel.onSetField] itself.
  final void Function(int id, int index, String field, Object? value)?
  onSetModifierField;

  /// A row of [MaterialPanel]'s own list was tapped: paint the held object
  /// with that material, or null to take its paint off.
  final void Function(int id, int? to) onAssignMaterial;

  /// The material panel's own "Add material" link was pressed.
  final VoidCallback onAddMaterial;

  /// A field of the held object's own material committed —
  /// [SetMaterialField]'s own vocabulary.
  final void Function(int materialIndex, String field, Object? value)
  onSetMaterialField;

  /// "Choose…" was pressed for one of a material's five texture slots —
  /// `albedo`, `normal`, `metallicRoughness`, `occlusion`, `emissive`, the
  /// same names [SetTexture.slot] takes.
  final void Function(int materialIndex, String slot) onChooseTexture;

  /// "Clear" was pressed for one of a material's texture slots.
  final void Function(int materialIndex, String slot) onClearTexture;

  /// `anim-07`'s own two commands: a diamond finished a drag, or "Add" was
  /// pressed under the action list.
  final ValueChanged<MoveKeys> onMoveKeys;
  final VoidCallback onAddClip;

  /// `anim-07`'s own live pose: which clip the action list has open, or null
  /// for none, and where the panel's own scrubber sits inside it.
  final ValueChanged<int?> onSelectAnimationClip;
  final ValueChanged<double> onScrubAnimation;

  /// What the operation card is showing, and where an adjustment goes.
  final ModelCommand? lastCommand;
  final ValueChanged<ModelCommand> onAmend;

  final ShadingMode shading;
  final ValueChanged<ShadingMode> onShading;
  final ViewLens lens;
  final ValueChanged<ViewLens> onLens;
  final ValueChanged<StandardView> onView;

  @override
  Widget build(BuildContext context) {
    final mesh = switch (project[selection.activeObject ?? -1]?.geometry) {
      EditedGeometry(:final mesh) => mesh,
      _ => null,
    };
    final held = project[selection.activeObject ?? -1];
    final sections = sectionsFor(mode);
    final int? activeMaterial = held == null ? null : activeMaterialSlot(held);
    final ProjectMaterial? activeMaterialRow =
        activeMaterial != null && activeMaterial < project.materials.length
        ? project.materials[activeMaterial]
        : null;
    String? imageNameOf(TextureBinding? binding) {
      if (binding == null) return null;
      return binding.imageIndex < project.images.length
          ? (project.images[binding.imageIndex].name ??
                'image ${binding.imageIndex}')
          : 'image ${binding.imageIndex}';
    }

    final Map<String, TextureBinding?> textureBySlot =
        <String, TextureBinding?>{
          'albedo': activeMaterialRow?.surface.baseColorTexture,
          'normal': activeMaterialRow?.surface.normalTexture,
          'metallicRoughness':
              activeMaterialRow?.surface.metallicRoughnessTexture,
          'occlusion': activeMaterialRow?.surface.occlusionTexture,
          'emissive': activeMaterialRow?.surface.emissiveTexture,
        };
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      children: <Widget>[
        SectionLabel('Display'),
        SegmentedButton<ShadingMode>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<ShadingMode>>[
            ButtonSegment<ShadingMode>(
              value: ShadingMode.material,
              label: Text('Material'),
            ),
            ButtonSegment<ShadingMode>(
              value: ShadingMode.normals,
              label: Text('Normals'),
            ),
            ButtonSegment<ShadingMode>(
              value: ShadingMode.wireframe,
              label: Text('Wire'),
            ),
          ],
          selected: <ShadingMode>{shading},
          onSelectionChanged: (Set<ShadingMode> picked) =>
              onShading(picked.first),
        ),
        const SizedBox(height: 8),
        SegmentedButton<ViewLens>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<ViewLens>>[
            ButtonSegment<ViewLens>(
              value: ViewLens.perspective,
              label: Text('Perspective'),
            ),
            ButtonSegment<ViewLens>(
              value: ViewLens.orthographic,
              label: Text('Orthographic'),
            ),
          ],
          selected: <ViewLens>{lens},
          onSelectionChanged: (Set<ViewLens> picked) => onLens(picked.first),
        ),
        SectionLabel('View'),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: <Widget>[
            for (final StandardView view in StandardView.values)
              OutlinedButton(
                onPressed: () => onView(view),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, ModelerMetrics.row - 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(_viewNames[view]!),
              ),
          ],
        ),
        if (sections.contains(PropertiesSection.objects)) ...<Widget>[
          SectionLabel('Objects'),
          for (final ModelObject object in project.objects)
            ObjectRow(
              object: object,
              selected: selection.objects.contains(object.id),
              onTap: () => onSelect(object.id),
            ),
        ],
        if (held != null &&
            sections.contains(PropertiesSection.transform)) ...<Widget>[
          SectionLabel('Transform'),
          NameField(
            key: ValueKey<int>(held.id),
            name: held.name,
            onRenamed: (String to) => onRename(held.id, to),
          ),
          const SizedBox(height: 4),
          TransformRows(
            key: ValueKey<int>(held.id),
            fields: transformFieldsOf(held.transform),
            onChanged: (TransformFields to) => onTransform(held.id, to),
          ),
          const SizedBox(height: 8),
          PivotAndSpaceChips(pivot: pivot, onPivot: onPivot),
          const SizedBox(height: 4),
          SpaceChips(space: space, onSpace: onSpace),
        ],
        if (held != null &&
            sections.contains(PropertiesSection.modifiers)) ...<Widget>[
          SectionLabel('Modifiers'),
          ModifierStackPanel(
            key: ValueKey<int>(held.id),
            slots: held.modifiers,
            onToggle: (int index) => onToggleModifier(held.id, index),
            onReorder: (int from, int to) =>
                onReorderModifier(held.id, from, to),
            onAdd: () => onAddModifier(held.id),
            onSetField: onSetModifierField == null
                ? null
                : (int index, String field, Object? value) =>
                      onSetModifierField!(held.id, index, field, value),
          ),
        ],
        if (held != null &&
            sections.contains(PropertiesSection.materials)) ...<Widget>[
          SectionLabel('Material'),
          MaterialPanel(
            key: ValueKey<int>(held.id),
            materials: project.materials,
            activeIndex: activeMaterial,
            onAssign: (int? to) => onAssignMaterial(held.id, to),
            onAddMaterial: onAddMaterial,
            onSetField: (String field, Object? value) {
              if (activeMaterial != null) {
                onSetMaterialField(activeMaterial, field, value);
              }
            },
            metallicEnabled: activeMaterialRow == null
                ? true
                : metallicIsMeaningful(
                    lightingModelOf(activeMaterialRow.surface),
                  ),
            textureSlots: activeMaterial == null
                ? const <String, TextureSlotController>{}
                : <String, TextureSlotController>{
                    for (final entry in textureBySlot.entries)
                      entry.key: (
                        name: imageNameOf(entry.value),
                        onChoose: () =>
                            onChooseTexture(activeMaterial, entry.key),
                        onClear: entry.value == null
                            ? null
                            : () => onClearTexture(activeMaterial, entry.key),
                      ),
                  },
          ),
        ],
        if (sections.contains(PropertiesSection.animation))
          AnimationPanel(
            clips: project.clips,
            objects: project.objects,
            skeleton:
                held?.skeletonIndex != null &&
                    held!.skeletonIndex! < project.skeletons.length
                ? project.skeletons[held.skeletonIndex!]
                : null,
            onMoveKeys: onMoveKeys,
            onAddClip: onAddClip,
            onSelectClip: onSelectAnimationClip,
            onTimeChanged: onScrubAnimation,
          ),
        if (sections.contains(PropertiesSection.lastOperation)) ...<Widget>[
          SectionLabel('Last operation'),
          OperationCard(command: lastCommand, onAmend: onAmend),
        ],
        if (sections.contains(PropertiesSection.selection)) ...<Widget>[
          SectionLabel('Selection'),
          LabelValueRow('What', selection.says),
        ],
        if (mesh != null &&
            sections.contains(PropertiesSection.mesh)) ...<Widget>[
          SectionLabel('Mesh'),
          LabelValueRow('Vertices', '${mesh.vertexCount}'),
          LabelValueRow('Faces', '${mesh.faceCount}'),
        ],
        SectionLabel('Budget'),
        LabelValueRow('Triangles', '${project.triangleCount}'),
        LabelValueRow('Profile', project.profile.name),
      ],
    );
  }

  static const Map<StandardView, String> _viewNames = <StandardView, String>{
    StandardView.front: 'Front',
    StandardView.back: 'Back',
    StandardView.left: 'Left',
    StandardView.right: 'Right',
    StandardView.top: 'Top',
    StandardView.bottom: 'Bottom',
  };
}
