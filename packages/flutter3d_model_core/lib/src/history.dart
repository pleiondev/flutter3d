/// The stack of changes, and the way back.
///
/// **It keeps documents, not reversals.** Every other way of doing undo asks
/// each command to know how to take itself back, and every one of those is a
/// second implementation that can disagree with the first — a move that undoes
/// by subtracting is right until somebody clamps the result, and then it is
/// quietly wrong for ever. Keeping the project as it was cannot be wrong about
/// anything. It is affordable because `ModelProject` shares what an edit did
/// not touch: a step over a document of two hundred objects with one moved
/// costs two hundred pointers.
///
/// **A drag is one step, and that is what [transaction] is for.** A hundred
/// pointer moves are a hundred commands and one thing a person did; a history
/// that recorded each would need a hundred presses of ⌘Z to get back, which is
/// the single most complained-about behaviour a tool can have. Inside a
/// transaction the commands run against the live project and only the state
/// before the first of them is kept.
///
/// **[amend] is the operation card, and it is not undo.** A slider on the card
/// for the operation at the top of the stack re-runs that operation with a new
/// argument, against the document as it was before it — so dragging the slider
/// does not grow the stack by one per frame and does not need a transaction
/// wrapped round the widget.
///
/// **[recoveryJournal], once attached, hears every [run]/[amend]/transaction
/// through this door, regardless of who is calling it.** `tut-15`'s own fix:
/// an `--mcp-port` session binds a `ModelSession` over the very
/// `ModelHistory` a person already has open (`mcp_bootstrap_io.dart`), so
/// `ModelSession.run` and a person's own `ModelerCubit.run` (`now.history
/// .run(command)`, no author named) both end up calling the [run] below —
/// recording here rather than leaving each caller to record to a journal of
/// its own is what makes a session's own recovery file agree with every step
/// actually taken on the shared document, whoever took it.
library;

import 'dart:async';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

import 'command.dart';
import 'command_journal.dart';
import 'project.dart';
import 'selection.dart';

/// Who made a [HistoryStep] — `mcp-10n`'s own reason [HistoryStep] names one
/// at all: an agent's own [ModelHistory.undo] should not reach past a
/// person's own step and take back work nobody asked it to.
enum StepAuthor { person, agent }

/// One entry: what was done, and what the document was before it.
final class HistoryStep {
  const HistoryStep({
    required this.command,
    required this.before,
    required this.selectionBefore,
    this.meshSteps = const <EditMesh, int>{},
    this.author = StepAuthor.person,
  });

  final ModelCommand command;

  /// The project as it was. See the library comment.
  final ModelProject before;

  /// The selection the command was made against, kept so a redo does the same
  /// thing to the same elements even if the pointer has moved on.
  final ProjectSelection selectionBefore;

  /// Who made this step — a person at the app, or an agent over MCP.
  /// Defaults to [StepAuthor.person] because that is every call site this
  /// class has ever had until `ModelSession` (`flutter3d_model_mcp`) started
  /// naming its own steps [StepAuthor.agent] explicitly; a step nobody names
  /// an author for is one a human made, not an agent whose own undo needs
  /// watching.
  final StepAuthor author;

  /// How many journal steps each mesh took in this history step.
  ///
  /// **The one thing the kept document cannot answer.** A mesh is a flat array
  /// with a journal rather than a value with old versions in it — `p0-05`
  /// measured both and the journal costs two per cent of a copy where chunks
  /// cost a hundred — so rolling a mesh back is `EditMesh.undo`, not swapping a
  /// pointer. A transaction can touch more than one mesh and can take more than
  /// one step on each, which is why this is a count per mesh rather than a
  /// flag.
  final Map<EditMesh, int> meshSteps;
}

/// A project, the changes made to it, and the way back.
final class ModelHistory {
  ModelHistory(
    this._project, {
    this.depth = 64,
    ProjectSelection? selection,
    this.recoveryJournal,
  }) : _selection = selection ?? ProjectSelection.none,
       _saved = _project;

