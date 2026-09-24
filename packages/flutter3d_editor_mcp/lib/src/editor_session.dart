import 'dart:io';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart'
    show Answer, PictureAnswer;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'level_view.dart';

// What a tool call did, and the sentence to say about it — the one `Answer`
// every server here shares, and the `PictureAnswer` that carries a PNG
// beside it. A refusal is an answer, not an exception: `EditorCommand.apply`
// already decided that.
export 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart'
    show Answer, PictureAnswer;

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

  /// Where a picture is taken from: [from] and [at] where the call named
  /// them, the level's default view for whichever it left out. Null for a
  /// level with nothing in it to look at.
  LevelCamera? _camera(Vector3? from, Vector3? at) {
    final fallback = LevelView.defaultCamera(editing.level);
    if (fallback == null) return null;
    return (from: from ?? fallback.from, at: at ?? fallback.at);
  }

  /// A picture of the level from [from] looking at [at].
  Future<PictureAnswer> screenshot(Vector3? from, Vector3? at) async {
    final camera = _camera(from, at);
    if (camera == null) {
      return (did: false, says: 'the level is empty', png: null);
    }
    final png = await LevelView.of(editing.level).picture(camera);
    return (
      did: true,
      says:
          'the level from ${_place(camera.from)} looking at '
          '${_place(camera.at)}, ${LevelView.width}×${LevelView.height}',
      png: png,
    );
  }

  /// What the camera from [from] looking at [at] sees, one line per brush,
  /// light and entity.
  ///
  /// **Answered from the frame's own object ids**, not from boxes against a
  /// ray: the renderer draws the level once more with every draw's number in
  /// place of its colour (`Renderer.captureObjectIds`), so a pixel counted as
  /// a wall's is a pixel the wall was drawn at, after the depth test. The
  /// level is built one draw per brush for this, so a pixel names a brush and
  /// not a material.
  Future<Answer> report(Vector3? from, Vector3? at) async {
    final camera = _camera(from, at);
    if (camera == null) return (did: false, says: 'the level is empty');
    final rows = await LevelView.of(editing.level).report(camera);
    final headline =
        'from ${_place(camera.from)} looking at ${_place(camera.at)}, '
        '${LevelView.width}×${LevelView.height}:';
    return (
      did: true,
      says: <String>[headline, for (final row in rows) row.says].join('\n'),
    );
  }

  /// Fewer lights, judged by the pictures they make from [views] — from the
  /// spawn when none are given — and applied as one step of undo unless
  /// [apply] is false.
  ///
  /// The picture is the new set's, from the first view; the sentence carries
  /// the moves and the numbers, so an agent can judge the change before
  /// keeping it and undo it after.
  PictureAnswer optimizeLights({List<LightView>? views, bool apply = true}) {
    final level = editing.level;
    if (level.lights.isEmpty) {
      return (did: false, says: 'the level has no lights', png: null);
    }
    final seen = views ?? defaultLightViews(level);
    if (seen.isEmpty) {
      return (
        did: false,
        says: 'no view to judge the lights from — name one, or add a spawn',
        png: null,
      );
    }
    final plan = const LightOptimizer().optimize(level, views: seen);
    final said = <String>[
      plan.says,
      for (final move in plan.moves) '  $move',
    ].join('\n');
    if (!plan.changes) {
      return (did: false, says: 'nothing to gain: $said', png: plan.pngs.after);
    }
    if (apply) editing.history.run(SetLights(plan.after, why: plan.says));
    return (
      did: apply,
      says: apply
          ? '$said\n(undo puts the old lights back)'
          : 'proposed: $said',
      png: plan.pngs.after,
    );
  }

  static String _place(Vector3 it) => <double>[it.x, it.y, it.z]
      .map(
        (double v) => v == v.roundToDouble()
            ? v.toStringAsFixed(0)
            : v.toStringAsFixed(2),
      )
      .join(', ');

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
