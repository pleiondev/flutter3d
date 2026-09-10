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
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

import 'command.dart';
import 'project.dart';
import 'selection.dart';

/// One entry: what was done, and what the document was before it.
final class HistoryStep {
  const HistoryStep({
    required this.command,
    required this.before,
    required this.selectionBefore,
    this.meshSteps = const <EditMesh, int>{},
  });

  final ModelCommand command;

  /// The project as it was. See the library comment.
  final ModelProject before;

  /// The selection the command was made against, kept so a redo does the same
  /// thing to the same elements even if the pointer has moved on.
  final ProjectSelection selectionBefore;

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
  ModelHistory(this._project, {this.depth = 64, ProjectSelection? selection})
    : _selection = selection ?? ProjectSelection.none,
      _saved = _project;

  /// How many steps are kept.
  ///
  /// Sixty-four rather than unbounded: each step holds a whole project, and
  /// while the shared parts cost nothing, an edit that replaces a two hundred
  /// thousand face mesh does not share and a hundred of those is a gigabyte.
  /// Sixty-four is far past what anybody undoes through and near enough to
  /// nothing in the ordinary case.
  final int depth;

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
  String? run(ModelCommand command) {
    final Outcome outcome = command.apply(_project, selection);
    if (!outcome.ok) return outcome.refused;
    final EditMesh? touched = outcome.meshTouched;
    if (_inTransaction) {
      _firstOfTransaction ??= command;
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
        ),
      );
      // Only a step that a person made clears the redo stack. A redo that ran
      // through here would wipe the very stack it is walking.
      _undone.clear();
      if (_done.length > depth) _done.removeAt(0);
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
  final Map<EditMesh, int> _meshStepsOfTransaction = <EditMesh, int>{};

  /// Runs [body] and records everything it did as one step.
  ///
  /// The step is named after the *first* command, because that is the one the
  /// person started: a drag is `move`, whatever the ninety-nine after it were.
  /// A transaction in which nothing succeeded leaves no step, which is what
  /// makes a drag that never moved anything cost nothing.
  T transaction<T>(T Function() body) {
    if (_inTransaction) {
      // Nesting would need a stack of open steps and a rule about which one a
      // failure unwinds to, for a case nothing has: the interface opens one on
      // a pointer down and closes it on a pointer up.
      throw StateError('a transaction is already open');
    }
    final before = _project;
    final selectionBefore = _selection;
    _inTransaction = true;
    _firstOfTransaction = null;
    _meshStepsOfTransaction.clear();
    try {
      return body();
    } finally {
      final ModelCommand? first = _firstOfTransaction;
      final Map<EditMesh, int> meshSteps = Map<EditMesh, int>.of(
        _meshStepsOfTransaction,
      );
      _inTransaction = false;
      _firstOfTransaction = null;
      _meshStepsOfTransaction.clear();
      if (first != null && !identical(_project, before)) {
        _done.add(
          HistoryStep(
            command: first,
            before: before,
            selectionBefore: selectionBefore,
            meshSteps: meshSteps,
          ),
        );
        _undone.clear();
        if (_done.length > depth) _done.removeAt(0);
      }
    }
  }

  /// Re-runs the command at the top of the stack with [replacement], against
  /// the document as it was before it.
  ///
  /// **The stack does not grow, and that is the whole point.** The card for the
  /// last operation has a slider on it; a person dragging that slider is
  /// adjusting one step, not making sixty. Returns the refusal when the new
  /// arguments are refused — and leaves the old step in place, so the model is
  /// still what it was rather than reverted to before an operation the person
  /// did not ask to undo.
  String? amend(ModelCommand replacement) {
    if (_done.isEmpty) return 'there is nothing to adjust';
    final HistoryStep step = _done.last;
    final Outcome outcome = replacement.apply(
      step.before,
      step.selectionBefore,
    );
    if (!outcome.ok) return outcome.refused;
    _done[_done.length - 1] = HistoryStep(
      command: replacement,
      before: step.before,
      selectionBefore: step.selectionBefore,
    );
    _project = outcome.project!;
    _selection = outcome.selection ?? step.selectionBefore;
    return null;
  }

  /// One step back. False when there is nothing to go back to.
  bool undo() {
    if (_done.isEmpty) return false;
    final HistoryStep step = _done.removeLast();
    _undone.add(
      HistoryStep(
        command: step.command,
        before: _project,
        selectionBefore: _selection,
        meshSteps: step.meshSteps,
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

  /// Every command that has been kept, oldest first — the journal a project
  /// file writes and an agent's transcript reads.
  List<ModelCommand> get journal => <ModelCommand>[
    for (final HistoryStep step in _done) step.command,
  ];
}
