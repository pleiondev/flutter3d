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
import 'ui/tools.dart';

export 'modeler_state.dart';

final class ModelerCubit extends Cubit<ModelerState> {
  ModelerCubit() : super(const ModelerOpening());

  /// Readiness for the open document, recomputed only where the project moved.
  ///
  /// Owned here rather than by the screen because it is the cubit that knows
  /// when a project changed: every path that changes one goes through [ran],
  /// [undo], [redo] or [opened].
  final ReadinessCache _readiness = ReadinessCache();

  /// Every background bake actually running, by the object it answers for —
  /// `ui-25`'s own row. [ModelerReady.jobs] is this map's own progress,
  /// copied out for a screen to read; the running [Job] itself stays here,
  /// since [cancelBake] needs to reach it and a screen never does.
  final Map<int, Job<JobResult?>> _activeJobs = <int, Job<JobResult?>>{};

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

  /// Bakes [objectId]'s own modifier stack up to and including [uptoIndex] in
  /// the background — `ui-25`'s own row, `doc-24`'s `JobRequest` the value it
  /// runs.
  ///
  /// Answers whether the bake actually landed. False for every way it can
  /// come back empty-handed: there is nothing to bake, one is already running
  /// for this object, it was cancelled, or [ApplyJobResult] itself refused a
  /// [JobRequest.baseVersion] the object has since moved past.
  ///
  /// **One chunk, because [JobRequest.run] is one opaque call.** It already
  /// crosses to another isolate on its own (`editInIsolate`), which is the
  /// row's own "`Isolate.run` на native" — chunking further would mean
  /// splitting one modifier stack's bake into per-modifier isolate hops,
  /// several times the cost for a stack that is rarely more than a handful of
  /// steps. The trade this makes: [cancelBake] stops a bake that has not
  /// started running its one chunk yet, the same as the last of
  /// `job_runner_test.dart`'s own cases (`cancel` before `run` prevents every
  /// chunk); once the isolate call is under way there is no checkpoint inside
  /// it to stop at, so it runs to its own finish either way — an honest limit
  /// of wrapping one atomic call in a job, not a broken promise about what
  /// [cancelBake] does.
  ///
  /// **One microtask yield before the chunk starts**, so a caller who calls
  /// [cancelBake] in the same synchronous stretch that started this (the
  /// ordinary shape: fire the bake, then wire the cancel button to stop it)
  /// still lands before [Job.run] takes its own first look at whether it was
  /// asked to stop — without the yield, this function would already have run
  /// straight past that check by the time control ever returned to whoever
  /// called it.
  Future<bool> bakeInBackground(int objectId, int uptoIndex) async {
    final ModelerReady? now = _ready;
    if (now == null) return false;
    if (_activeJobs.containsKey(objectId)) return false;
    final JobRequest? request = jobRequestFor(now.project, objectId, uptoIndex);
    if (request == null) return false;

    JobResult? result;
    final job = Job<JobResult?>(
      chunkCount: 1,
      runChunk: (int _) async => result = await request.run(),
      onProgress: (double _) => _syncJobs(),
    );
    _activeJobs[objectId] = job;
    _syncJobs();
    await Future<void>.value();

    final JobOutcome<JobResult?> outcome = await job.run(() => result);
    _activeJobs.remove(objectId);
    _syncJobs();

    if (outcome is! JobFinished<JobResult?> || outcome.value == null) {
      return false;
    }
    return ran(
      ApplyJobResult.of(outcome.value!),
      said: 'baked in the background',
    );
  }

  /// Asks [objectId]'s own background bake to stop, if one is running — see
  /// [bakeInBackground] for what that can and cannot still catch.
  void cancelBake(int objectId) => _activeJobs[objectId]?.cancel();

  void _syncJobs() {
    final ModelerReady? now = _ready;
    if (now == null) return;
    emit(
      now.copyWith(
        jobs: <ActiveJob>[
          for (final MapEntry<int, Job<JobResult?>> entry
              in _activeJobs.entries)
            ActiveJob(objectId: entry.key, progress: entry.value.progress),
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

  /// Brings the scene to the project and the readiness with it.
  ///
  /// The three-in-one this class exists for. `SceneSync.apply` answers with how
  /// many buffers it had to upload, which is the number that must be zero while
  /// somebody is dragging — it is dropped here and read by the frame test.
  void _synced(ModelerReady now, {String? said}) {
    now.stage.sync?.apply(now.project);
    emit(
      now.copyWith(
        readiness: _readiness.of(now.project),
        said: said,
        clearSaid: said == null,
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
