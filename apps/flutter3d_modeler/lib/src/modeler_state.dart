/// What the modeller is doing, as far as a screen is concerned.
///
/// **Everything a screen rebuilds on, and nothing a render loop reads sixty
/// times a second.** The orbit, the modal transform, the selection rectangle,
/// the frame timings and the element picker stay plain fields on
/// `_ModelerScreenState`: they change while a finger is down, and a state
/// object emitted per frame is an allocation and a rebuild of the whole shell
/// for a number only the viewport reads. What is here instead is the other
/// half — which document is open, what mode it is being edited in, and what to
/// say about the last thing that happened.
///
/// **The renderer, the stage and the history are carried live.** They are
/// mutated in place — the camera moves, the scene follows the project, the
/// history grows — and a state class that copied their numbers would be a state
/// class that disagreed with the thing on screen the moment either changed.
/// `EditorReady` next door carries a live `Editing` for the same reason and
/// says so. What *is* copied is everything above them: the mode, the tool, the
/// sentence and the readiness, which are values and are replaced by an `emit`.
///
/// **Readiness is a field rather than a call.** It used to be computed in
/// `build`, walking every object and every face on every frame. Here it is a
/// value the cubit refreshes when a command lands, which is the only moment it
/// can change — and a value cannot go stale behind a check that never runs,
/// which a getter can.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'staging.dart';
import 'ui/tools.dart';

sealed class ModelerState {
  const ModelerState();
}

/// Before the device is up: no renderer, nothing to draw with yet.
final class ModelerOpening extends ModelerState {
  const ModelerOpening();
}

/// A device is up and no document has been chosen.
///
/// **Not reachable from the interface yet, and here on purpose.** `ui-15` is
/// the start screen — open a file, pick from the recents, begin a new project
/// against a profile — and the state it needs is this one. Adding it now costs
/// a class and stops the start screen from being a reason to reshape everything
/// else later.
final class ModelerChoosing extends ModelerState {
  const ModelerChoosing({required this.said});

  /// What to say above the choices: usually why they are showing.
  final String said;
}

/// A document is open and being edited.
final class ModelerReady extends ModelerState {
  const ModelerReady({
    required this.renderer,
    required this.stage,
    required this.history,
    required this.readiness,
    this.mode = ModelerMode.object,
    this.submode = MeshSubmode.vertex,
    this.tool = 'object.select',
    this.said,
  });

  /// Live, and mutated by the frame loop.
  final Renderer renderer;

  /// Live: the camera moves inside it and `SceneSync` follows the project.
  final ModelerStage stage;

  /// Live: commands land in it and undo takes them back. The document.
  final ModelHistory history;

  /// What the model will refuse to export as, computed when a command lands
  /// rather than when a frame is drawn.
  final ExportReadiness readiness;

  final ModelerMode mode;

  /// Which element level the mesh mode is picking at. Kept while the object
  /// mode is on, so that going back into the mesh mode returns to the level
  /// somebody left — losing it is the kind of small rudeness an editor is
  /// judged by.
  final MeshSubmode submode;

  /// The tool the rail has lit, by id.
  final String? tool;

  /// The last thing worth saying: a file opened, an operation run, a refusal.
  /// Null when there is nothing to add and the status line falls back to
  /// describing the selection.
  final String? said;

  /// The project, which is what nearly every reader actually wants.
  ModelProject get project => history.project;

  ProjectSelection get selection => history.selection;

  ModelerReady copyWith({
    ModelerStage? stage,
    ExportReadiness? readiness,
    ModelerMode? mode,
    MeshSubmode? submode,
    String? tool,
    bool clearTool = false,
    String? said,
    bool clearSaid = false,
  }) => ModelerReady(
    renderer: renderer,
    stage: stage ?? this.stage,
    history: history,
    readiness: readiness ?? this.readiness,
    mode: mode ?? this.mode,
    submode: submode ?? this.submode,
    tool: clearTool ? null : (tool ?? this.tool),
    said: clearSaid ? null : (said ?? this.said),
  );
}

/// Nothing to draw with, or nothing that would open, and the sentence saying
/// why.
final class ModelerFailed extends ModelerState {
  const ModelerFailed(this.said);

  final String said;
}
