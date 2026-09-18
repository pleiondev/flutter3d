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

  @override
  String get gallery => 'Gallery';

  @override
  String get galleryTooltip =>
      'Gallery — insert a ready model beside what is open';

  @override
  String get toolSculptDrawLabel => 'Draw';

  @override
  String get toolSculptDrawAbout =>
      'Pushes everything under the brush out along one shared direction, the way a stamp would.';

  @override
  String get toolSculptClayLabel => 'Clay';

  @override
  String get toolSculptClayAbout =>
      'Builds the surface up in flat layers, like thumbing clay on.';

  @override
  String get toolSculptInflateLabel => 'Inflate';

  @override
  String get toolSculptInflateAbout =>
      'Pushes each vertex along its own normal, so a rounded patch puffs up rather than rising as a plane.';

  @override
  String get toolSculptSmoothLabel => 'Smooth';

  @override
  String get toolSculptSmoothAbout =>
      'Evens out what is under the brush, taking the bumps down.';

  @override
  String get toolSculptFlattenLabel => 'Flatten';

  @override
  String get toolSculptFlattenAbout =>
      'Pulls everything under the brush toward one plane.';

  @override
  String get toolSculptGrabLabel => 'Grab';

  @override
  String get toolSculptGrabAbout =>
      'Drags the vertices under the brush along with the pointer.';

  @override
  String get toolSculptPinchLabel => 'Pinch';

  @override
  String get toolSculptPinchAbout =>
      'Pulls the vertices under the brush toward its centre.';

  @override
  String get toolSculptCreaseLabel => 'Crease';

  @override
  String get toolSculptCreaseAbout =>
      'Pinches and sinks at once, which is how a fold is cut in.';

  @override
  String get toolRetopoQuadLabel => 'Draw a quad';

  @override
  String get toolRetopoQuadAbout =>
      'Click four points on the high mesh; each one snaps to a vertex the new mesh already has, or lands on the surface.';

  @override
  String get toolRetopoAutoLabel => 'Retopologize';

  @override
  String get toolRetopoAutoAbout =>
      'Rebuilds the whole surface as quads at about the count the panel asks for, shrink-wrapped back onto the original.';

  @override
  String get toolRetopoBakeLabel => 'Bake the maps';

  @override
  String get toolRetopoBakeAbout =>
      'Bakes the high mesh\'s own surface into the low one\'s UVs — a normal map, an occlusion map, or both.';

  @override
  String get toolPaintBrushLabel => 'Brush';

  @override
  String get toolPaintBrushAbout =>
      'Paints onto the object\'s own texture, through its UVs — a stroke over a seam paints both islands.';

  @override
  String get toolPaintFillLabel => 'Fill the layer';

  @override
  String get toolPaintFillAbout =>
      'Floods the whole layer with the colour on the palette.';

  @override
  String get toolPaintClearLabel => 'Clear the layer';

  @override
  String get toolPaintClearAbout =>
      'Empties the layer without touching the ones under it.';

  @override
  String get toolSimSelectLabel => 'Select';

  @override
  String get toolSimSelectAbout =>
      'Pick the vertices a cloth hangs from, or the object to solve.';

  @override
  String get toolSimPinLabel => 'Pin the selection';

  @override
  String get toolSimPinAbout =>
      'Holds the selected vertices still while everything else falls.';

  @override
  String get toolSimBakeLabel => 'Bake';

  @override
  String get toolSimBakeAbout =>
      'Solves the whole clip and keeps it, so it can be scrubbed.';

  @override
  String get toolRenderSnapshotLabel => 'Render';

  @override
  String get toolRenderSnapshotAbout =>
      'Renders the project at the size on the panel, one tile at a time, and shows the result.';

  @override
  String get toolRenderSaveLabel => 'Save the picture';

  @override
  String get toolRenderSaveAbout => 'Writes the last render out as a PNG.';

  @override
  String get settingsClearDataTitle => 'Clear local data?';

  @override
  String get settingsClear => 'Clear';

  @override
  String get settingsCameraNavigation => 'Camera navigation';

  @override
  String get settingsKeys => 'Keys';

  @override
  String get settingsTransformTools => 'Move, rotate and scale';

  @override
  String get settingsWorkspace => 'Workspace';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsStepMove => 'Move';

  @override
  String get settingsStepTurn => 'Turn°';

  @override
  String get settingsStepScale => 'Scale';

  @override
  String get settingsShowHome => 'Show Home at launch';

  @override
  String get settingsSaveHistory => 'Save projects with their history';

  @override
  String get settingsLegal => 'Licence, privacy and the rest';

  @override
  String get settingsClearData => 'Clear local data';

  @override
  String get settingsClearDataBody =>
      'This removes the settings, the recent-files list and the autosave copy. Project files you saved yourself are left alone. It cannot be undone.';

  @override
  String get settingsCameraNavigationHelp =>
      'Which buttons and gestures orbit, pan and zoom.';

  @override
  String get settingsKeysHelp => 'Which set of shortcuts is live.';

  @override
  String get settingsTransformToolsHelp =>
      'Whether the key opens a transform at once or arms it for a drag.';

  @override
  String get settingsWorkspaceHelp => 'Which screens the mode switcher offers.';

  @override
  String get settingsLanguageHelp => 'What the interface is written in.';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageRussian => 'Russian';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsSnapSteps => 'Snap steps';

  @override
  String get settingsShowHomeHelp =>
      'The start screen, with recent models and the scenario cards.';

  @override
  String get settingsSaveHistoryHelp =>
      'Keeps what you could still undo inside the saved file.';

  @override
  String get settingsLegalSection => 'Legal and data';

  @override
  String get settingsClearDataHelp =>
      'Settings, the recent-files list and the autosave. Saved project files are not touched.';

  @override
  String get settingsLegalHelp =>
      'The documents this build shipped under, and the third-party licences.';

  @override
  String commandPaletteNoMatch(String said) {
    return 'nothing matches “$said”';
  }

  @override
  String get autorigTitle => 'Auto-rig';

  @override
  String get autorigCreate => 'Create';

  @override
  String get autorigDragMarker => 'Drag a marker to refine the joint';

  @override
  String get autorigTemplate => 'Template';

  @override
  String get autorigHumanoid => 'Humanoid';

  @override
  String get autorigQuadruped => 'Quadruped';

  @override
  String get autorigCustom => 'Custom';

  @override
  String get autorigComposition => 'Composition';

  @override
  String get autorigFingers => 'Fingers';

  @override
  String get autorigToes => 'Toes';

  @override
  String get autorigSpine => 'Spine';

  @override
  String get autorigFaceBones => 'Face bones';

  @override
  String get autorigIkChains => 'IK chains';

  @override
  String get autorigController => 'Rig controller';

  @override
  String get autorigBinding => 'Binding';

  @override
  String get autorigPrimaryWeights => 'Assign primary weights';

  @override
  String get autorigSymmetry => 'Symmetry';

  @override
  String get autorigBones => 'Bones';

  @override
  String get autorigDeforming => 'Deforming';

  @override
  String get autorigNone => 'None';

  @override
  String autorigMarkers(int placed, int total) {
    return 'Markers $placed of $total';
  }

  @override
  String get brushSize => 'Size';

  @override
  String get brushStrength => 'Strength';

  @override
  String get sculptBrush => 'Brush';

  @override
  String get sculptFalloffLinear => 'Linear';

  @override
  String get sculptFalloffSmooth => 'Smooth';

  @override
  String get sculptFalloffSharp => 'Sharp';

  @override
  String get sculptSymmetryX => 'Symmetry (X)';

  @override
  String get sculptSurface => 'Surface';

  @override
  String get sculptSubdivide => 'Subdivide';

  @override
  String get paintCanvas => 'Canvas';

  @override
  String get paintNothingYet => 'Nothing painted yet';

  @override
  String get paintLayers => 'Layers';

  @override
  String get paintAddLayer => 'Add a layer';

  @override
  String get paintColour => 'Colour';

  @override
  String get paintMask => 'Mask';

  @override
  String get paintMaskNone => 'None';

  @override
  String get bakeRetopology => 'Retopology';

  @override
  String get bakeTargetQuads => 'Target quads';

  @override
  String get bakeRetopologize => 'Retopologize';

  @override
  String get bakeMaps => 'Maps';

  @override
  String get bakeResolution => 'Resolution';

  @override
  String get simKind => 'Kind';

  @override
  String get simParameters => 'Parameters';

  @override
  String get simCollidesWith => 'Collides with';

  @override
  String get simNothingElse => 'Nothing else in the scene';

  @override
  String get simPinned => 'Pinned';

  @override
  String get simClearPins => 'Clear the pins';

  @override
  String get simClearCache => 'Clear the cache';

  @override
  String get renderPasses => 'Passes';

  @override
  String get renderStart => 'Render';

  @override
  String get renderNothingYet => 'Nothing rendered yet';

  @override
  String sculptFaces(int count) {
    return '$count faces';
  }

  @override
  String renderCancelTiles(int done, int total) {
    return 'Cancel · $done/$total';
  }

  @override
  String get weightsBrush => 'Brush';

  @override
  String get weightsPaint => 'Paint';

  @override
  String get weightsAssign => 'Assign';

  @override
  String get weightsRadius => 'Radius';

  @override
  String get weightsMirror => 'Mirror';

  @override
  String get weightsNormalize => 'Normalize';

  @override
  String get weightsSelectedVertex => 'Selected vertex';

  @override
  String get weightsNoVertex => 'No vertex under the brush yet';

  @override
  String get weightsNoInfluences => 'No influences on this vertex';

  @override
  String get weightsBones => 'Bones';

  @override
  String get weightsNoBones => 'No bones';

  @override
  String get morphsNoShapeKeys => 'No shape keys on this object';

  @override
  String get morphsAddDriver => 'Add driver';

  @override
  String get morphsKeyShape => 'Key this shape';

  @override
  String get morphsRemoveDriver => 'Remove driver';

  @override
  String get morphsFrom => 'From°';

  @override
  String get morphsTo => 'To°';

  @override
  String get retargetRootMotion => 'Root motion';

  @override
  String get retargetCorrections => 'Corrections';

  @override
  String get retargetLockFeet => 'Lock feet';

  @override
  String get retargetGroundY => 'Ground Y';

  @override
  String get retargetFootTolerance => 'Foot tolerance';

  @override
  String get retargetApply => 'Apply the retarget';

  @override
  String get uvMethod => 'Method';

  @override
  String get uvMargin => 'Margin';

  @override
  String get uvIslands => 'Islands';

  @override
  String get uvNoIslands => 'No islands';

  @override
  String get transportKeys => 'Keys';

  @override
  String get transportCurves => 'Curves';

  @override
  String get transportLoop => 'Loop';

  @override
  String uvIsland(int id) {
    return 'Island $id';
  }

  @override
  String get propDisplay => 'Display';

  @override
  String get propMaterial => 'Material';

  @override
  String get propNormals => 'Normals';

  @override
  String get propWire => 'Wire';

  @override
  String get propPerspective => 'Perspective';

  @override
  String get propOrthographic => 'Orthographic';

  @override
  String get propView => 'View';

  @override
  String get propObjects => 'Objects';

  @override
  String get propTransform => 'Transform';

  @override
  String get propSource => 'Source';

  @override
  String get propReimport => 'Re-import';

  @override
  String get propModifiers => 'Modifiers';

  @override
  String get propMorphs => 'Morphs';

  @override
  String get propLastOperation => 'Last operation';

  @override
  String get propSelection => 'Selection';

  @override
  String get propMesh => 'Mesh';

  @override
  String get propHealth => 'Health';

  @override
  String get propBudget => 'Budget';

  @override
  String get importTitle => 'Import';

  @override
  String get importUnit => 'Unit';

  @override
  String get importUpAxis => 'Up axis';

  @override
  String get importWeld => 'Weld coincident vertices';

  @override
  String get importWeldHelp =>
      'Builds real mesh topology; leave off to keep the file\'s own data exactly as it arrived.';

  @override
  String get importRecalculateNormals => 'Recalculate normals';

  @override
  String get importTriangulate => 'Triangulate n-gons';

  @override
  String get importLinkToSource => 'Link to source';

  @override
  String get importLinkToSourceHelp =>
      'Remember where this came from, so \"Re-import\" can read it again and keep the transform, materials and modifiers.';

  @override
  String get exportTitle => 'Export';

  @override
  String get exportTriangles => 'Triangles';

  @override
  String get exportBakeTransforms => 'Bake node transforms';

  @override
  String get exportBakeTransformsHelp =>
      'Move each object\'s position into its own vertices, so the file has no hierarchy to lose.';

  @override
  String get exportApplyModifiers => 'Apply modifiers';

  @override
  String get exportApplyModifiersHelp =>
      'Write the shape you see, with the mirrors and arrays folded in. Off writes the base mesh instead.';

  @override
  String get exportSelectionOnly => 'Selection only';

  @override
  String get exportSelectionOnlyHelp =>
      'Write what is selected and whatever hangs under it, leaving the rest of the project where it is.';

  @override
  String get exportCompressTextures => 'Compress textures (KTX2)';

  @override
  String get exportCompressTexturesHelp =>
      'Smaller images that a GPU reads without unpacking. Only the .f3d reader takes them.';

  @override
  String get exportReady => 'ready to export';

  @override
  String get exportShow => 'Show';

  @override
  String get shortcutEdgeLoop => 'Select the edge loop';

  @override
  String get shortcutEdgeRing => 'Select the edge ring';

  @override
  String get shortcutFinger => 'A finger';

  @override
  String get shortcutFingerHeld => 'A finger held still';

  @override
  String get shortcutPen => 'A pen';

  @override
  String get shortcutPenOtherEnd => 'The other end of the pen';

  @override
  String get shortcutOrbit => 'Orbit';

  @override
  String get shortcutPan => 'Pan';

  @override
  String get shortcutZoom => 'Zoom';

  @override
  String get exportNothing => 'Nothing to export';

  @override
  String exportOfBudget(int triangles, int budget, String profile) {
    return '$triangles of $budget ($profile)';
  }

  @override
  String get shortcutEdgeLoopKeys => 'Alt and a click, in mesh mode';

  @override
  String get shortcutEdgeRingKeys => 'Ctrl or ⌘, with Alt and a click';

  @override
  String get shortcutFingerKeys => 'Moves the camera, whatever tool is armed';

  @override
  String get shortcutFingerHeldKeys =>
      'Opens the menu, without nudging the camera first';

  @override
  String get shortcutPenKeys =>
      'Draws on the model, harder for a stronger stroke';

  @override
  String get shortcutPenOtherEndKeys => 'The same stroke, erasing';

  @override
  String get shortcutPanKeys => 'Shift and whatever orbits';

  @override
  String get shortcutZoomKeys => 'The wheel, or Ctrl with two fingers';

  @override
  String importWarnings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count warnings',
      one: '1 warning',
    );
    return '$_temp0';
  }

  @override
  String get shortcutOrbitMiddle =>
      'Middle button, Alt and the left button, or two fingers on a trackpad';

  @override
  String get shortcutOrbitLeft =>
      'Left button on empty space, the middle button, or two fingers on a trackpad';

  @override
  String get actionSave => 'Save';

  @override
  String get actionExport => 'Export';

  @override
  String get actionUndo => 'Undo';

  @override
  String get actionRedo => 'Redo';

  @override
  String get actionThisScreen => 'This screen';

  @override
  String get actionCommandPalette => 'Command palette';

  @override
  String get actionFoldPanel => 'Fold the properties panel';

  @override
  String get actionFoldRail => 'Fold the tool rail';

  @override
  String get actionGrowSelection => 'Grow the selection';

  @override
  String get actionShrinkSelection => 'Shrink the selection';

  @override
  String get actionBrushNarrower => 'Narrower brush';

  @override
  String get actionBrushWider => 'Wider brush';

  @override
  String get actionFrameSelection => 'Frame what is selected';

  @override
  String get actionFrameAll => 'Frame everything';

  @override
  String get actionViewFront => 'Front view';

  @override
  String get actionViewSide => 'Side view';

  @override
  String get actionViewTop => 'Top view';

  @override
  String get actionPlayPause => 'Play and pause';

  @override
  String get actionSelectAll => 'Select everything';

  @override
  String get actionSelectNone => 'Select nothing';

  @override
  String get actionInvertSelection => 'Invert the selection';

  @override
  String get actionToggleObjectMesh => 'Object and mesh';

  @override
  String get actionDelete => 'Delete';

  @override
  String get matNoMaterials => 'No materials';

  @override
  String get matAdd => 'Add material';

  @override
  String get matUnassign => 'Unassign';

  @override
  String get matOpenInEditor => 'Open in editor';

  @override
  String get matCutoff => 'Cutoff';

  @override
  String get matAdvanced => 'Advanced';

  @override
  String get matEmissiveStrength => 'Emissive strength';

  @override
  String get matNormalScale => 'Normal scale';

  @override
  String get matOcclusionStrength => 'Occlusion strength';

  @override
  String get matDoubleSided => 'Double-sided';

  @override
  String get sceneNoLights => 'No lights';

  @override
  String get sceneRemoveLight => 'Remove this light';

  @override
  String get sceneAdd => 'Add';

  @override
  String get sceneSource => 'Source';

  @override
  String get sceneIntensity => 'Intensity';

  @override
  String get sceneRange => 'Range';

  @override
  String get sceneCone => 'Cone';

  @override
  String get sceneCastsShadow => 'Casts shadow';

  @override
  String get quickSetupTitle => 'Set up the editor';

  @override
  String get quickSetupHelp =>
      'Five answers, once. Every one of them is in Settings afterwards.';

  @override
  String get quickSetupCamera => 'Camera';

  @override
  String get quickSetupHowMuch => 'How much of it';

  @override
  String get quickSetupStart => 'Start';

  @override
  String get pivotHelp =>
      'Where a turn or a scale from the boxes above is centred';

  @override
  String get pivotMedian => 'Median';

  @override
  String get pivotIndividual => 'Individual';

  @override
  String get pivotCursor => '3D Cursor';

  @override
  String get spaceHelp => 'Whose axes a turn from the boxes above is given in';

  @override
  String get spaceGlobal => 'Global';

  @override
  String get spaceLocal => 'Local';

  @override
  String get modifierMirror => 'Mirror';

  @override
  String get modifierArray => 'Array';

  @override
  String get modifierSmooth => 'Smooth';

  @override
  String get modifierSubdivision => 'Subdivision';

  @override
  String get modifierBoolean => 'Boolean';

  @override
  String get modifierNone => 'No modifiers';

  @override
  String get modifierAdd => 'Add a modifier';

  @override
  String get modifierAddShort => 'Add';

  @override
  String get modifierRemove => 'Remove it';

  @override
  String modifierTriangles(int before, int after) {
    return '$before → $after triangles';
  }

  @override
  String get latheSegments => 'Segments';

  @override
  String get latheClosed => 'Closed profile';

  @override
  String get latheAdd => 'Add';

  @override
  String get latheTitle => 'Lathe';

  @override
  String get saveAsTitle => 'Save as';

  @override
  String get saveWithoutHistory => 'Save without history';

  @override
  String get saveWithoutHistoryHelp =>
      'Undo will not be available after this file is reopened.';

  @override
  String get galleryTitle => 'Gallery';

  @override
  String get galleryClose => 'Close';

  @override
  String get gallerySearch => 'Search the gallery';

  @override
  String get galleryAll => 'All';

  @override
  String get galleryNoCredit => 'No credit needed';

  @override
  String get previewBudgets => 'Budgets';

  @override
  String get previewTitle => 'Preview';

  @override
  String get previewClose => 'Close preview';

  @override
  String get previewWireframe => 'Show wireframe';

  @override
  String get previewNotBuilt => 'not built for this screen yet';

  @override
  String get agentHide => 'Hide the agent panel';

  @override
  String get agentSession => 'Session';

  @override
  String get agentRenders => 'Renders';

  @override
  String get agentToolCalls => 'Tool calls';

  @override
  String get agentHistoryAuthor => 'History · author';

  @override
  String get agentUndoSteps => 'Undo agent steps';

  @override
  String get agentContactSheet => 'CONTACT SHEET';

  @override
  String get agentInsteadOfNumbers => 'what the agent gets instead of numbers';

  @override
  String get agentNoRenderYet => 'No render/renderSheet call yet this session';

  @override
  String get graphNextImage => 'Next image';

  @override
  String get graphAddNode => 'Add node';

  @override
  String get graphTitle => 'Texture graph';

  @override
  String get legalTitle => 'Legal';

  @override
  String get legalClose => 'Close';

  @override
  String get legalDocument => 'Document';

  @override
  String get legalEnglishOnly =>
      'These documents are published in English only, whatever the interface language: one authentic version, so there is never a question of which one binds.';

  @override
  String get legalThirdParty => 'Third-party licences';

  @override
  String get budgetTriangles => 'Triangles';

  @override
  String get budgetJoints => 'Joints';

  @override
  String get budgetTextureMemory => 'Texture memory';

  @override
  String get budgetInfluences => 'Influences';

  @override
  String get consoleAll => 'All';

  @override
  String get consoleYou => 'You';

  @override
  String get consoleAgent => 'Agent';

  @override
  String get consoleClose => 'Close the console';

  @override
  String previewLights(int lights, int shadowed, int cap) {
    return '$lights lights · $shadowed/$cap shadowed';
  }

  @override
  String agentSteps(int agent, int person) {
    return '$agent agent · $person yours';
  }

  @override
  String exportAnywayMore(int count) {
    return 'and $count more';
  }

  @override
  String legalLoadFailed(String error) {
    return 'The documents did not load: $error';
  }

  @override
  String metricsFps(int fps) {
    return '$fps fps';
  }

  @override
  String metricsDrawCalls(String count) {
    return '$count draw calls';
  }

  @override
  String metricsTriangles(String count) {
    return '$count triangles';
  }

  @override
  String metricsBones(String count) {
    return '$count bones';
  }

  @override
  String get metricsPasses => 'Frame passes';

  @override
  String metricsPassLine(
    String name,
    String ms,
    String draws,
    String triangles,
  ) {
    return '$name · $ms ms · $draws draws · $triangles tri';
  }

  @override
  String get captureTitle => 'Frame capture';

  @override
  String get captureTake => 'Capture a frame';

  @override
  String get captureWaiting => 'Capturing…';

  @override
  String get captureEmpty => 'Nothing captured yet';

  @override
  String capturePassLine(String name, String images) {
    return '$name · $images images';
  }

  @override
  String captureInactive(String name) {
    return '$name · did not run';
  }

  @override
  String captureReads(String names) {
    return 'reads $names';
  }

  @override
  String captureWrites(String names) {
    return 'writes $names';
  }

  @override
  String captureBlack(String name) {
    return '$name came back black';
  }

  @override
  String captureRefused(String name, String reason) {
    return '$name: $reason';
  }

  @override
  String galleryUnreachable(String names) {
    return '$names could not be reached; everything else is still here';
  }

  @override
  String get graphNextImageTooltip => 'Next image';

  @override
  String get statusShowFolder => 'Show folder';

  @override
  String get envClearPanorama => 'Clear the panorama';

  @override
  String get envAmbient => 'Ambient';

  @override
  String get animActions => 'Actions';

  @override
  String statusTexelDensity(String density) {
    return '$density tex/cm';
  }

  @override
  String statusTextureBudget(String used, String budget) {
    return '$used MB of $budget';
  }

  @override
  String statusFrameTime(String ms) {
    return '$ms ms';
  }

  @override
  String get animSkeleton => 'Skeleton';

  @override
  String get animConstraints => 'Constraints';

  @override
  String get crashTitle => 'Something went wrong';

  @override
  String get crashDismiss => 'Dismiss';

  @override
  String get crashReport => 'Report a problem';

  @override
  String get postBloom => 'Bloom';

  @override
  String get postExposure => 'Exposure';

  @override
  String get playStop => 'Stop';

  @override
  String get playReload => 'Reload';

  @override
  String get operationNothingDone => 'nothing done yet';

  @override
  String get operationHide => 'Hide this card';

  @override
  String get operationHideHelp => 'Hide this card without undoing it';

  @override
  String get operationNothingToAdjust => 'nothing to adjust';

  @override
  String get studioTitle => 'Material Studio';

  @override
  String get studioClose => 'Close';

  @override
  String get constraintsNone => 'No constraints';

  @override
  String get constraintsRemove => 'Remove this constraint';

  @override
  String get clipBlend => 'Blend';

  @override
  String get clipPreview => 'Preview';

  @override
  String get boneMapTitle => 'Bone map';

  @override
  String get boneMapAuto => 'Map automatically';

  @override
  String get animPickAction => 'Select or add an action to see its timeline';

  @override
  String get animPickTrack => 'Select a track in Keys mode to see its curve';

  @override
  String get startFrom => 'Start from';

  @override
  String get dialogClose => 'Close';

  @override
  String get nameField => 'Name';

  @override
  String get healthNothingWrong => 'Nothing wrong with it';

  @override
  String get clipSearch => 'Search clips';

  @override
  String get clipNoSource => 'No source imported yet';

  @override
  String get actionsNone => 'No actions';

  @override
  String get actionsAdd => 'Add';

  @override
  String get weightsPickBone => 'Select a bone to test its bend';

  @override
  String crashCommand(String name) {
    return 'Command: $name';
  }

  @override
  String crashRecent(String names) {
    return 'Recent commands: $names';
  }

  @override
  String playHint(String template) {
    return '$template  ·  WASD to walk, drag to look, Esc to stop';
  }

  @override
  String simCacheSemantics(int baked, int target) {
    return 'Simulation cache: $baked of $target frames baked';
  }

  @override
  String simCacheReadout(int baked, int target) {
    return '$baked / $target frames cached';
  }

  @override
  String healthSelectThem(String message) {
    return '$message, select them';
  }

  @override
  String lodThreshold(int index) {
    return 'LOD $index threshold';
  }

  @override
  String clipNoMatch(String query) {
    return 'No clips match “$query”';
  }

  @override
  String bakingMaps(int count) {
    return 'Baking $count maps…';
  }

  @override
  String get outlinerToTopLevel => 'to the top level';

  @override
  String get retargetImportSource => 'Import a source clip';

  @override
  String get skeletonNoJoints => 'No joints';

  @override
  String sceneLightNamed(int number, String kind) {
    return 'Light $number · $kind';
  }

  @override
  String get healthTriangulate => 'Triangulate';

  @override
  String get healthFill => 'Fill';

  @override
  String get healthMerge => 'Merge';

  @override
  String get healthRecalculate => 'Recalculate';

  @override
  String get healthFix => 'Fix';

  @override
  String get budgetProfile => 'Profile';

  @override
  String get importBounds => 'Bounds';

  @override
  String get propWhat => 'What';

  @override
  String get envNone => 'None';

  @override
  String get envStudio => 'Studio';

  @override
  String get envDaylight => 'Daylight';

  @override
  String get envSunset => 'Sunset';
}
