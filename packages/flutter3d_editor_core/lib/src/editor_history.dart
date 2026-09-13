import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'editing.dart';
import 'editor_command.dart';

/// One step back: what the document was, what was done to it, and which state
/// of the document the snapshot is.
///
/// The snapshot is beside the sentence rather than under it, because both
/// answers are wanted at once — a bar says "undo move by 0.25, 0, 0" and then
/// has to put that document back. [state] is the token [EditorHistory] gave
/// that document when it came into being; see [EditorHistory.isDirty].
typedef _Step = ({String says, Map<String, Object?> document, int state});

/// Everything that has been done to a document, and the way back.
///
/// **Whole documents, not reversed commands.** A step is a snapshot of
/// `level.toJson()` taken before the change, and going back is that snapshot
/// read into the document again. [EditorCommand] says at length why the
/// alternative was refused; the short version is the sentence `editing.dart`
/// carried before any of this existed — an undo that reconstructs state is an
/// undo with its own bugs. A level is a few hundred numbers and a snapshot of
/// one costs nothing worth measuring, so the expensive thing here is the only
/// thing that cannot be wrong.
///
/// **It also knows what has been saved**, which looks like two jobs and is one.
/// "Is there unsaved work" is not a flag that a change sets and a save clears:
/// undoing back past a save has to answer no, and redoing forward past it has
/// to answer yes again. So every state the document passes through gets a
/// token of its own, a save remembers the token of the state it wrote, and
/// [isDirty] compares the two.
///
/// **A token, not the depth of the stack.** The depth was the first answer and
/// it was wrong in the ordinary case: save, undo, change something, undo, redo
/// — the stack is back at the depth of the save and the document on screen is
/// a change nobody wrote down. Two states at one depth are two different
/// documents, and only something minted per state can tell them apart. It is
/// the question `ModelHistory` answers by identity, asked of a document that
/// is rebuilt from JSON and so has no identity to ask about.
final class EditorHistory {
  EditorHistory(this.editing);

  /// The document this remembers. It replaces [Editing.level] when it goes back.
  final Editing editing;

  /// How many steps back an editor can go.
  ///
  /// Sixty-four whole documents, which for a level of a few hundred numbers is
  /// a few hundred kilobytes and for a person is further back than anybody
  /// remembers having gone. The oldest falls off the end rather than the newest
  /// being refused: an editor that stops recording after the sixty-fourth
  /// change is an editor whose undo silently stops working halfway through an
  /// afternoon.
  static const int undoDepth = 64;

  final List<_Step> _undo = <_Step>[];

  /// Steps undone, newest last, so [redo] can put one back.
  final List<_Step> _redo = <_Step>[];

  /// Whether there is anything to go back to.
  bool get canUndo => _undo.isNotEmpty;

  /// Whether there is anything to go forward to.
  bool get canRedo => _redo.isNotEmpty;

  /// What going back would take away, or null.
  ///
  /// For a caller that wants to say which change it is about to undo rather
  /// than the word "undone" — the editor's status bar, and anything that shows
  /// a list of what has been done.
  String? get undoSays => _undo.isEmpty ? null : _undo.last.says;

  /// What going forward would put back, or null. Read by the same callers as
  /// [undoSays].
  String? get redoSays => _redo.isEmpty ? null : _redo.last.says;

  /// Runs [command] and remembers the document it changed.
  ///
  /// Answers whatever the command answered, so a caller finds out that resizing
  /// with a light selected did nothing without having to compare the document
  /// with itself. A command that answers false leaves no step, because a step
  /// that puts back what is already there is an undo that appears not to work.
  bool run(EditorCommand command) =>
      transaction(command.says, () => command.apply(editing));

