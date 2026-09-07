import 'dart:io';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// What a tool call actually did, and the sentence to say about it.
///
/// **A refusal is an answer here, not an exception.** `EditorCommand.apply`
/// already decided that: resizing with a light selected is a question whose
/// answer is no, and a caller that has to catch something to find out is a
/// caller that will eventually catch it in the wrong place. The protocol layer
/// turns a [did] of false into a tool result marked as an error, which is how
/// an agent is told to try something else rather than told nothing.
typedef Answer = ({bool did, String says});

/// One level document, open, with the editor's own verbs on it.
///
/// **The half with a disk in it, and the reason it is a separate file from the
/// server.** `flutter3d_editor_core` deliberately reads no disk — "that half is
/// where a crash loses somebody's work and where a platform gets an opinion" —
/// and the protocol layer deliberately knows nothing about levels. What is left
/// in the middle is this: open a path, run the commands, write it back, and say
/// in one sentence what happened.
///
/// One per process, because the document is the state. There is no `open` tool
/// and no second document: an agent that could swap the level underneath itself
/// would have an undo stack describing a file it is no longer editing, and the
/// sixty-four snapshots behind it would quietly become sixty-four snapshots of
/// somebody else's work.
final class EditorSession {
  EditorSession(this.editing);

  /// Reads the document at [path].
  ///
  /// The path as typed, resolved by the shell that started this process rather
  /// than searched for. The editor application searches — its bundle's working
  /// directory is `/` and not where anybody typed the command — and a server
  /// started by an agent host has no such excuse: it inherits a working
  /// directory that somebody chose.
  factory EditorSession.open(String path) =>
      EditorSession(Editing.parse(File(path).readAsStringSync(), path: path));

  final Editing editing;

  /// What this editor writes into `generatedBy` when it takes ownership of a
  /// copy. The application writes `apps/flutter3d_editor` for the same reason:
  /// a document should name what last wrote it.
  static const String author = 'packages/flutter3d_editor_mcp';

  /// Everything in the document, one line each.
  ///
  /// **The tool an agent has to call first, and the one the plan was missing.**
  /// Every other verb here works on "the selection", and a selection is a kind
  /// and an index — which a program with no screen has no way to guess. Without
  /// this, driving the editor means moving the third brush without ever being
  /// able to find out that there is a third brush.
  String listing() {
    final rows = contentsOf(editing.level);
    if (rows.isEmpty) return 'the level is empty';
    return <String>[
      for (final row in rows) row.says,
      '',
      'selection: $selection',
    ].join('\n');
  }

  /// What is selected, said to something that has no mouse.
  ///
  /// `Editing.says` answers "nothing selected — click something", which is the
  /// right sentence for the application it was written for and the wrong one
  /// here: an agent reading it looks for a way to click. Only the empty case
  /// differs, so a selection reads identically in both editors.
  String get selection =>
      editing.piece == null ? 'nothing selected — call select' : editing.says;

  /// Picks one of the rows [listing] gave, or nothing when [index] is null.
  ///
  /// Answers false when there is no such row, rather than quietly selecting
  /// nothing: "brush 40" in a level with six brushes is a mistake worth
  /// hearing about, and an editor that silently deselected would answer the
  /// next four commands with "nothing is selected" and never say why.
  Answer select(Piece? kind, int? index) {
    editing.select(kind, index);
    if (index != null && editing.piece == null) {
      return (did: false, says: 'there is no ${kind?.name} $index — call list');
    }
    return (did: true, says: selection);
  }

  /// Runs one editor command through the history, so it can be undone.
  ///
  /// Through [EditorHistory.run] rather than through the command's own `apply`,
  /// because that is where a step gets its name: an agent that undoes gets told
  /// "move by 0.25, 0, 0" rather than the word "undone".
  Answer run(EditorCommand command) {
    final did = editing.history.run(command);
    return (
      did: did,
      says: did
          ? '${command.says} — $selection'
          : 'nothing did ${command.says}: $selection',
    );
  }

  /// Puts the document back the way it was before the last change.
  Answer undo() {
    final says = editing.history.undoSays;
    if (says == null) return (did: false, says: 'nothing to undo');
    editing.undo();
    return (did: true, says: 'undid $says — $selection');
  }

  /// Puts back the change [undo] took away.
  Answer redo() {
    final says = editing.history.redoSays;
    if (says == null) return (did: false, says: 'nothing to redo');
    editing.redo();
    return (did: true, says: 'redid $says — $selection');
  }

  /// What is wrong with the level, as the game would see it.
  ///
  /// **Against the document's own vocabulary, which is the only one this
  /// process has.** `vocabularyOf` builds a registry out of whatever the level
  /// happens to name, so nothing here reports "unknown entity type: torch" for
  /// a game full of torches — the editor has no vocabulary and must not invent
  /// one, and a genre's real registry lives in a genre package that a tool is
  /// forbidden to name. What is left is every check that is honestly about the
  /// document: geometry that overlaps, a brush naming a material the level does
  /// not declare, a light with no reach, a name two entities both answer to.
  ///
  /// That is exactly the class of mistake an agent makes, because it edits by
  /// writing words rather than by clicking on something that is already there.
  String validate() {
    final issues = editing.issuesFor(vocabularyOf(editing.level));
    if (issues.isEmpty) return 'no issues';
    final errors = issues.where((LevelIssue it) => it.isError).length;
    final headline =
        '${issues.length} issue${issues.length == 1 ? '' : 's'}, '
        '$errors of them fatal';
    return <String>[
      headline,
      for (final issue in issues) '  $issue',
    ].join('\n');
  }

  /// Writes the document, to [path] or over the one it came from.
  ///
  /// **The refusal is half of what this tool is for.** A document that says
  /// `generatedBy` belongs to the program that generated it: editing
  /// `level.first.json` by hand and saving it produces a file that looks edited
  /// right up until somebody runs `make_templates.py` again, at which point the
  /// work is gone and nothing ever said so. So a generated document may be
  /// opened, changed and saved *somewhere else*, and the copy claims itself —
  /// a file saved beside the original still naming the generator is a file that
  /// invites somebody to regenerate it.
  Answer save(String? path) {
    final elsewhere = path != null && path != editing.path;
    if (!elsewhere && !editing.mayOverwrite) {
      return (
        did: false,
        says:
            '${editing.path} was written by ${editing.generatedBy} and will '
            'not be overwritten — save to another path and the copy takes '
            'ownership of itself',
      );
    }
    final to = path ?? editing.path;
    File(
      to,
    ).writeAsStringSync(editing.write(claiming: elsewhere ? author : null));
    editing.saved();
    return (did: true, says: 'written to $to');
  }
}
