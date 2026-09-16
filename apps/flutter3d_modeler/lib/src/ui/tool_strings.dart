/// `ux-22`: what the rail, the palette and the tablet sheet call each
/// tool, in the language the person picked.
///
/// **`ModelerTool.label`/`about` stay English and stay where they are.**
/// They are what `ui.commands()` hands an agent and what the journal
/// quotes, and both of those are English by the same rule `says` is:
/// a tool's own name is part of the document's vocabulary, not part of
/// the interface. This is the interface's half.
///
/// A switch rather than a map: `AppLocalizations`' getters are
/// generated, so a string cannot reach one, and a map would build all
/// ninety strings to answer for one.
library;

import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import 'tools.dart';

/// [tool]'s own name, translated — its English label where this build
/// has no translation for it, which is what a tool added without one
/// would otherwise show as a blank.
String toolLabel(AppLocalizations l, ModelerTool tool) => switch (tool.id) {
  'object.select' => l.toolObjectSelectLabel,
  'object.move' => l.toolObjectMoveLabel,
  'object.rotate' => l.toolObjectRotateLabel,
  'object.scale' => l.toolObjectScaleLabel,
  'object.add' => l.toolObjectAddLabel,
  'object.duplicate' => l.toolObjectDuplicateLabel,
  'object.bake' => l.toolObjectBakeLabel,
  'object.lathe' => l.toolObjectLatheLabel,
  'object.origin' => l.toolObjectOriginLabel,
  'object.apply' => l.toolObjectApplyLabel,
  'object.delete' => l.toolObjectDeleteLabel,
  'mesh.select' => l.toolMeshSelectLabel,
  'mesh.lasso' => l.toolMeshLassoLabel,
  'mesh.linked' => l.toolMeshLinkedLabel,
  'mesh.move' => l.toolMeshMoveLabel,
  'mesh.rotate' => l.toolMeshRotateLabel,
  'mesh.scale' => l.toolMeshScaleLabel,
  'mesh.extrude' => l.toolMeshExtrudeLabel,
  'mesh.loopCut' => l.toolMeshLoopCutLabel,
  'mesh.bevel' => l.toolMeshBevelLabel,
  'mesh.inset' => l.toolMeshInsetLabel,
  'mesh.bridge' => l.toolMeshBridgeLabel,
  'mesh.slide' => l.toolMeshSlideLabel,
  'mesh.triangulate' => l.toolMeshTriangulateLabel,
  'mesh.separate' => l.toolMeshSeparateLabel,
  'mesh.dissolve' => l.toolMeshDissolveLabel,
  'mesh.fillHoles' => l.toolMeshFillHolesLabel,
  'mesh.merge' => l.toolMeshMergeLabel,
  'mesh.normals' => l.toolMeshNormalsLabel,
  'mesh.flip' => l.toolMeshFlipLabel,
  'mesh.delete' => l.toolMeshDeleteLabel,
  'pose.select' => l.toolPoseSelectLabel,
  'pose.key' => l.toolPoseKeyLabel,
  'pose.deleteKey' => l.toolPoseDeleteKeyLabel,
  'pose.autoRig' => l.toolPoseAutoRigLabel,
  'weights.paint' => l.toolWeightsPaintLabel,
  'weights.assign' => l.toolWeightsAssignLabel,
  'weights.mirror' => l.toolWeightsMirrorLabel,
  'weights.normalize' => l.toolWeightsNormalizeLabel,
  'retarget.import' => l.toolRetargetImportLabel,
  'retarget.autoMap' => l.toolRetargetAutoMapLabel,
  'retarget.apply' => l.toolRetargetApplyLabel,
  'morphs.add' => l.toolMorphsAddLabel,
  'morphs.key' => l.toolMorphsKeyLabel,
  'morphs.delete' => l.toolMorphsDeleteLabel,
  _ => tool.label,
};

