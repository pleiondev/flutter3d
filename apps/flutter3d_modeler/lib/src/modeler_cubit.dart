/// The screen's answers to what the document is doing.
///
/// **A thin layer over `ModelHistory`, `ReadinessCache` and `SceneSync`, not a
/// rewrite of any of them.** Running a command, taking it back and deciding
/// what a project refuses to export as already live in classes that need no
/// window and are already tested that way. What this adds is the part those do
/// not answer: which screen a person sees, which mode they are in, and what the
/// strip along the bottom says about the last thing that happened.
///
/// **Every method is a state transition somebody could write down as a
/// sentence**, which is what makes it reachable from a plain `test()` rather
/// than from a pumped widget — see `test/modeler_cubit_test.dart`. That is the
/// whole point of the class: before it, the only way to ask "does changing the
/// mode keep the selection" was to build a shell and press things.
///
/// **The three seams it keeps in step, and why they are here rather than
/// scattered.** A command lands, and three things must follow it: the scene has
/// to be brought to the new project, the readiness has to be recomputed, and
/// the sentence has to be replaced. Before this class each of those was a line
/// somebody had to remember to write next to every `history.run`, and the
/// selection commands forgot the second one.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'job_runner.dart';
import 'modeler_state.dart';
import 'staging.dart';
import 'timeline_playback.dart';
import 'ui/tools.dart';

export 'modeler_state.dart';

/// The command most recently handed to [ModelerCubit.ran], regardless of
/// whether it landed, refused, or threw.
///
/// **A global, because the reader is not a widget.** `ui-30n`'s own crash
/// handler in `main.dart` is a top-level function wired to `FlutterError.
/// onError`/`runZonedGuarded`: by the time it runs, the command that threw is
/// off the call stack and nowhere else still names it. Set on the line
/// before [ModelHistory.run] is called, so a throw from inside
/// [ModelCommand.apply] leaves this holding exactly the command that threw.
ModelCommand? lastAttemptedCommand;

/// `tut-16`'s own bound on `ModelerReady.agentCalls` — a long-running
/// `--mcp-port` session's own feed keeps growing otherwise; the history
/// list underneath it is bounded on its own terms already (`ModelHistory
/// .depth`), and this is the feed's equivalent.
const int _agentCallFeedLimit = 50;

final class ModelerCubit extends Cubit<ModelerState> {
  ModelerCubit() : super(const ModelerOpening());

  /// Readiness for the open document, recomputed only where the project moved.
  ///
  /// Owned here rather than by the screen because it is the cubit that knows
  /// when a project changed: every path that changes one goes through [ran],
  /// [undo], [redo] or [opened].
  final ReadinessCache _readiness = ReadinessCache();

  /// Every background job actually running, by the [JobKey] it answers for —
  /// `ui-25`'s own row, widened by `anim-25` to cover more than a bake.
  /// [ModelerReady.jobs] is this map's own progress, copied out for a screen
  /// to read; the running [Job] itself stays here, since [cancelJob] needs to
  /// reach it and a screen never does.
  ///
  /// **`Job<Object?>`, not one type parameter per job kind.** A bake answers
  /// with a [JobResult], a retarget with a [ProjectClip], a bind-weights
  /// with a [JobResult] again — three different `T`s sharing one map, which
  /// only [runJob]'s own `T` ever needs to be the real one, since nothing
  /// here calls a stored [Job]'s own `run` a second time.
  final Map<JobKey, Job<Object?>> _activeJobs = <JobKey, Job<Object?>>{};

  /// A document opened, with the world that draws it.
  void opened(
    ModelHistory history, {
    required Renderer renderer,
    required ModelerStage stage,
    String documentName = 'untitled',
    String? said,
  }) {
    // A different document entirely: the old answers name ids this project
    // does not have, and would sit in the map for the length of the session.
    _readiness.forget();
    emit(
      ModelerReady(
        renderer: renderer,
        stage: stage,
        history: history,
        readiness: _readiness.of(history.project),
        documentName: documentName,
        said: said,
      ),
    );
  }