  /// Runs [body] and leaves at most one step behind, whatever it changed.
  ///
  /// **Without this a drag eats the stack.** Dragging a brush across a room is
  /// one thing a person did and a hundred changes to the document, one per
  /// mouse move; recorded singly they fill all sixty-four steps in about a
  /// second, so the change *before* the drag — the one anybody would actually
  /// want back — is gone before the mouse button comes up. One snapshot on the
  /// way in, one step on the way out.
  ///
  /// **At most one**, not exactly one: a body that changed nothing leaves
  /// nothing. A drag that never moved off the grid square it started on is not
  /// a change, and an undo that has to be pressed twice because one of the
  /// presses does nothing visible is an undo nobody trusts.
  ///
  /// Nested transactions belong to the outermost: the snapshot it took is the
  /// state a person means when they say "before all that".
  T transaction<T>(String says, T Function() body) {
    if (_open) return body();
    final before = editing.level.toJson();
    _open = true;
    _touched = false;
    try {
      return body();
    } finally {
      _open = false;
      if (_touched) _push(says, before);
      _touched = false;
    }
  }

  /// Records the document as it is now, before a change [says] describes.
  ///
  /// **Called by [Editing] itself**, from the one line that every method which
  /// changes the document begins with, which is why it is public rather than
  /// private to this file. That is what keeps a bare `editing.nudge(...)`
  /// undoable: a document layer that only recorded when somebody went through
  /// [run] would be a document layer with two kinds of edit in it, one of them
  /// quietly unrecoverable.
  ///
  /// Inside a [transaction] this only notes that something happened; the
  /// snapshot the transaction took on the way in is the one that will be kept.
  void remember(String says) {
    if (_open) {
      _touched = true;
      return;
    }
    _push(says, editing.level.toJson());
  }

  void _push(String says, Map<String, Object?> document) {
    _undo.add((says: says, document: document, state: _state));
    if (_undo.length > undoDepth) _undo.removeAt(0);
    // A new change is a new future. Keeping the old one would let redo put back
    // a document that never followed from what is on screen.
    _redo.clear();
    // The document about to exist has never existed before, so it has never
    // been saved either — whatever depth the stack happens to be at.
    _state = ++_minted;
  }

  /// Whether a transaction is open, and so who owns the next step.
  bool _open = false;

  /// Whether anything asked to be remembered since the transaction began.
  bool _touched = false;

  /// Puts the document back the way it was before the last change.
  void undo() {
    if (_undo.isEmpty) return;
    final step = _undo.removeLast();
    _redo.add((says: step.says, document: editing.level.toJson(), state: _state));
    _state = step.state;
    _restore(step.document);
  }

  /// Puts back the change [undo] took away.
  void redo() {
    if (_redo.isEmpty) return;
    final step = _redo.removeLast();
    _undo.add((says: step.says, document: editing.level.toJson(), state: _state));
    _state = step.state;
    _restore(step.document);
  }

  void _restore(Map<String, Object?> document) {
    editing.level = Level.fromJson(document);
    // **The selection survives if it still points at something.** That is what
    // makes undoing a nudge feel like undoing a nudge rather than like losing
    // the brush — and it is why the selection is an index rather than the
    // object: a reference into a list that has just been replaced is a
    // reference to something no longer in the document. One that points past
    // the end of a list that just got shorter is a crash waiting for the next
    // key, so it is dropped.
    if (editing.piece == null) {
      editing.kind = null;
      editing.selected = null;
    }
  }

  /// Whether anything has been changed since the last save.
  ///
  /// **Not "has anything happened since".** Undoing back to the state that was
  /// last written is a document with nothing unsaved in it, and saying
  /// otherwise means the bar reads "— unsaved" over work that is on the disk,
  /// and that closing the window asks a question it already knows the answer
  /// to.
  bool get isDirty => _state != _savedState;

  /// Says the document has been written, so it stops calling itself unsaved.
  void saved() => _savedState = _state;

  /// The token of the document as it stands, of the one last written, and the
  /// last token handed out. The document a history opens on is token zero and
  /// counts as saved: nothing has been done to it yet.
  int _state = 0;
  int _savedState = 0;
  int _minted = 0;
}
