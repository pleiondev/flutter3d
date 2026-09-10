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

import 'command.dart';
import 'project.dart';
import 'selection.dart';

/// One entry: what was done, and what the document was before it.
final class HistoryStep {
  const HistoryStep({
    required this.command,
    required this.before,
    required this.selectionBefore,
  });

  final ModelCommand command;

  /// The project as it was. See the library comment.
  final ModelProject before;

  /// The selection the command was made against, kept so a redo does the same
  /// thing to the same elements even if the pointer has moved on.
  final ProjectSelection selectionBefore;
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
    if (_inTransaction) {
      _firstOfTransaction ??= command;
    } else {
      _done.add(
        HistoryStep(
          command: command,
          before: _project,
          selectionBefore: _selection,
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
    try {
      return body();
    } finally {
      final ModelCommand? first = _firstOfTransaction;
      _inTransaction = false;
      _firstOfTransaction = null;
      if (first != null && !identical(_project, before)) {
        _done.add(
          HistoryStep(
            command: first,
            before: before,
            selectionBefore: selectionBefore,
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
      ),
    );
    _project = step.before;
    _selection = step.selectionBefore;
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
      ),
    );
    _project = step.before;
    _selection = step.selectionBefore;
    return true;
  }

  /// Every command that has been kept, oldest first — the journal a project
  /// file writes and an agent's transcript reads.
  List<ModelCommand> get journal => <ModelCommand>[
    for (final HistoryStep step in _done) step.command,
  ];
}
