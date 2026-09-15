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

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'staging.dart';
import 'timeline_playback.dart';
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
    this.documentName = 'untitled',
    this.mode = ModelerMode.object,
    this.submode = MeshSubmode.vertex,
    this.animationSubmode = AnimationSubmode.pose,
    this.tool = 'object.select',
    this.said,
    this.saidIsImportant = false,
    this.jobs = const <ActiveJob>[],
    this.playback = const Playback(),
    this.agentCalls = const <AgentToolCall>[],
    this.autosaveTrouble,
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

  /// What opened this document, or the profile's own default subject when
  /// nothing was — the top bar's and the window title's own single source
  /// for "which file is this," which neither read from before this field
  /// existed.
  final String documentName;

  final ModelerMode mode;

  /// Which element level the mesh mode is picking at. Kept while the object
  /// mode is on, so that going back into the mesh mode returns to the level
  /// somebody left — losing it is the kind of small rudeness an editor is
  /// judged by.
  final MeshSubmode submode;

  /// Which of the four animation workflows the animation mode is showing —
  /// `ui-40d`'s own field, [submode]'s counterpart for [ModelerMode.animation].
  /// Kept the same way across a trip through another mode, for the same
  /// reason [submode] is.
  final AnimationSubmode animationSubmode;

  /// The tool the rail has lit, by id.
  final String? tool;

  /// The last thing worth saying: a file opened, an operation run, a refusal.
  /// Null when there is nothing to add and the status line falls back to
  /// describing the selection.
  final String? said;

  /// Whether [said] should survive a routine clear — a selection change from
  /// a click or a box-drag, which happens far more often than a person reads
  /// the status line, and is not itself news worth burying a save/open/export
  /// outcome under. Only `ModelerCubit.say`'s own routine clear (a `null`
  /// passed by code that has nothing new to add) checks this; a mode change
  /// or a fresh `say` with something to report still replace [said]
  /// unconditionally, the same as before this field existed.
  final bool saidIsImportant;

  /// Background bakes in progress, for a `JobButton` to show — `ui-25`'s own
  /// row. Empty whenever nothing is baking, which is almost always.
  final List<ActiveJob> jobs;

  /// `S2`'s own coarse transport state — play/pause, which clip, the speed,
  /// the loop mode — one emit per change of any of those, never per frame.
  /// The playhead itself is not here: `_ModelerScreenState`'s own
  /// `ValueNotifier<int>` carries that at the sixty-times-a-second grain a
  /// value on this class would repaint the whole shell for.
  final Playback playback;

  /// `tut-16`'s own feed: every MCP tool call this session's own
  /// `--mcp-port` server has answered, oldest first, bounded to
  /// `ModelerCubit.agentToolCalled`'s own limit — `AgentSessionPanel`'s
  /// "tool calls" list reads this directly. Empty whenever no
  /// `--mcp-port` session is open, or one is open but nothing has called it
  /// yet.
  final List<AgentToolCall> agentCalls;

  /// Why autosave is not writing, and where it was trying to write — null
  /// whenever it is working, which is the ordinary case.
  ///
  /// `ux-01`'s own row: the live run found this failing silently for a whole
  /// session behind one unexplained "could not write" in the status line.
  /// A reason a person can act on, and a folder they can be shown, are the
  /// two things that sentence was missing; [folder] is null on the web, where
  /// there is nothing to show.
  final ({String reason, String? folder})? autosaveTrouble;

  /// The project, which is what nearly every reader actually wants.
  ModelProject get project => history.project;

  ProjectSelection get selection => history.selection;

  ModelerReady copyWith({
    ModelerStage? stage,
    ExportReadiness? readiness,
    ModelerMode? mode,
    MeshSubmode? submode,
    AnimationSubmode? animationSubmode,
    String? tool,
    bool clearTool = false,
    String? said,
    bool clearSaid = false,
    bool saidIsImportant = false,
    List<ActiveJob>? jobs,
    Playback? playback,
    List<AgentToolCall>? agentCalls,
    ({String reason, String? folder})? autosaveTrouble,
    bool clearAutosaveTrouble = false,
  }) => ModelerReady(
    renderer: renderer,
    stage: stage ?? this.stage,
    history: history,
    readiness: readiness ?? this.readiness,
    documentName: documentName,
    mode: mode ?? this.mode,
    submode: submode ?? this.submode,
    animationSubmode: animationSubmode ?? this.animationSubmode,
    tool: clearTool ? null : (tool ?? this.tool),
    said: clearSaid ? null : (said ?? this.said),
    saidIsImportant: clearSaid
        ? false
        : (said != null ? saidIsImportant : this.saidIsImportant),
    jobs: jobs ?? this.jobs,
    playback: playback ?? this.playback,
    agentCalls: agentCalls ?? this.agentCalls,
    autosaveTrouble: clearAutosaveTrouble
        ? null
        : (autosaveTrouble ?? this.autosaveTrouble),
  );
}

/// One background job in progress, as far as a screen needs to know —
/// `ui-25`'s own row, [key] telling apart the three families `anim-25`
/// widens it to: `ModelerCubit.bakeInBackground`, `retargetInBackground` and
/// `bindWeightsInBackground`.
///
/// **Progress only, not the [Job] itself.** The running `Job` stays inside
/// `ModelerCubit`'s own bookkeeping, since a `Job` carries a callback
/// closure and a mutable cancel flag, neither of which belongs in a value a
/// screen compares with `==` to decide whether to rebuild.
final class ActiveJob {
  const ActiveJob({required this.key, required this.progress});