  /// Rebuilds a history whose undo stack is already known — `doc-31d`'s own
  /// reader, once a file's own `history` section has read [steps] back.
  ///
  /// **No mesh rolling on undo/redo built from this.** Every [HistoryStep]
  /// read from a file already names the real, distinct `EditMesh` for its
  /// own moment — `project_format.dart`'s own dedup means two steps that
  /// happened to leave a mesh untouched already point at the same
  /// instance — so swapping `_project` to `step.before` is the whole of
  /// undo here. [HistoryStep.meshSteps] stays empty for exactly that
  /// reason: it exists for the *live* editing path, where one `EditMesh`
  /// keeps mutating through its own journal rather than being copied each
  /// step, and a file-rebuilt history has already paid that copy's cost by
  /// construction.
  ModelHistory.withSteps(
    this._project,
    List<HistoryStep> steps, {
    this.depth = 64,
    ProjectSelection? selection,
    this.recoveryJournal,
  }) : _selection = selection ?? ProjectSelection.none,
       _saved = _project {
    _done.addAll(steps);
  }

  /// How many steps are kept.
  ///
  /// Sixty-four rather than unbounded: each step holds a whole project, and
  /// while the shared parts cost nothing, an edit that replaces a two hundred
  /// thousand face mesh does not share and a hundred of those is a gigabyte.
  /// Sixty-four is far past what anybody undoes through and near enough to
  /// nothing in the ordinary case.
  final int depth;

  /// A recovery journal every [run]/[amend]/[beginTransaction]/
  /// [endTransaction] call writes to as well, when one is attached — see the
  /// library comment. Not [journal] (that getter is [_done]'s own commands,
  /// oldest first, for `doc-31d`'s own file writer) — a *recovery* journal,
  /// `doc-16`'s `CommandJournal`, JSON Lines rather than a Dart list. Null by
  /// default: a history built for a test, a `CommandJournal.replay` (which
  /// never attaches one to the `ModelHistory` it builds), or a plain desktop
  /// session with no `--mcp-port` bound over it records nothing anywhere
  /// unless a caller asks for that in code.
  ///
  /// A plain mutable field rather than a constructor-only value: a caller
  /// that already holds a live `ModelHistory` — `ModelSession`, given one
  /// built elsewhere — has to be able to attach its own journal to it after
  /// the fact, not only build a fresh history around one.
  CommandJournal? recoveryJournal;

  ModelProject _project;
  ProjectSelection _selection;

  /// The project as of the last save, for [isDirty].
  ModelProject _saved;

  final List<HistoryStep> _done = <HistoryStep>[];
  final List<HistoryStep> _undone = <HistoryStep>[];

  ModelProject get project => _project;

  /// What is selected, filtered to what the project still holds.
  ///
  /// Filtered on the way out rather than cleared on the way in: an object that
  /// an undo brings back comes back selected, which is what a person who
  /// pressed delete by accident expects — see `ProjectSelection.within`.
  ProjectSelection get selection => _selection.within(_project);

  set selection(ProjectSelection to) => _selection = to;

  bool get canUndo => _done.isNotEmpty;
  bool get canRedo => _undone.isNotEmpty;

  /// What ⌘Z would take back, for the menu item, or null.
  String? get undoSays => _done.isEmpty ? null : _done.last.command.says;

  /// What ⇧⌘Z would put back, or null.
  String? get redoSays => _undone.isEmpty ? null : _undone.last.command.says;

  /// Whether anything has changed since [markSaved].
  ///
  /// By identity rather than by comparing documents: two projects that compare
  /// equal after an edit and an undo *are* the same document, and structural
  /// sharing makes `identical` say so without walking anything.
  bool get isDirty => !identical(_saved, _project);

  /// This is the version on disk now.
  void markSaved() => _saved = _project;