  /// The same document, drawn through a new [renderer] and [stage] — a device
  /// reopened under it because the old one no longer fit the viewport
  /// (`ui-20`), not a new file. Mode, tool, selection and running jobs are
  /// left exactly as they were: this answers "what draws this" and nothing
  /// else, which is also why it does nothing off [ModelerReady].
  void redeviced({required Renderer renderer, required ModelerStage stage}) {
    final ModelerReady? now = _ready;
    if (now == null) return;
    emit(
      ModelerReady(
        renderer: renderer,
        stage: stage,
        history: now.history,
        readiness: now.readiness,
        documentName: now.documentName,
        mode: now.mode,
        submode: now.submode,
        tool: now.tool,
        said: now.said,
        saidIsImportant: now.saidIsImportant,
        jobs: now.jobs,
        playback: now.playback,
      ),
    );
  }

  /// Nothing could be opened at all — a device that would not start, or a file
  /// that would not read.
  void failed(String said) => emit(ModelerFailed(said));

  /// A device is up and there is no document yet. See [ModelerChoosing].
  void choosing({required String said}) => emit(ModelerChoosing(said: said));

  /// Runs [command] and brings everything that follows it into step.
  ///
  /// Returns whether it landed. A refused command leaves the document exactly
  /// as it was and says why — a refusal is an answer, not a failure, and the
  /// history is not touched by one.
  bool ran(ModelCommand command, {String? said}) {
    final ModelerReady? now = _ready;
    if (now == null) return false;

    lastAttemptedCommand = command;
    // `run` answers with the refusal, or null when it landed — a refusal is an
    // answer rather than a failure, and the history is not touched by one.
    final String? refused = now.history.run(command);
    if (refused != null) {
      emit(now.copyWith(said: refused));
      return false;
    }
    _synced(now, said: said ?? command.says);
    return true;
  }

  /// Takes back the step on top, or says there is none.
  void undo() {
    final ModelerReady? now = _ready;
    if (now == null) return;
    final String? took = now.history.undoSays;
    if (!now.history.undo()) {
      emit(now.copyWith(said: 'nothing to undo'));
      return;
    }
    _synced(now, said: took == null ? 'undone' : 'undone $took');
  }

  void redo() {
    final ModelerReady? now = _ready;
    if (now == null) return;
    if (!now.history.redo()) {
      emit(now.copyWith(said: 'nothing to redo'));
      return;
    }
    _synced(now, said: 'redone');
  }

  /// `tut-16`'s own button beside the ordinary undo: pops the top step only
  /// when `mcp-10n`'s own [StepAuthor.agent] made it, leaving a person's own
  /// work alone — [ModelHistory.undo]'s own `onlyIfAuthoredBy` is the whole
  /// of the restriction; this is that restriction, reported the way [undo]
  /// already reports the plain one.
  void undoAgentSteps() {
    final ModelerReady? now = _ready;
    if (now == null) return;
    if (now.history.topStepAuthor == null) {
      emit(now.copyWith(said: 'nothing to undo'));
      return;
    }
    if (now.history.topStepAuthor != StepAuthor.agent) {
      emit(now.copyWith(said: "the top step is yours, not the agent's"));
      return;
    }
    final String? took = now.history.undoSays;
    now.history.undo(onlyIfAuthoredBy: StepAuthor.agent);
    _synced(now, said: took == null ? 'undone' : 'undone $took');
  }