/// [tool]'s own sentence — `ux-18`'s own second line, translated.
String toolAbout(AppLocalizations l, ModelerTool tool) => switch (tool.id) {
  'object.select' => l.toolObjectSelectAbout,
  'object.move' => l.toolObjectMoveAbout,
  'object.rotate' => l.toolObjectRotateAbout,
  'object.scale' => l.toolObjectScaleAbout,
  'object.add' => l.toolObjectAddAbout,
  'object.duplicate' => l.toolObjectDuplicateAbout,
  'object.bake' => l.toolObjectBakeAbout,
  'object.lathe' => l.toolObjectLatheAbout,
  'object.origin' => l.toolObjectOriginAbout,
  'object.apply' => l.toolObjectApplyAbout,
  'object.delete' => l.toolObjectDeleteAbout,
  'mesh.select' => l.toolMeshSelectAbout,
  'mesh.lasso' => l.toolMeshLassoAbout,
  'mesh.linked' => l.toolMeshLinkedAbout,
  'mesh.move' => l.toolMeshMoveAbout,
  'mesh.rotate' => l.toolMeshRotateAbout,
  'mesh.scale' => l.toolMeshScaleAbout,
  'mesh.extrude' => l.toolMeshExtrudeAbout,
  'mesh.loopCut' => l.toolMeshLoopCutAbout,
  'mesh.bevel' => l.toolMeshBevelAbout,
  'mesh.inset' => l.toolMeshInsetAbout,
  'mesh.bridge' => l.toolMeshBridgeAbout,
  'mesh.slide' => l.toolMeshSlideAbout,
  'mesh.triangulate' => l.toolMeshTriangulateAbout,
  'mesh.separate' => l.toolMeshSeparateAbout,
  'mesh.dissolve' => l.toolMeshDissolveAbout,
  'mesh.fillHoles' => l.toolMeshFillHolesAbout,
  'mesh.merge' => l.toolMeshMergeAbout,
  'mesh.normals' => l.toolMeshNormalsAbout,
  'mesh.flip' => l.toolMeshFlipAbout,
  'mesh.delete' => l.toolMeshDeleteAbout,
  'pose.select' => l.toolPoseSelectAbout,
  'pose.key' => l.toolPoseKeyAbout,
  'pose.deleteKey' => l.toolPoseDeleteKeyAbout,
  'pose.autoRig' => l.toolPoseAutoRigAbout,
  'weights.paint' => l.toolWeightsPaintAbout,
  'weights.assign' => l.toolWeightsAssignAbout,
  'weights.mirror' => l.toolWeightsMirrorAbout,
  'weights.normalize' => l.toolWeightsNormalizeAbout,
  'retarget.import' => l.toolRetargetImportAbout,
  'retarget.autoMap' => l.toolRetargetAutoMapAbout,
  'retarget.apply' => l.toolRetargetApplyAbout,
  'morphs.add' => l.toolMorphsAddAbout,
  'morphs.key' => l.toolMorphsKeyAbout,
  'morphs.delete' => l.toolMorphsDeleteAbout,
  _ => tool.about,
};

/// The localisations [context] can reach, or null where nothing installed
/// them.
///
/// **`AppLocalizations.of` asserts rather than answering null**, which is
/// right for a screen inside the application and wrong for a widget a test
/// pumps on its own: every shell test in this suite builds the rail without
/// a `MaterialApp`'s delegates, and none of them is about language. So the
/// two helpers below fall back to the English `ModelerTool` carries, which
/// is what those tests were reading before this row and what they go on
/// reading after it.
AppLocalizations? modelerStrings(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations);

/// [tool]'s own name in [context]'s language.
String toolLabelIn(BuildContext context, ModelerTool tool) {
  final AppLocalizations? l = modelerStrings(context);
  return l == null ? tool.label : toolLabel(l, tool);
}

/// [tool]'s own sentence in [context]'s language.
String toolAboutIn(BuildContext context, ModelerTool tool) {
  final AppLocalizations? l = modelerStrings(context);
  return l == null ? tool.about : toolAbout(l, tool);
}
