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
/// **The paint arrives a moment after the shape, and on purpose.** Building a
/// material means decoding the images it samples, which a frame cannot wait
/// for. So the stage is made and drawn first — every object in clay — and the
/// pool is filled after; `repaint` then puts the materials on without touching
/// a vertex buffer. Doing it the other way round would hold the first frame of
/// every opened file for as long as its textures take to decode.
Future<OpenedModel> openDocument(
  ModelDocument document, {
  required GraphicsDevice device,
}) async {
  final project = fromModelDocument(document);
  final stage = ModelerStage.fromProject(device: device, project: project);

  await stage.materials?.refresh(project);
  stage.sync?.repaint(project);

  return OpenedModel(project, stage);
}