  /// Runs [command]. Returns null when it worked and the refusal otherwise.
  ///
  /// A refusal leaves the stack exactly as it was: it is an ordinary answer,
  /// not a step, and a person who pressed extrude with nothing selected has not
  /// done anything to take back.
  ///
  /// [author] is [StepAuthor.person] unless a caller says otherwise —
  /// `ModelSession` (`flutter3d_model_mcp`) is the one caller that ever
  /// passes [StepAuthor.agent], since every command an MCP tool call runs is
  /// one by definition.
  ///
  /// **Records to [recoveryJournal], when one is attached, on every success
  /// — regardless of which door the caller came in through.** `ModelSession
  /// .run` and a plain `now.history.run(command)` from `ModelerCubit` both
  /// call this same method, so attaching a journal here is what lets both a
  /// person's live edit and an agent's own reach the identical recovery file
  /// (`tut-15`), each under the [author] it was actually given.
  String? run(ModelCommand command, {StepAuthor author = StepAuthor.person}) {
    final Outcome outcome = command.apply(_project, selection);
    if (!outcome.ok) return outcome.refused;
    final EditMesh? touched = outcome.meshTouched;
    if (_inTransaction) {
      _firstOfTransaction ??= command;
      _authorOfTransaction ??= author;
      if (touched != null) {
        _meshStepsOfTransaction[touched] =
            (_meshStepsOfTransaction[touched] ?? 0) + 1;
      }
    } else {
      _done.add(
        HistoryStep(
          command: command,
          before: _project,
          selectionBefore: _selection,
          meshSteps: touched == null
              ? const <EditMesh, int>{}
              : <EditMesh, int>{touched: 1},
          author: author,
        ),
      );
      // Only a step that a person made clears the redo stack. A redo that ran
      // through here would wipe the very stack it is walking.
      _undone.clear();
      if (_done.length > depth) _done.removeAt(0);
    }
    if (command.isJournaled) {
      recoveryJournal?.record(command, author: author);
    }
    _project = outcome.project!;
    _selection = outcome.selection ?? _selection;
    return null;
  }

  /// Whether a transaction is open, and the command that opened it.
  ///
  /// Two fields rather than a nullable step, because what a transaction needs
  /// to remember is only the project it started from — which is a local in
  /// [transaction] — and the name to put on the one step it leaves behind.
  bool _inTransaction = false;
  ModelCommand? _firstOfTransaction;
  StepAuthor? _authorOfTransaction;
  final Map<EditMesh, int> _meshStepsOfTransaction = <EditMesh, int>{};

  /// Completed by [endTransaction] and awaited by [whenNotInTransaction] —
  /// `mcp-14n`'s own lock, held by whichever modal transform is mid-drag.
  Completer<void>? _transactionClosed;

  /// Resolves once no transaction is open — immediately, when none is.
  ///
  /// **The whole of `mcp-14n`'s own fix lives in this one `await`,** called
  /// from `flutter3d_model_mcp`'s generic command tool before it runs an
  /// agent's command. [ModelHistory.run] folds a command into whichever
  /// transaction happens to be open when it is called — right, for the
  /// gesture that opened it, wrong for a command that arrives from
  /// somewhere else entirely while a person is mid-drag: it would land
  /// inside a step it never asked to be part of, at whatever intermediate
  /// position the drag has reached that frame, and the picture a person is
  /// watching would disagree with the document an agent just read back.
  ///
  /// **A loop, not a single await, because a drag can end and start again
  /// before this resolves.** Every iteration re-reads [_inTransaction]
  /// after waking, so this only returns at a moment nothing is open — and
  /// because everything here runs on one isolate's one event loop, nothing
  /// can call [beginTransaction] between this returning and the very next
  /// synchronous line the caller runs, which is what lets that caller call
  /// [run] right after `await`ing this with no window between the two.
  Future<void> get whenNotInTransaction async {
    while (_inTransaction) {
      await (_transactionClosed ??= Completer<void>()).future;
    }
  }

  /// Runs [body] and records everything it did as one step.
  T transaction<T>(T Function() body) {
    beginTransaction();
    try {
      return body();
    } finally {
      endTransaction();
    }
  }

  /// Opens a transaction that a later event will close.
  ///
  /// **The pair exists because a drag is not a closure.** A pointer goes down
  /// in one callback and up in another, with sixty frames of moves in between,
  /// and there is no scope that spans them — so [transaction] is written on top
  /// of these two rather than the other way round. A caller that can wrap its
  /// work in a function should use [transaction] and let the `finally` close
  /// it; a caller driven by events cannot.
  void beginTransaction() {
    if (_inTransaction) {
      // Nesting would need a stack of open steps and a rule about which one a
      // failure unwinds to, for a case nothing has: the interface opens one on
      // a pointer down and closes it on a pointer up.
      throw StateError('a transaction is already open');
    }
    _inTransaction = true;
    _firstOfTransaction = null;
    _authorOfTransaction = null;
    _meshStepsOfTransaction.clear();
    _projectBeforeTransaction = _project;
    _selectionBeforeTransaction = _selection;
    recoveryJournal?.beginTransaction();
  }