  /// `tut-16`'s own hook: `mcp_bootstrap_io.dart`'s `onToolCall` calls this
  /// after every MCP tool call answers, whether or not it touched the
  /// document — the feed wants every call, not only the ones that left a
  /// [HistoryStep] behind.
  ///
  /// **Resyncs the scene, the same half of [_synced] [documentMoved] runs.**
  /// A document tool call lands straight on the shared [ModelHistory]
  /// `ModelSession.run` holds, never through this cubit's own [ran] — so
  /// this is the only place the screen ever learns an agent's own edit
  /// landed and brings the viewport and the readiness to it. `said` is left
  /// untouched on purpose: `ui.say` (`mcp-16d`) already writes an important
  /// sentence to the status line through [say] itself, and clearing it here
  /// right after — every tool call, including that one — would undo the
  /// one thing [say]'s own `important` flag exists to protect.
  void agentToolCalled(AgentToolCall call) {
    final ModelerReady? now = _ready;
    if (now == null) return;
    final calls = List<AgentToolCall>.of(now.agentCalls)..add(call);
    if (calls.length > _agentCallFeedLimit) {
      calls.removeRange(0, calls.length - _agentCallFeedLimit);
    }
    now.stage.sync?.apply(now.project);
    now.stage.lighting?.sync(now.stage.scene, now.project.lighting);
    emit(
      now.copyWith(agentCalls: calls, readiness: _readiness.of(now.project)),
    );
  }

  /// Whatever changed the document outside a command — a transaction closed by
  /// a drag, an `amend` on the operation card — brought into step.
  ///
  /// The one door for "the history moved and I did it myself", so that the
  /// scene, the readiness and the sentence cannot be updated in two places
  /// and disagree.
  void documentMoved({String? said}) {
    final ModelerReady? now = _ready;
    if (now == null) return;
    _synced(now, said: said);
  }

  /// Runs [work] as one background [Job], tracked under [key] in
  /// [ModelerReady.jobs] for a `JobButton` to show and [cancelJob] to stop —
  /// the runner [bakeInBackground], [retargetInBackground] and
  /// [bindWeightsInBackground] all build on rather than each rolling its own.
  ///
  /// Answers [JobCancelled] instead of starting a second job when [key]
  /// already names one in flight — `modeler_cubit_test.dart`'s own "a second
  /// bake for the same object while one runs is refused", generalised to
  /// every job kind through [JobKey].
  ///
  /// **One chunk, because every job this wraps is already one opaque call.**
  /// [JobRequest.run] and its siblings in `flutter3d_model_core` each cross
  /// an isolate or stay small enough not to need one on their own account
  /// (`rig_job.dart`'s own class comment says which); splitting further here
  /// would mean this cubit reaching into work it does not own the shape of.
  /// The trade this makes: [cancelJob] stops a job that has not started
  /// running its one chunk yet, the same as the last of
  /// `job_runner_test.dart`'s own cases (`cancel` before `run` prevents every
  /// chunk); once [work] is under way there is no checkpoint inside it to
  /// stop at, so it runs to its own finish either way — an honest limit of
  /// wrapping one atomic call in a job, not a broken promise about what
  /// [cancelJob] does.
  ///
  /// **One microtask yield before [work] starts**, so a caller who calls
  /// [cancelJob] in the same synchronous stretch that started this (the
  /// ordinary shape: fire the job, then wire a cancel button to stop it)
  /// still lands before [Job.run] takes its own first look at whether it was
  /// asked to stop — without the yield, this function would already have run
  /// straight past that check by the time control ever returned to whoever
  /// called it.
  Future<JobOutcome<T>> runJob<T>(JobKey key, Future<T> Function() work) async {
    if (_activeJobs.containsKey(key)) return const JobCancelled();

    late T result;
    final job = Job<T>(
      chunkCount: 1,
      runChunk: (int _) async => result = await work(),
      onProgress: (double _) => _syncJobs(),
    );
    _activeJobs[key] = job;
    _syncJobs();
    await Future<void>.value();

    final JobOutcome<T> outcome = await job.run(() => result);
    _activeJobs.remove(key);
    _syncJobs();
    return outcome;
  }

