// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'flutter3d modeller';

  @override
  String get unsavedChangesTitle => 'Unsaved changes';

  @override
  String get unsavedChangesBody =>
      'This model has changes that have not been saved.';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get discard => 'Discard';

  @override
  String get saveAndClose => 'Save and close';

  @override
  String get restoreUnsavedChangesTitle => 'Restore unsaved changes?';

  @override
  String restoreUnsavedChangesBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'An autosave from a session that did not close cleanly was found ($count objects).',
      one:
          'An autosave from a session that did not close cleanly was found ($count object).',
    );
    return '$_temp0';
  }

  @override
  String get restore => 'Restore';

  @override
  String get exportAnywayTitle => 'Export anyway?';

  @override
  String exportAnywayMoreIssues(int count) {
    return 'and $count more';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get exportAnyway => 'Export anyway';

  @override
  String get addPrimitiveTooltip => 'Add a primitive';

  @override
  String get add => 'Add';

  @override
  String get open => 'Open';

  @override
  String get save => 'Save';

  @override
  String get exportTooltip => 'Export a copy';

  @override
  String get export => 'Export';

  @override
  String get materialStudioSemanticsLabel => 'Material Studio';

  @override
  String get materialStudioTooltip => 'Material Studio — preview a material';

  @override
  String get keyboardShortcuts => 'Keyboard shortcuts';

  @override
  String get keyboardShortcutsTooltip => 'Keyboard shortcuts (?)';

  @override
  String get startScreenSemanticsLabel => 'Start screen';

  @override
  String get startScreenTooltip =>
      'Start screen — open a file or start a new project';

  @override
  String get reportProblem => 'Report a problem';

  @override
  String get sectionDisplay => 'Display';

  @override
  String get sectionView => 'View';

  @override
  String get sectionObjects => 'Objects';

  @override
  String get sectionTransform => 'Transform';

  @override
  String get sectionModifiers => 'Modifiers';

  @override
  String get sectionLastOperation => 'Last operation';

  @override
  String get sectionSelection => 'Selection';

  @override
  String get sectionMesh => 'Mesh';

  @override
  String get sectionBudget => 'Budget';

  @override
  String get rowWhat => 'What';

  @override
  String get rowVertices => 'Vertices';

  @override
  String get rowFaces => 'Faces';

  @override
  String get rowTriangles => 'Triangles';

  @override
  String get rowProfile => 'Profile';

  @override
  String get shadingMaterial => 'Material';

  @override
  String get shadingNormals => 'Normals';

  @override
  String get shadingWire => 'Wire';

  @override
  String get lensPerspective => 'Perspective';

  @override
  String get lensOrthographic => 'Orthographic';

  @override
  String get viewFront => 'Front';

  @override
  String get viewBack => 'Back';

  @override
  String get viewLeft => 'Left';

  @override
  String get viewRight => 'Right';

  @override
  String get viewTop => 'Top';

  @override
  String get viewBottom => 'Bottom';

  @override
  String get recoverUnsavedChangesTitle => 'Recover unsaved changes?';

  @override
  String get recoverUnsavedChangesBody =>
      'A more recent autosave was found than the last saved file. Restore it, or open the file as it was last saved?';

  @override
  String get openSavedFile => 'Open saved file';

  @override
  String get restoreAutosave => 'Restore autosave';

  @override
  String get startTitle => 'Start';

  @override
  String get openFile => 'Open file';

  @override
  String get newProject => 'New project';

  @override
  String get recent => 'Recent';

  @override
  String get tutorial => 'Tutorial';

  @override
  String get close => 'Close';

  @override
  String sceneStatusLabel(int lightCount, int shadowedCount, int shadowCap) {
    return '$lightCount sources · $shadowedCount shadowed of $shadowCap';
  }

  @override
  String get sceneEnvironmentSectionLabel => 'Environment';

  @override
  String get sceneShadowsSectionLabel => 'Shadows';

  @override
  String get sceneShadowsToggleLabel => 'Shadows';

  @override
  String get sceneSourcesSectionLabel => 'Sources';

  @override
  String get scenePostSectionLabel => 'Post';

  @override
  String get bakeTextureButtonLabel => 'Bake 2048²';

  @override
  String get resetPoseButtonLabel => 'Reset pose';

  @override
  String get toolObjectSelectLabel => 'Select';

  @override
  String get toolObjectSelectAbout =>
      'Click an object to work on it; shift-click adds to what is already picked.';

  @override
  String get toolObjectMoveLabel => 'Move';

  @override
  String get toolObjectMoveAbout =>
      'Drag an arrow to slide it along one axis, or the centre to move it freely.';

  @override
  String get toolObjectRotateLabel => 'Rotate';

  @override
  String get toolObjectRotateAbout => 'Drag a ring to turn it about that axis.';

  @override
  String get toolObjectScaleLabel => 'Scale';

  @override
  String get toolObjectScaleAbout =>
      'Drag a handle to grow or shrink it — one axis at a time, or all three from the centre.';

  @override
  String get toolObjectAddLabel => 'Add a box';

  @override
  String get toolObjectAddAbout =>
      'Puts a new box at the origin, still parametric: its size and segment counts stay editable in the panel.';

  @override
  String get toolObjectDuplicateLabel => 'Duplicate';

  @override
  String get toolObjectDuplicateAbout =>
      'Copies what is selected and selects the copy, leaving the original where it was.';

  @override
  String get toolObjectBakeLabel => 'Convert to a mesh';

  @override
  String get toolObjectBakeAbout =>
      'Turns a shape that still knows its own parameters into plain editable geometry. Its size and segment fields go away.';

  @override
  String get toolObjectLatheLabel => 'Add a lathe';

  @override
  String get toolObjectLatheAbout =>
      'Spins a profile you draw around an axis — how a vase, a bottle or a wheel is made.';

  @override
  String get toolObjectOriginLabel => 'Origin to the bottom';

  @override
  String get toolObjectOriginAbout =>
      'Moves the point the object turns and scales about down to its lowest vertex, so it sits on the floor.';

  @override
  String get toolObjectApplyLabel => 'Apply the transform';

  @override
  String get toolObjectApplyAbout =>
      'Folds the position, rotation and scale into the vertices themselves and leaves the transform at rest.';

  @override
  String get toolObjectDeleteLabel => 'Delete';

  @override
  String get toolObjectDeleteAbout =>
      'Removes what is selected. Undo brings it back.';

  @override
  String get toolMeshSelectLabel => 'Select';

  @override
  String get toolMeshSelectAbout =>
      'Click a vertex, edge or face; shift-click adds to what is already picked.';

  @override
  String get toolMeshLassoLabel => 'Lasso select';

  @override
  String get toolMeshLassoAbout =>
      'Draw a freehand loop round what you want instead of clicking each part of it.';

  @override
  String get toolMeshLinkedLabel => 'Select linked';

  @override
  String get toolMeshLinkedAbout =>
      'Takes everything joined to what is already picked — one whole shell of a mesh that has several.';

  @override
  String get toolMeshMoveLabel => 'Move';

  @override
  String get toolMeshMoveAbout =>
      'Drags the picked elements. Typing a number while dragging sets the distance exactly.';

  @override
  String get toolMeshRotateLabel => 'Rotate';

  @override
  String get toolMeshRotateAbout =>
      'Turns the picked elements about the middle of the selection.';

  @override
  String get toolMeshScaleLabel => 'Scale';

  @override
  String get toolMeshScaleAbout =>
      'Grows or shrinks the picked elements about the middle of the selection.';

  @override
  String get toolMeshExtrudeLabel => 'Extrude';

  @override
  String get toolMeshExtrudeAbout =>
      'Pulls new geometry out of the picked faces and leaves a wall joining it to where it came from.';

  @override
  String get toolMeshLoopCutLabel => 'Loop cut';

  @override
  String get toolMeshLoopCutAbout =>
      'Adds a ring of edges all the way round the mesh, where the next change of shape needs one to bend at.';

  @override
  String get toolMeshBevelLabel => 'Bevel';

  @override
  String get toolMeshBevelAbout =>
      'Replaces a sharp edge with a narrow strip, so light catches it the way it does on a real object.';

  @override
  String get toolMeshInsetLabel => 'Inset';

  @override
  String get toolMeshInsetAbout =>
      'Shrinks a face inward and walls the ring it leaves — how a panel, a window or a recessed button is made.';

  @override
  String get toolMeshBridgeLabel => 'Bridge';

  @override
  String get toolMeshBridgeAbout =>
      'Joins two open borders with a ring of quads, so two halves of a tube become one surface.';

  @override
  String get toolMeshSlideLabel => 'Edge slide';

  @override
  String get toolMeshSlideAbout =>
      'Moves a loop along the edges that cross it, changing where a seam sits without changing a single face.';

  @override
  String get toolMeshTriangulateLabel => 'Triangulate';

  @override
  String get toolMeshTriangulateAbout =>
      'Cuts every face into triangles — what a game engine reads, and what a face with more than four corners has to become first.';

  @override
  String get toolMeshSeparateLabel => 'Separate';

  @override
  String get toolMeshSeparateAbout =>
      'Moves the picked faces out into an object of their own.';

  @override
  String get toolMeshDissolveLabel => 'Dissolve edges';

  @override
  String get toolMeshDissolveAbout =>
      'Removes the picked edges but keeps the surface, merging the faces they divided into one.';

  @override
  String get toolMeshFillHolesLabel => 'Fill holes';

  @override
  String get toolMeshFillHolesAbout =>
      'Closes every open boundary — the gaps that make a model look see-through from one side.';

  @override
  String get toolMeshMergeLabel => 'Merge by distance';

  @override
  String get toolMeshMergeAbout =>
      'Fuses vertices sitting on top of each other, which is what a scan or an STL arrives full of.';

  @override
  String get toolMeshNormalsLabel => 'Recalculate normals';

  @override
  String get toolMeshNormalsAbout =>
      'Points every face outward again, so the surface stops reading as inside-out.';

  @override
  String get toolMeshFlipLabel => 'Flip normals';

  @override
  String get toolMeshFlipAbout =>
      'Turns the picked faces the other way round, for the shell that really is meant to be seen from inside.';

  @override
  String get toolMeshDeleteLabel => 'Delete';

  @override
  String get toolMeshDeleteAbout =>
      'Removes the picked vertices, edges or faces, and whatever depended on them.';

  @override
  String get toolPoseSelectLabel => 'Select';

  @override
  String get toolPoseSelectAbout => 'Click a joint of the skeleton to pose it.';

  @override
  String get toolPoseKeyLabel => 'Key the pose';

  @override
  String get toolPoseKeyAbout =>
      'Writes the pose on screen into the clip, at the frame the playhead is on.';

  @override
  String get toolPoseDeleteKeyLabel => 'Delete the key';

  @override
  String get toolPoseDeleteKeyAbout =>
      'Takes this frame\'s key back out, leaving the keys either side to carry the motion through it.';

  @override
  String get toolPoseAutoRigLabel => 'Auto-rig…';

  @override
  String get toolPoseAutoRigAbout =>
      'Builds a skeleton from a handful of points you place on the model.';

  @override
  String get toolWeightsPaintLabel => 'Paint weights';

  @override
  String get toolWeightsPaintAbout =>
      'Brushes how strongly the chosen joint pulls on the surface under the cursor.';

  @override
  String get toolWeightsAssignLabel => 'Assign to the joint';

  @override
  String get toolWeightsAssignAbout =>
      'Gives every vertex the brush touches to the chosen joint, at full strength.';

  @override
  String get toolWeightsMirrorLabel => 'Mirror';

  @override
  String get toolWeightsMirrorAbout =>
      'Copies one side\'s weights onto the other, so a symmetrical model is painted once.';

  @override
  String get toolWeightsNormalizeLabel => 'Normalize';

  @override
  String get toolWeightsNormalizeAbout =>
      'Makes each vertex\'s pulls add up to one and drops the smallest past the profile\'s own limit.';

  @override
  String get toolRetargetImportLabel => 'Import a source clip';

  @override
  String get toolRetargetImportAbout =>
      'Reads a clip out of another file to drive this rig with.';

  @override
  String get toolRetargetAutoMapLabel => 'Map bones automatically';

  @override
  String get toolRetargetAutoMapAbout =>
      'Guesses which bone of the source matches which of this rig, from their names.';

  @override
  String get toolRetargetApplyLabel => 'Apply the retarget';

  @override
  String get toolRetargetApplyAbout =>
      'Writes the mapped motion onto this rig as a clip of its own.';

  @override
  String get toolMorphsAddLabel => 'Add a shape';

  @override
  String get toolMorphsAddAbout =>
      'Takes the mesh as it stands now as a shape the slider can blend towards.';

  @override
  String get toolMorphsKeyLabel => 'Key the shape';

  @override
  String get toolMorphsKeyAbout =>
      'Writes the shape weights as they stand into the clip, at the playhead.';

  @override
  String get toolMorphsDeleteLabel => 'Delete the shape';

  @override
  String get toolMorphsDeleteAbout =>
      'Removes the selected shape and the slider that drove it.';

  @override
  String get primitiveBox => 'Box';

  @override
  String get primitivePlane => 'Plane';

  @override
  String get primitiveSphere => 'Sphere';

  @override
  String get primitiveCylinder => 'Cylinder';

  @override
  String get primitiveTorus => 'Torus';

  @override
  String get openTooltip =>
      'Open a file — replaces everything that is open now';

  @override
  String get importTooltip =>
      'Import a file — brings it in beside what is already open';

  @override
  String get import => 'Import';

  @override
  String get saveTooltipDirty => 'Save — there are unsaved changes';

  @override
  String get saveTooltipClean => 'Save — everything is written';

  @override
  String get saveToCabinet => 'Save to cabinet';

  @override
  String get splitViewportSemanticsLabel => 'Split the viewport';

  @override
  String get splitViewportOn =>
      'Split the viewport — the same document from two cameras';

  @override
  String get splitViewportOff => 'One viewport again';

  @override
  String get play => 'Play';

  @override
  String get playTooltip => 'Play — walk the document in a template';

  @override
  String playBlockedTooltip(String reason) {
    return 'Play — $reason';
  }

  @override
  String get preview => 'Preview';

  @override
  String get previewTooltip =>
      'Preview — see it the way the game would draw it';

  @override
  String get settings => 'Settings';

  @override
  String get settingsTooltip =>
      'Settings — navigation, keys, workspace, language';

  @override
  String agentSessionSemanticsLabel(int count) {
    return 'Agent session, $count calls';
  }

  @override
  String agentSessionTooltip(String client, int count) {
    return '$client · $count calls';
  }

  @override
  String get exportCopyTooltip => 'Export a copy';

  @override
  String get reportProblemTooltip => 'Report a problem';

  @override
  String get startScreenLabel => 'Start screen';

  @override
  String get more => 'More';

  @override
  String get foldPropertiesPanel => 'Fold the properties panel';

  @override
  String get foldToolRail => 'Fold the tool rail';

  @override
  String get legalEntry => 'Legal: licence, privacy and third-party licences';

  @override
  String get runACommand => 'Run a command';
}