  /// Which job this answers for — the same value `ModelerCubit.cancelJob`
  /// takes to stop it.
  final JobKey key;

  /// 0 to 1, [Job.progress]'s own number at the moment this was built.
  final double progress;

  /// [key]'s own [JobKey.objectId] — the object a `JobButton` drawn for one
  /// particular object compares itself against, without switching on [key]'s
  /// variant to ask.
  int? get objectId => key.objectId;

  @override
  bool operator ==(Object other) =>
      other is ActiveJob && other.key == key && other.progress == progress;

  @override
  int get hashCode => Object.hash(key, progress);

  @override
  String toString() => 'ActiveJob(key: $key, progress: $progress)';
}

/// Which background job an [ActiveJob] reports on, and what
/// `ModelerCubit.runJob` keys its bookkeeping by so a bake and a rig job on
/// the same object never share a slot.
///
/// **Three variants because three jobs answer for different things.**
/// [JobKey.object] names the object a `bakeInBackground` folds a modifier
/// stack for; [JobKey.rig] names the object a `bindWeightsInBackground`
/// binds a skin for — kept apart from [JobKey.object] even when both name
/// the same id, since baking and binding are two different jobs that can run
/// on one object at once; [JobKey.clip] names the clip index a
/// `retargetInBackground` answers for, [ApplyClipResult.clipIndex]'s own
/// convention of null-appends/given-replaces carried straight through — a
/// caller retargeting onto a fresh clip and a caller re-baking clip 2 are
/// two different jobs even though neither names an object at all.
sealed class JobKey {
  const JobKey();

  /// `bakeInBackground`, for object [id]'s own modifier stack.
  const factory JobKey.object(int id) = JobKeyObject;

  /// `retargetInBackground`, for the clip [index] names — the clip index a
  /// caller passed as `clipIndex` when it replaces one, or the index the
  /// retargeted clip will land at when it appends (`clipIndex: null`, so
  /// there is nothing to key by yet except where the append will land).
  const factory JobKey.clip(int index) = JobKeyClip;

  /// `bindWeightsInBackground`, for object [objectId]'s own mesh.
  const factory JobKey.rig(int objectId) = JobKeyRig;

  /// The object this job answers for — null for [JobKeyClip], which answers
  /// for a clip rather than one object.
  int? get objectId;
}

final class JobKeyObject extends JobKey {
  const JobKeyObject(this.objectId);

  @override
  final int objectId;

  @override
  bool operator ==(Object other) =>
      other is JobKeyObject && other.objectId == objectId;

  @override
  int get hashCode => Object.hash(JobKeyObject, objectId);

  @override
  String toString() => 'JobKey.object($objectId)';
}

final class JobKeyClip extends JobKey {
  const JobKeyClip(this.index);

  final int index;

  @override
  int? get objectId => null;

  @override
  bool operator ==(Object other) => other is JobKeyClip && other.index == index;

  @override
  int get hashCode => Object.hash(JobKeyClip, index);

  @override
  String toString() => 'JobKey.clip($index)';
}

final class JobKeyRig extends JobKey {
  const JobKeyRig(this.objectId);

  @override
  final int objectId;

  @override
  bool operator ==(Object other) =>
      other is JobKeyRig && other.objectId == objectId;

  @override
  int get hashCode => Object.hash(JobKeyRig, objectId);

  @override
  String toString() => 'JobKey.rig($objectId)';
}

/// One call an agent made over `--mcp-port` — `tut-16`'s own row: screen
/// 26's "tool calls" feed reads a bounded list of these, appended as they
/// happen by `mcp_bootstrap_io.dart`'s own `onToolCall` hook
/// (`flutter3d_model_mcp`'s `ModelHttpServer.start`/`ModelMcpServer`,
/// `flutter3d_mcp_kit`'s `ToolTableServer.onCall` underneath both).
///
/// **Not a `HistoryStep`.** A history step is only ever a document command
/// that actually landed; a tool call is every MCP call at all — a `ui.*`
/// tool that changes no document, a `list`/`check` that answers with no
/// step of its own, and a `render`/`renderSheet` call that draws a picture
/// rather than editing anything. The feed wants all of them; only
/// `ModelHistory.steps` wants the narrower set.
final class AgentToolCall {
  const AgentToolCall({
    required this.tool,
    required this.arguments,
    required this.did,
    required this.says,
    required this.elapsed,
    required this.at,
    this.png,
  });

  /// The tool's own name, e.g. `render` or `ui.setMode`.
  final String tool;

  /// What the agent called it with, straight off the request — read, never
  /// mutated, by whatever formats a line out of it for the feed.
  final Map<String, Object?> arguments;

  /// Whether it did anything, the same `did` every `Answer`/`PictureAnswer`
  /// in this repository already carries.
  final bool did;

  /// What it said — the sentence a person reads in the feed.
  final String says;

  /// How long the call took to answer.
  final Duration elapsed;

  /// When it was made, for the feed's own clock.
  final DateTime at;

  /// The picture a `render`/`renderSheet` call answered with, when it drew
  /// one — the contact sheet's own source; every other tool leaves this
  /// null.
  final Uint8List? png;
}

/// Nothing to draw with, or nothing that would open, and the sentence saying
/// why.
final class ModelerFailed extends ModelerState {
  const ModelerFailed(this.said);

  final String said;
}
