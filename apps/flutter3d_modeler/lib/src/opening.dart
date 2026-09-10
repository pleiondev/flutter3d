/// What opening a model file leaves behind.
///
/// **One function returning both halves, because the bug this replaced was the
/// two halves disagreeing.** Opening used to instantiate the decoded model into
/// a scene and, separately, start a fresh project holding a cube. Both lines
/// were correct on their own and the application they made was not: the model
/// was on the screen and the document described something else, so the outliner
/// listed a cube, a click selected nothing that was drawn, undo had no edits to
/// take back and the export readiness measured a shape nobody could see.
///
/// The repair is not a comment saying to keep them in step. It is that there is
/// no way to get one without the other: [openDocument] builds the project and
/// builds the stage *from that project*, and hands back the pair. A caller that
/// wants a scene has already got the document it draws.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'staging.dart';

/// A model that has been opened: the document a person now edits, and the
/// scene that draws it.
final class OpenedModel {
  const OpenedModel(this.project, this.stage);

  /// The objects the file became. What the outliner lists, what a click
  /// selects, what undo takes back and what an export writes.
  final ModelProject project;

  /// The scene built from [project], with a node per object.
  final ModelerStage stage;
}

/// [document] as a project, and a stage drawing that project.
///
/// The framing is left to the caller: where the camera goes when a file opens
/// is a viewport decision, and the measurement stands open documents without
/// wanting one.
///
/// **The materials do not come across yet.** A [ModelProject] has no material
/// table, so every object arrives as untextured clay and a model that had a
/// base colour opens without it — `mat-01`. Keeping the textures by
/// instantiating the asset instead is what this function exists to stop: a
/// model that is the wrong colour can still be edited, moved, undone and
/// exported, and a model that never reached the document can do none of those.
OpenedModel openDocument(
  ModelDocument document, {
  required GraphicsDevice device,
}) {
  final project = fromModelDocument(document);
  return OpenedModel(
    project,
    ModelerStage.fromProject(device: device, project: project),
  );
}