  /// Bakes [objectId]'s own modifier stack up to and including [uptoIndex] in
  /// the background — `ui-25`'s own row, `doc-24`'s `JobRequest` the value it
  /// runs, [runJob] the runner.
  ///
  /// Answers whether the bake actually landed. False for every way it can
  /// come back empty-handed: there is nothing to bake, one is already running
  /// for this object, it was cancelled, or [ApplyJobResult] itself refused a
  /// [JobRequest.baseVersion] the object has since moved past.
  ///
  /// See [runJob] for what cancelling this can and cannot still catch.
  Future<bool> bakeInBackground(int objectId, int uptoIndex) async {
    final ModelerReady? now = _ready;
    if (now == null) return false;
    final JobRequest? request = jobRequestFor(now.project, objectId, uptoIndex);
    if (request == null) return false;

    final outcome = await runJob<JobResult>(
      JobKey.object(objectId),
      request.run,
    );
    if (outcome is! JobFinished<JobResult>) return false;
    return ran(
      ApplyJobResult.of(outcome.value),
      said: 'baked in the background',
    );
  }

  /// Retargets [request]'s own source clip onto its own target skeleton in
  /// the background, landing the answer through [ApplyClipResult] —
  /// `anim-25`'s own second [runJob] wrapper, `anim-17`'s
  /// `RetargetClipJobRequest` the value it runs.
  ///
  /// [clipIndex] is [ApplyClipResult.clipIndex]'s own convention carried
  /// straight through: null appends the retargeted clip as a new one, given
  /// replaces the clip already at that index (a re-run against a tightened
  /// bone map, say). It also keys the job in [ModelerReady.jobs] — an append
  /// under the index the new clip will land at if nothing else changes
  /// [ModelProject.clips]'s own length first, so two appends started in the
  /// same synchronous stretch collide the same way two bakes of the same
  /// object do, rather than both running unannounced.
  ///
  /// Answers the applied [ApplyClipResult] when it landed, so a caller can
  /// read [ApplyClipResult.clipIndex] back off it to know where the clip
  /// landed even when it appended — null for every way it can come back
  /// empty-handed, the same set [bakeInBackground] answers false for.
  Future<ApplyClipResult?> retargetInBackground(
    RetargetClipJobRequest request, {
    int? clipIndex,
  }) async {
    final ModelerReady? now = _ready;
    if (now == null) return null;

    final key = JobKey.clip(clipIndex ?? now.project.clips.length);
    final outcome = await runJob<ProjectClip>(key, request.run);
    if (outcome is! JobFinished<ProjectClip>) return null;

    final command = ApplyClipResult(clip: outcome.value, clipIndex: clipIndex);
    return ran(command, said: 'retargeted in the background') ? command : null;
  }

  /// Binds [request]'s own bones to its own mesh in the background, landing
  /// the answer through [ApplyJobResult] the same way [bakeInBackground]
  /// does — `anim-25`'s own third [runJob] wrapper, `anim-22`'s
  /// `BindWeightsJobRequest` the value it runs: the one rig job that crosses
  /// an isolate the way a mesh bake does, since it is `O(vertex count × bone
  /// count)` rather than the `O(keyframe count)` the clip bakes are
  /// (`rig_job.dart`'s own class comment).
  ///
  /// [JobKey.rig], not [JobKey.object]: a bake and a bind-weights can run on
  /// the same object at once, and sharing a slot would refuse the second as
  /// though it collided with the first when the two answer for different
  /// things entirely.
  Future<bool> bindWeightsInBackground(BindWeightsJobRequest request) async {
    if (_ready == null) return false;

    final outcome = await runJob<JobResult>(
      JobKey.rig(request.objectId),
      request.run,
    );
    if (outcome is! JobFinished<JobResult>) return false;
    return ran(
      ApplyJobResult.of(outcome.value),
      said: 'bound weights in the background',
    );
  }

