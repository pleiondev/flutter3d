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
import 'package:flutter3d_rig/flutter3d_rig.dart' show BoneMap;

import '../../display_modes.dart';
import '../../lighting_sync.dart';
import '../../material_editing.dart';
import '../../scene_mode.dart';
import '../../staging.dart';
import '../../texture_slot.dart';
import '../../transform_fields.dart';
import '../animation_panel.dart';
import '../material_panel.dart';
import '../modifier_stack_panel.dart';
import '../morphs_panel.dart';
import '../operation_card.dart';
import '../properties_sections.dart';
import '../retarget_panel.dart';
import '../scene_environment_panel.dart';
import '../scene_post_panel.dart';
import '../scene_shadows_panel.dart';
import '../scene_source_panel.dart';
import '../texture_graph_panel.dart';
import '../theme.dart';
import '../tools.dart';
import '../weight_paint_panel.dart';
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
    this.animationSubmode = AnimationSubmode.pose,
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
    required this.onAddTextureNode,
    required this.onLinkTextureNode,
    required this.onUnlinkTextureNode,
    required this.onSetTextureNodeField,
    required this.onMoveTextureNode,
    required this.onRemoveTextureNode,
    required this.onBakeTextureGraph,
    required this.onAddClip,
    this.selectedAnimationClip,
    required this.onSelectAnimationClip,
    this.retargetSourceNames = const <String>[],
    this.retargetBoneMap = const BoneMap(<String, String>{}),
    required this.onRetargetAutoMap,
    this.retargetRootMotion = RetargetRootMotion.inAnimation,
    required this.onRetargetRootMotionChanged,
    this.retargetLockFeet = true,
    required this.onRetargetLockFeetChanged,
    this.retargetGroundY = 0.0,
    required this.onRetargetGroundYChanged,
    this.retargetFootTolerance = 1e-3,
    required this.onRetargetFootToleranceChanged,
    this.canApplyRetarget = false,
    this.onApplyRetarget,
    this.selectedJoint,
    required this.onSelectJoint,
    this.selectedConstraint,
    required this.onSelectConstraint,
    this.onRemoveConstraint,
    this.weightBrushMode = PaintWeightsMode.paint,
    required this.onWeightBrushModeChanged,
    this.weightBrushRadius = 48.0,
    required this.onWeightBrushRadiusChanged,
    this.weightBrushStrength = 1.0,
    required this.onWeightBrushStrengthChanged,
    this.weightMirror = false,
    required this.onWeightMirrorChanged,
    this.weightNormalize = true,
    required this.onWeightNormalizeChanged,
    this.selectedWeightVertex,
    this.hasShapeKeyAtCurrentFrame = false,
    required this.onSetShapeWeight,
    required this.onKeyShape,
    this.selectedShape,
    required this.onSelectShape,
    required this.onAddShapeDriver,
    required this.onRemoveShapeDriver,
    required this.onSetShapeDriverField,
    this.selectedLight,
    required this.onSelectLight,
    required this.onAddLight,
    required this.onRemoveLight,
    required this.onLightTypeChanged,
    required this.onLightIntensityChanged,
    required this.onLightRangeChanged,
    required this.onLightShadowChanged,
    required this.onLightConeChanged,
    required this.onSceneShadowsChanged,
    required this.onEnvironmentChanged,
    required this.onAmbientChanged,
    required this.onBloomChanged,
    required this.onExposureChanged,
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

  /// Which of the four animation workflows [mode] shows, when [mode] is
  /// [ModelerMode.animation] — `sectionsFor`'s own second argument, read the
  /// same way here as `toolsFor` already reads it for the rail. Ignored by
  /// every other mode, and defaulted to [AnimationSubmode.pose] for the same
  /// reason `sectionsFor`'s own bare, one-argument form already does: every
  /// caller that predates this field keeps reading exactly what it always
  /// has.
  final AnimationSubmode animationSubmode;

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

  /// `TextureGraphPanel`'s own "Add" menu picked a node kind, for the active
  /// material's own graph — [AddNode]'s arguments beyond the material.
  final void Function(
    int materialIndex,
    String kind,
    Map<String, Object?> fields,
    (double x, double y) position,
  )
  onAddTextureNode;

  /// A pending link was completed onto a node's input socket — [Link]'s own
  /// arguments beyond the material.
  final void Function(int materialIndex, int nodeId, String input, int from)
  onLinkTextureNode;

  /// An input socket's own link was removed — [Unlink]'s own arguments
  /// beyond the material.
  final void Function(int materialIndex, int nodeId, String input)
  onUnlinkTextureNode;

  /// A node's own field was committed — [SetNodeField]'s own arguments
  /// beyond the material.
  final void Function(
    int materialIndex,
    int nodeId,
    String field,
    Object? value,
  )
  onSetTextureNodeField;

  /// A node was dragged to a new spot — [MoveNode]'s own arguments beyond
  /// the material.
  final void Function(int materialIndex, int nodeId, double x, double y)
  onMoveTextureNode;

  /// A node's own delete icon was tapped — [RemoveNode]'s own arguments
  /// beyond the material.
  final void Function(int materialIndex, int nodeId) onRemoveTextureNode;

  /// The texture graph's own bake button was pressed — [BakeTextureGraph]'s
  /// own argument beyond the size the panel always asks for.
  final ValueChanged<int> onBakeTextureGraph;

  /// "Add" was pressed under the action list — `anim-04`'s own row.
  final VoidCallback onAddClip;

  /// `S2`'s own row: which clip [AnimationPanel]'s own action list has open —
  /// lifted out of that panel's own local state so the timeline in
  /// `ModelerShell.bottom` reads and drives the same selection.
  final int? selectedAnimationClip;
  final ValueChanged<int> onSelectAnimationClip;

  /// `S7`'s own [RetargetPanel]: every joint name on the imported source's
  /// own skeleton, resolved to text — empty before `retarget.import` has
  /// run.
  final List<String> retargetSourceNames;
  final BoneMap retargetBoneMap;

  /// `retarget.autoMap`'s own rail button, reachable a second way from
  /// [RetargetPanel]'s own "Map automatically" link.
  final VoidCallback onRetargetAutoMap;

  final RetargetRootMotion retargetRootMotion;
  final ValueChanged<RetargetRootMotion> onRetargetRootMotionChanged;
  final bool retargetLockFeet;
  final ValueChanged<bool> onRetargetLockFeetChanged;
  final double retargetGroundY;
  final ValueChanged<double> onRetargetGroundYChanged;
  final double retargetFootTolerance;
  final ValueChanged<double> onRetargetFootToleranceChanged;

  /// Whether `retarget.apply`/[onApplyRetarget] has a source clip and a
  /// rigged target to run against.
  final bool canApplyRetarget;
  final VoidCallback? onApplyRetarget;

  /// `S2`'s own row: which joint [SkeletonTree] highlights, and which
  /// [IkConstraint] row [ConstraintsList] highlights — both lifted the same
  /// way [selectedAnimationClip] was. `S5`'s own [WeightPaintPanel] reads and
  /// sets the same [selectedJoint]/[onSelectJoint] for its own "Bones" list —
  /// which joint a stroke paints onto is the same fact whichever animation
  /// sub-mode is showing it.
  final int? selectedJoint;
  final ValueChanged<int> onSelectJoint;
  final int? selectedConstraint;
  final ValueChanged<int> onSelectConstraint;
  final ValueChanged<int>? onRemoveConstraint;

  /// `S5`'s own [WeightPaintPanel]: the brush's own radius/strength/mirror/
  /// normalize, and which of `weights.paint`/`weights.assign` is armed.
  final PaintWeightsMode weightBrushMode;
  final ValueChanged<PaintWeightsMode> onWeightBrushModeChanged;
  final double weightBrushRadius;
  final ValueChanged<double> onWeightBrushRadiusChanged;
  final double weightBrushStrength;
  final ValueChanged<double> onWeightBrushStrengthChanged;
  final bool weightMirror;
  final ValueChanged<bool> onWeightMirrorChanged;
  final bool weightNormalize;
  final ValueChanged<bool> onWeightNormalizeChanged;

  /// The vertex nearest the weight brush's last hit — [WeightPaintPanel]'s
  /// own influences card.
  final int? selectedWeightVertex;

  /// `S6`'s own [MorphsPanel]: whether the held object's own `weights` track
  /// carries a key on the timeline's current frame — one boolean for every
  /// shape row, see `shape_key_state.dart`'s own `hasShapeKeyAtFrame`.
  final bool hasShapeKeyAtCurrentFrame;

  /// A shape's own slider was dragged to a new weight.
  final void Function(int id, int shapeIndex, double weight) onSetShapeWeight;

  /// Any shape row's own key dot was tapped.
  final ValueChanged<int> onKeyShape;

  /// Which shape [MorphsPanel] highlights, and the marker the viewport's own
  /// overlay draws `secondary` for — lifted the same way [selectedJoint] is.
  final int? selectedShape;
  final ValueChanged<int> onSelectShape;

  /// "Add driver" was pressed under a shape's own row — [id], then the
  /// shape index that new [ShapeDriver] drives.
  final void Function(int id, int shapeIndex) onAddShapeDriver;

  /// A driver's own remove icon was pressed — [id], then the index into
  /// [ModelObject.shapeDrivers].
  final void Function(int id, int index) onRemoveShapeDriver;

  /// A driver's own field was committed — [SetShapeDriverField]'s own
  /// vocabulary, beyond [id] and the driver's index.
  final void Function(int id, int index, String field, Object? value)
  onSetShapeDriverField;

  /// `mat-34d`'s own scene-mode wiring: which of `project.lighting.lights`
  /// [SceneSourcePanel] shows the fields of, or null for none — a plain
  /// field on the screen's own state, the same way [pivot]/[space] are
  /// rather than document state, because undoing to before a light was
  /// selected does not put the selection back either.
  final int? selectedLight;
  final ValueChanged<int> onSelectLight;
  final VoidCallback onAddLight;
  final ValueChanged<int> onRemoveLight;
  final void Function(int index, ProjectLightType type) onLightTypeChanged;
  final void Function(int index, double value) onLightIntensityChanged;
  final void Function(int index, double value) onLightRangeChanged;
  final void Function(int index, bool value) onLightShadowChanged;
  final void Function(int index, double outerConeAngle) onLightConeChanged;

  /// The scene-wide shadow request — [SceneLighting.shadows] — as opposed to
  /// [onLightShadowChanged], which is one light's own `castsShadow`.
  final ValueChanged<bool> onSceneShadowsChanged;
  final ValueChanged<SceneEnvironmentPreset> onEnvironmentChanged;
  final ValueChanged<double> onAmbientChanged;
  final ValueChanged<bool> onBloomChanged;
  final ValueChanged<double> onExposureChanged;

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
    final sections = sectionsFor(mode, animation: animationSubmode);
    // Read once and shared by [PropertiesSection.animation]'s `AnimationPanel`
    // and `S5`'s own `WeightPaintPanel` below — the same skeleton, whichever
    // of the two sub-modes is asking for it.
    final ProjectSkeleton? heldSkeleton =
        held?.skeletonIndex != null &&
            held!.skeletonIndex! < project.skeletons.length
        ? project.skeletons[held.skeletonIndex!]
        : null;
    final int? activeMaterial = held == null ? null : activeMaterialSlot(held);
    final ProjectMaterial? activeMaterialRow =
        activeMaterial != null && activeMaterial < project.materials.length
        ? project.materials[activeMaterial]
        : null;
    // `texture_slot.dart`'s own mapping from an image's bytes to what
    // `TextureSlotRow` draws — a name, a `w×h · weight` subtitle, a format
    // badge and a thumbnail — read once here rather than reaching for the
    // image's bytes three more times below.
    TextureSlotDisplay? displayOf(TextureBinding? binding) {
      if (binding == null || binding.imageIndex >= project.images.length) {
        return null;
      }
      return textureSlotDisplay(
        project.images[binding.imageIndex],
        fallbackName: 'image ${binding.imageIndex}',
      );
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
                      entry.key: _slotController(
                        binding: entry.value,
                        display: displayOf(entry.value),
                        onChoose: () =>
                            onChooseTexture(activeMaterial, entry.key),
                        onClear: entry.value == null
                            ? null
                            : () => onClearTexture(activeMaterial, entry.key),
                      ),
                  },
          ),
          if (activeMaterial != null) ...<Widget>[
            const SizedBox(height: 6),
            TextureGraphPanel(
              graph: activeMaterialRow?.graph ?? const TextureGraph(),
              onAddNode:
                  (
                    String kind,
                    Map<String, Object?> fields,
                    (double, double) position,
                  ) => onAddTextureNode(activeMaterial, kind, fields, position),
              onLink: (int nodeId, String input, int from) =>
                  onLinkTextureNode(activeMaterial, nodeId, input, from),
              onUnlink: (int nodeId, String input) =>
                  onUnlinkTextureNode(activeMaterial, nodeId, input),
              onSetNodeField: (int nodeId, String field, Object? value) =>
                  onSetTextureNodeField(activeMaterial, nodeId, field, value),
              onMoveNode: (int nodeId, double x, double y) =>
                  onMoveTextureNode(activeMaterial, nodeId, x, y),
              onRemoveNode: (int nodeId) =>
                  onRemoveTextureNode(activeMaterial, nodeId),
              // `BakeTextureGraph.apply` runs to completion inline — see its
              // own doc comment — so there is no in-flight progress for this
              // panel to show and nothing a cancel button would interrupt.
              onBake: () => onBakeTextureGraph(activeMaterial),
              onCancelBake: () {},
            ),
          ],
        ],
        if (sections.contains(PropertiesSection.sceneSources))
          SceneSourcePanel(
            lights: project.lighting.lights,
            selected: selectedLight,
            onSelect: onSelectLight,
            onAdd: onAddLight,
            onRemove: onRemoveLight,
            onTypeChanged: onLightTypeChanged,
            onIntensityChanged: onLightIntensityChanged,
            onRangeChanged: onLightRangeChanged,
            onShadowChanged: onLightShadowChanged,
            onConeChanged: onLightConeChanged,
          ),
        if (sections.contains(PropertiesSection.sceneShadows))
          SceneShadowsPanel(
            shadows: project.lighting.shadows,
            status: computeSceneStatus(
              lights: project.lighting.lights,
              lightsDropped: lightOverflowOf(project.lighting),
            ),
            onShadowsChanged: onSceneShadowsChanged,
          ),
        if (sections.contains(PropertiesSection.sceneEnvironment))
          SceneEnvironmentPanel(
            environment: project.lighting.environment,
            ambientIntensity: project.lighting.ambientIntensity,
            onEnvironmentChanged: onEnvironmentChanged,
            onAmbientChanged: onAmbientChanged,
          ),
        if (sections.contains(PropertiesSection.scenePost))
          ScenePostPanel(
            post: project.lighting.post,
            exposure: project.lighting.exposure,
            onBloomChanged: onBloomChanged,
            onExposureChanged: onExposureChanged,
          ),
        if (sections.contains(PropertiesSection.animation))
          AnimationPanel(
            clips: project.clips,
            objects: project.objects,
            skeleton: heldSkeleton,
            onAddClip: onAddClip,
            selectedClip: selectedAnimationClip,
            onSelectClip: onSelectAnimationClip,
            selectedJoint: selectedJoint,
            onSelectJoint: onSelectJoint,
            selectedConstraint: selectedConstraint,
            onSelectConstraint: onSelectConstraint,
            onRemoveConstraint: onRemoveConstraint,
          ),
        if (sections.contains(PropertiesSection.weightPaint))
          WeightPaintPanel(
            mode: weightBrushMode,
            onModeChanged: onWeightBrushModeChanged,
            radius: weightBrushRadius,
            onRadiusChanged: onWeightBrushRadiusChanged,
            strength: weightBrushStrength,
            onStrengthChanged: onWeightBrushStrengthChanged,
            mirror: weightMirror,
            onMirrorChanged: onWeightMirrorChanged,
            normalize: weightNormalize,
            onNormalizeChanged: onWeightNormalizeChanged,
            objects: project.objects,
            skeleton: heldSkeleton,
            mesh: mesh,
            selectedVertex: selectedWeightVertex,
            selectedJoint: selectedJoint,
            onSelectJoint: onSelectJoint,
          ),
        if (sections.contains(PropertiesSection.retarget))
          RetargetPanel(
            sourceNames: retargetSourceNames,
            boneMap: retargetBoneMap,
            onAutoMap: onRetargetAutoMap,
            rootMotion: retargetRootMotion,
            onRootMotionChanged: onRetargetRootMotionChanged,
            lockFeet: retargetLockFeet,
            onLockFeetChanged: onRetargetLockFeetChanged,
            groundY: retargetGroundY,
            onGroundYChanged: onRetargetGroundYChanged,
            footTolerance: retargetFootTolerance,
            onFootToleranceChanged: onRetargetFootToleranceChanged,
            canApply: canApplyRetarget,
            onApply: onApplyRetarget,
          ),
        if (held != null && sections.contains(PropertiesSection.morphs))
          MorphsPanel(
            object: held,
            objects: project.objects,
            skeleton: heldSkeleton,
            hasKeyAtCurrentFrame: hasShapeKeyAtCurrentFrame,
            selectedShape: selectedShape,
            onSelectShape: onSelectShape,
            onSetWeight: (int shapeIndex, double weight) =>
                onSetShapeWeight(held.id, shapeIndex, weight),
            onKeyShape: () => onKeyShape(held.id),
            onAddDriver: (int shapeIndex) =>
                onAddShapeDriver(held.id, shapeIndex),
            onRemoveDriver: (int index) => onRemoveShapeDriver(held.id, index),
            onSetDriverField: (int index, String field, Object? value) =>
                onSetShapeDriverField(held.id, index, field, value),
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

/// One [MaterialPanel] texture slot, from [binding] (what the material
/// names) and [display] (`texture_slot.dart`'s own read of the bound
/// image's bytes, or null when [binding] is null or points past
/// `project.images`).
///
/// **A name survives even a [display] miss.** A stale [TextureBinding] —
/// one naming a row `project.images` no longer has — still gets
/// `"image N"` for its own name, the same fallback the panel showed before
/// this slot carried a subtitle or a badge at all; only the extra detail a
/// real [display] would have added goes missing with it.
TextureSlotController _slotController({
  required TextureBinding? binding,
  required TextureSlotDisplay? display,
  required VoidCallback onChoose,
  required VoidCallback? onClear,
}) {
  final String? dimensions = display?.dimensionsText;
  return (
    name: binding == null
        ? null
        : (display?.name ?? 'image ${binding.imageIndex}'),
    subtitle: dimensions == null
        ? null
        : '$dimensions · ${display!.weightText}',
    badge: display?.formatBadge,
    thumbnail: display?.thumbnail,
    onChoose: onChoose,
    onClear: onClear,
  );
}