  /// Closes it, leaving one step for everything that succeeded inside.
  ///
  /// The step is named after the *first* command, because that is the one the
  /// person started: a drag is `move`, whatever the ninety-nine after it were.
  /// A transaction in which nothing succeeded leaves no step, which is what
  /// makes a drag that never moved anything cost nothing.
  void endTransaction() {
    if (!_inTransaction) return;
    final ModelCommand? first = _firstOfTransaction;
    final StepAuthor author = _authorOfTransaction ?? StepAuthor.person;
    final ModelProject before = _projectBeforeTransaction!;
    final ProjectSelection selectionBefore = _selectionBeforeTransaction!;
    final Map<EditMesh, int> meshSteps = Map<EditMesh, int>.of(
      _meshStepsOfTransaction,
    );
    _inTransaction = false;
    _firstOfTransaction = null;
    _authorOfTransaction = null;
    _projectBeforeTransaction = null;
    _selectionBeforeTransaction = null;
    _meshStepsOfTransaction.clear();
    // Whoever is in `whenNotInTransaction`'s loop wakes here — before the
    // early return below, so a drag that moved nothing still releases a
    // command that has been waiting on it.
    _transactionClosed?.complete();
    _transactionClosed = null;
    // Unconditional, matching `beginTransaction`'s own marker: a transaction
    // that ran nothing still closes the bracket it opened on the journal,
    // the same as it always has when a caller wrapped `CommandJournal
    // .transaction` around this by hand.
    recoveryJournal?.endTransaction();
    if (first == null || identical(_project, before)) return;
    _done.add(
      HistoryStep(
        command: first,
        before: before,
        selectionBefore: selectionBefore,
        meshSteps: meshSteps,
        author: author,
      ),
    );
    _undone.clear();
    if (_done.length > depth) _done.removeAt(0);
  }

  ModelProject? _projectBeforeTransaction;
  ProjectSelection? _selectionBeforeTransaction;

  /// Re-runs the command at the top of the stack with [replacement], against
  /// the document as it was before it.
  ///
  /// **The stack does not grow, and that is the whole point.** The card for the
  /// last operation has a slider on it; a person dragging that slider is
  /// adjusting one step, not making sixty. Returns the refusal when the new
  /// arguments are refused — and leaves the old step in place, so the model is
  /// still what it was rather than reverted to before an operation the person
  /// did not ask to undo.
  ///
  /// **A mesh the step edited is rolled back first.** `step.before` is a kept
  /// document, but an `EditMesh` inside it is the same mesh the step edited in
  /// place — so re-running an extrusion against it without rolling its journal
  /// back would extrude a second time on top of the first. The journal goes
  /// back by [HistoryStep.meshSteps], the replacement runs, and the new step
  /// records the mesh it touched, so the next undo moves the geometry with the
  /// document. A refusal rolls the journal forward again: refused commands
  /// abandon their open step rather than pushing one, so the redo is still
  /// there to take.
  ///
  /// **Records to [recoveryJournal], when one is attached, the same way [run]
  /// does** — under the step's own original [HistoryStep.author], since an
  /// amend adjusts a step already on the stack rather than naming a fresh
  /// one; a person dragging the app's own operation-card slider and an agent
  /// calling `ModelSession.amend` both reach this, and both now leave the
  /// adjustment on a shared recovery journal the same way an ordinary edit
  /// does.
  String? amend(ModelCommand replacement) {
    if (_done.isEmpty) return 'there is nothing to adjust';
    final HistoryStep step = _done.last;
    _rollMeshes(step.meshSteps, forward: false);
    final Outcome outcome = replacement.apply(
      step.before,
      step.selectionBefore,
    );
    if (!outcome.ok) {
      _rollMeshes(step.meshSteps, forward: true);
      return outcome.refused;
    }
    final EditMesh? touched = outcome.meshTouched;
    _done[_done.length - 1] = HistoryStep(
      command: replacement,
      before: step.before,
      selectionBefore: step.selectionBefore,
      meshSteps: touched == null
          ? const <EditMesh, int>{}
          : <EditMesh, int>{touched: 1},
      author: step.author,
    );
    // A different result is a different future, the same rule [run] keeps: a
    // redo recorded against the old one would put back a document that no
    // longer follows from this one, and its mesh steps are gone from the
    // journal the moment the replacement wrote.
    _undone.clear();
    if (replacement.isJournaled) {
      recoveryJournal?.amend(replacement, author: step.author);
    }
    _project = outcome.project!;
    _selection = outcome.selection ?? step.selectionBefore;
    return null;
  }