  /// Asks [objectId]'s own background bake to stop, if one is running — see
  /// [runJob] for what that can and cannot still catch.
  void cancelBake(int objectId) => cancelJob(JobKey.object(objectId));

  /// Asks whatever background job [key] names to stop, if one is running —
  /// see [runJob] for what that can and cannot still catch.
  void cancelJob(JobKey key) => _activeJobs[key]?.cancel();

  void _syncJobs() {
    final ModelerReady? now = _ready;
    if (now == null) return;
    emit(
      now.copyWith(
        jobs: <ActiveJob>[
          for (final MapEntry<JobKey, Job<Object?>> entry
              in _activeJobs.entries)
            ActiveJob(key: entry.key, progress: entry.value.progress),
        ],
      ),
    );
  }

  /// Switches between placing objects and editing one.
  ///
  /// **The selection is not cleared**, which is the whole reason this is one
  /// line here rather than three at a call site: an object stays selected when
  /// somebody drops into the mesh mode to work on it, and the element level
  /// they left is the level they come back to.
  void mode(ModelerMode mode) {
    final ModelerReady? now = _ready;
    if (now == null || now.mode == mode) return;
    emit(now.copyWith(mode: mode, clearSaid: true));
  }

  /// Changes the element level, carrying the selection across.
  ///
  /// **Through `convertedTo`, so the selection survives the change.** Somebody
  /// who picked a face and pressed 1 wants its corners, not an empty viewport —
  /// and this is the second half of the same courtesy [mode] pays. It lives here
  /// rather than at the call site because there are two call sites, the chip and
  /// the number key, and they were the same eleven lines twice.
  void submode(MeshSubmode submode) {
    final ModelerReady? now = _ready;
    if (now == null || now.submode == submode) return;

    final ElementLevel level = levelOf(submode);
    final EditMesh? mesh = editMeshOf(now.project, now.selection);
    final ProjectSelection was = now.selection;
    now.history.selection = mesh == null
        ? was.copyWith(level: level)
        : was.copyWith(
            level: level,
            elements: was.asMeshSelection.convertedTo(mesh, level).ids.toList(),
          );
    emit(now.copyWith(submode: submode, clearSaid: true));
  }

  /// Changes which of the four animation workflows is on screen —
  /// `ui-40d`'s own row, [submode]'s counterpart for the animation mode.
  ///
  /// **No selection to carry across.** [submode] converts the held
  /// selection to the new element level because vertex, edge and face are
  /// one selection looked at three grains; pose, weight-paint, retarget and
  /// morphs are four different workflows with nothing in common to convert
  /// — an object held while posing is still the object held while painting
  /// its weights, unchanged.
  void animationSubmode(AnimationSubmode animationSubmode) {
    final ModelerReady? now = _ready;
    if (now == null || now.animationSubmode == animationSubmode) return;
    emit(now.copyWith(animationSubmode: animationSubmode, clearSaid: true));
  }

  /// `S2`'s own row: [Playback]'s coarse half, folded into the state exactly
  /// as `TimelinePlayback.onPlaybackChanged` reports it — one emit per play/
  /// pause/clip/speed/loop change, never per frame. The frame itself never
  /// reaches this class; see [ModelerReady.playback]'s own doc comment for
  /// where it lives instead.
  ///
  /// **Does not clear `said`, unlike [mode]/[submode]/[animationSubmode].**
  /// Those three answer a person switching what they are looking at, which
  /// is exactly when a stale sentence about the old view stops making sense.
  /// Pressing play is not that — a refusal or a save sitting in the status
  /// line is still true a moment later whether or not a clip started moving.
  void playback(Playback next) {
    final ModelerReady? now = _ready;
    if (now == null || now.playback == next) return;
    emit(now.copyWith(playback: next));
  }

  void tool(String? id) {
    final ModelerReady? now = _ready;
    if (now == null) return;
    emit(id == null ? now.copyWith(clearTool: true) : now.copyWith(tool: id));
  }