  /// Who made the step [undo] would take back, or null when there is none.
  ///
  /// `mcp-10n`'s own reason to ask before calling [undo]: an agent's own
  /// undo has to know whose the top step is *before* deciding whether to
  /// take it — [undo]'s own `onlyIfAuthoredBy` refuses silently (`false`),
  /// and a caller that wants the clear sentence the row's acceptance asks
  /// for reads this first to say whose step it actually was.
  StepAuthor? get topStepAuthor => _done.isEmpty ? null : _done.last.author;

  /// One step back. False when there is nothing to go back to, or when
  /// [onlyIfAuthoredBy] is given and does not match [topStepAuthor] —
  /// `mcp-10n`'s own rule that an agent's undo does not reach past a
  /// person's own step. A person's own ⌘Z passes nothing here and undoes
  /// whichever step is on top regardless of who made it, the row's own
  /// second acceptance line.
  bool undo({StepAuthor? onlyIfAuthoredBy}) {
    if (_done.isEmpty) return false;
    if (onlyIfAuthoredBy != null && _done.last.author != onlyIfAuthoredBy) {
      return false;
    }
    final HistoryStep step = _done.removeLast();
    _undone.add(
      HistoryStep(
        command: step.command,
        before: _project,
        selectionBefore: _selection,
        meshSteps: step.meshSteps,
        author: step.author,
      ),
    );
    _project = step.before;
    _selection = step.selectionBefore;
    _rollMeshes(step.meshSteps, forward: false);
    return true;
  }

  /// One step forward.
  bool redo() {
    if (_undone.isEmpty) return false;
    final HistoryStep step = _undone.removeLast();
    _done.add(
      HistoryStep(
        command: step.command,
        before: _project,
        selectionBefore: _selection,
        meshSteps: step.meshSteps,
        author: step.author,
      ),
    );
    _project = step.before;
    _selection = step.selectionBefore;
    _rollMeshes(step.meshSteps, forward: true);
    return true;
  }

  /// Moves each mesh's own journal by the number of steps it took.
  ///
  /// The document and the meshes have to move together or not at all: a project
  /// put back to before a loop cut, holding a mesh that still has the cut in
  /// it, is a document that disagrees with itself and draws geometry no step of
  /// history describes.
  void _rollMeshes(Map<EditMesh, int> steps, {required bool forward}) {
    for (final MapEntry<EditMesh, int> each in steps.entries) {
      for (var i = 0; i < each.value; i++) {
        if (forward) {
          each.key.redo();
        } else {
          each.key.undo();
        }
      }
    }
  }

  /// Forgets what a redo would put back.
  ///
  /// **For the one caller that undoes a step it made itself.** A transform that
  /// is cancelled with Escape closes its transaction, takes the step back and
  /// wants it gone — leaving it on the redo stack would offer ⇧⌘Z for a
  /// transform the person explicitly threw away, and doing it a second time
  /// would apply it. Nothing else should call this: an ordinary undo keeps its
  /// redo, which is the whole of what undo is for.
  void dropRedo() => _undone.clear();

  /// Every command that has been kept, oldest first — the journal a project
  /// file writes and an agent's transcript reads.
  List<ModelCommand> get journal => <ModelCommand>[
    for (final HistoryStep step in _done) step.command,
  ];

  /// The undo stack itself, oldest first — `doc-31d`'s own writer reads this
  /// to put a project's history in the file beside it. Redo is not here:
  /// [_undone] is what a person has already taken back, and a save keeps
  /// what happened, not what somebody is one ⇧⌘Z away from doing again.
  List<HistoryStep> get steps => List<HistoryStep>.unmodifiable(_done);

  /// Journal steps an open transaction has taken on each mesh so far, which no
  /// entry of [steps] accounts for yet — empty when none is open.
  ///
  /// `writeProject` reads this before [steps]: a save that lands mid-drag has
  /// to roll the drag's own mesh steps back before the newest kept step's
  /// `before` is the geometry it names.
  Map<EditMesh, int> get openMeshSteps => _inTransaction
      ? Map<EditMesh, int>.unmodifiable(_meshStepsOfTransaction)
      : const <EditMesh, int>{};
}