  /// Something worth saying that changed nothing — a file written, a refusal
  /// from outside a command, a measurement.
  ///
  /// [important], when [said] is set, marks it to survive a later routine
  /// clear (`say(null)` called by code with nothing new to report, such as a
  /// selection change) rather than being silently replaced by whatever the
  /// status line falls back to. A `say(null)` call itself is always routine:
  /// it clears [ModelerReady.said] unless the sentence sitting there was
  /// marked important, in which case it is left for a person to actually
  /// read — the whole point of marking it that way.
  void say(String? said, {bool important = false}) {
    final ModelerReady? now = _ready;
    if (now == null) return;
    if (said == null) {
      if (now.saidIsImportant) return;
      emit(now.copyWith(clearSaid: true));
      return;
    }
    emit(now.copyWith(said: said, saidIsImportant: important));
  }

  /// Autosave stopped working, for [reason], while writing into [folder].
  ///
  /// `ux-01`'s own row: says so in the status line, and keeps the reason on
  /// the state so the line can go on offering the folder after the sentence
  /// itself has been replaced by whatever happened next. An important `say`,
  /// because a recovery copy that is not being written is precisely the news
  /// a routine selection change must not bury.
  void autosaveFailed(String reason, {String? folder}) {
    final ModelerReady? now = _ready;
    if (now == null) return;
    emit(
      now.copyWith(
        said: 'Autosave is not working: $reason',
        saidIsImportant: true,
        autosaveTrouble: (reason: reason, folder: folder),
      ),
    );
  }

  /// Autosave is writing again — the mirror of [autosaveFailed], so the offer
  /// to show the folder goes away with the trouble that raised it.
  void autosaveRecovered() {
    final ModelerReady? now = _ready;
    if (now == null || now.autosaveTrouble == null) return;
    emit(
      now.copyWith(
        said: 'Autosave is working again',
        clearAutosaveTrouble: true,
      ),
    );
  }

  /// Brings the scene to the project and the readiness with it.
  ///
  /// The three-in-one this class exists for. `SceneSync.apply` answers with how
  /// many buffers it had to upload, which is the number that must be zero while
  /// somebody is dragging — it is dropped here and read by the frame test.
  void _synced(ModelerReady now, {String? said}) {
    now.stage.sync?.apply(now.project);
    // `tut-07`'s own fix: the scene's own lights follow `project.lighting`
    // the same way its objects already follow `project.objects` above.
    now.stage.lighting?.sync(now.stage.scene, now.project.lighting);
    // `view-27d`'s own "more than 64 joints is a status line, never a
    // throw": `SceneSync.apply` refuses to build an over-large skeleton
    // rather than let its constructor throw, and reports it here the same
    // way a refused command already does — a message worth reading, not an
    // exception nothing catches.
    final String? overflow = now.stage.sync?.skeletonOverflow;
    final String? message = overflow ?? said;
    emit(
      now.copyWith(
        readiness: _readiness.of(now.project),
        said: message,
        clearSaid: message == null,
        saidIsImportant: overflow != null,
      ),
    );
  }

  ModelerReady? get _ready =>
      state is ModelerReady ? state as ModelerReady : null;
}

/// The element level a sub-mode names.
ElementLevel levelOf(MeshSubmode submode) => switch (submode) {
  MeshSubmode.vertex => ElementLevel.vertex,
  MeshSubmode.edge => ElementLevel.edge,
  MeshSubmode.face => ElementLevel.face,
};

/// The half-edge mesh behind the selected object, when it has one.
///
/// Null for a parametric shape and for anything imported: neither has topology
/// to select elements of, which is what makes the mesh mode empty for them
/// rather than broken.
EditMesh? editMeshOf(ModelProject project, ProjectSelection selection) =>
    switch (project[selection.activeObject ?? -1]?.geometry) {
      EditedGeometry(:final EditMesh mesh) => mesh,
      _ => null,
    };
