## 0.7.0

* **`scaffold` writes a project against the packages that exist now.** The
  pubspec it generates names `flutter3d`, `flutter3d_game`, `flutter3d_sim`,
  `flutter3d_app` and `flutter3d_audio` at `^0.7.0`. 0.6.0 wrote
  `flutter3d_bridge` and `flutter3d_session` into it, which are discontinued
  as of this release, and did not name `flutter3d_sim`, which
  `flutter3d_game` no longer re-exports. A project scaffolded by 0.6.0 keeps
  resolving against 0.6.0; `doc/boundary-0.7.0.md` lists which import lines
  move when it is brought up.
* **`isDirty` compares documents, not depths.** After an undo or a redo it was
  whether the undo stack's length differed from its length at the last
  `saved()`. Save, undo one step, make a different edit, undo that and redo
  it: the stack is as deep as it was at the save, and 0.6.0 read clean over a
  document that was never written. Every new document now gets a token, undo
  and redo carry theirs with them, and `isDirty` is whether the current token
  is the saved one. Undoing back to the saved document still reads clean.
* **A `.fmat` is edited through a gate, and the gate is here.**
  `materialWith(document, key, value)` returns the `MaterialDocument` with one
  field changed, or null when the result is not a file `readFmat` takes as
  written: the value does not fit the hint's shape, reading it back warns
  about something new, or the value comes back different. A value outside a
  range hint's ends is not refused, because a hint describes a control and
  does not constrain the reader. `materialDocumentFields` and
  `materialDocumentHint` came with it. They were private to the model editor's
  material panel and could move once `MaterialDocument` was in a plain Dart
  library, so `flutter3d_core` `^0.7.0` is a dependency now, for
  `package:flutter3d_core/formats.dart`.
* **What a lesson's step panel computes, without the panel.** `orderedSteps`,
  `mergedOffsets`, `movedStep`, `freshName` and `indexOfNamed` produce the
  values `Place` and `SetField` are handed for an `edu_sequence` and its
  `edu_step`s; none of them is a new `EditorCommand`. `bindingsInLevel` returns
  every binding an `edu_step` declares, keyed by target, as `ActiveBinding`s,
  which is what an inspector needs to know before it draws a property as
  read-only because a data source will overwrite it.
* Still plain Dart. The floor on `flutter3d_sim` is `^0.7.0`.

## 0.6.0

**The first release. It takes the set's number rather than a first number of its
own**, because the whole workspace goes out together and a document layer
resolved against a different `flutter3d_sim` than the editor above it would be
reading a level format nobody built it against. What follows is what this
package is, not what changed in it: the two versions it wore inside the
repository were never uploaded.

* **The headless half of a level editor, and the reason it is a package is that
  nothing could depend on it.** `Editing`, `Handle`, `Picking`, `Placeable`,
  `Looks`, `OpenKind`, `Template` and `scaffold` were files in an application
  that named Flutter nowhere at all. Anything else that wanted them — a
  command-line linter for a level, a tool an agent speaks to, a service that
  validates an uploaded level before a player loads it — had to depend on an
  application, which pub cannot express and this repository's own rules forbid.
* **Plain Dart, and the boundary is checked rather than described.** Every type
  the document is made of — `Level`, `Brush`, `LevelLight`, `EntityDef`,
  `EntityRegistry`, `LevelValidator`, `LevelIssue` — comes from `flutter3d_sim`,
  which stopped needing Flutter when it was split out. A rule in
  `tool/structure.dart` reads this package's `lib/` and `test/` and fails on the
  first `package:flutter/`, `package:flutter_test/` or `dart:ui`.
* **A change to a document is a value, not only a method call.** `EditorCommand`
  is a sealed hierarchy of ten — `MoveBy`, `Resize`, `AddBrush`, `AddLight`,
  `Place`, `Duplicate`, `Delete`, `SetField`, `Brighten`, `Turn` — each with a
  `says` that reads as a sentence, a `toJson` and a `fromJson`. That buys what a
  method cannot: the set can be listed, so a tool server builds its table from
  `editorCommandNames`; a step can be named, so undo says what it took back
  rather than the word "undone"; and a call can arrive over a socket, which is
  the whole shape of driving this editor from outside it.
* **Nothing reverses itself, and that is the decision.** The obvious form for a
  command is a pair — do it, undo it — and there is deliberately no second half.
  Going back is implemented once, in `EditorHistory`, by putting a snapshot of
  the whole document back: a level is a few hundred numbers and a snapshot costs
  nothing worth measuring, while an inverse per command is ten more places for
  the way back to disagree with the way there. The disagreement shows up as
  somebody's brush a quarter of a metre from where they left it rather than as a
  crash, which is why it is not a bug anybody would find.
* **A transaction, because a drag was eating the stack.** Dragging a brush across
  a room is one thing a person did and a hundred changes to the document;
  recorded singly they filled all sixty-four steps in about a second, so the
  change anybody would actually want back was gone before the mouse button came
  up. `EditorHistory.transaction` takes one snapshot on the way in and leaves at
  most one step on the way out — at most, because a drag that never left the
  grid square it started in is not a change, and an undo that has to be pressed
  twice is an undo nobody trusts.
* **"Is there unsaved work" is answered where the stack is.** `EditorHistory`
  holds the undo stack, the redo stack and the depth the stack stood at when the
  file was written; undoing back past a save answers no and redoing forward past
  it answers yes again. `Editing.undo`, `redo`, `canUndo`, `canRedo`, `isDirty`
  and `saved` still stand in front of it and answer the same way.
* **A scaffolded project names hosted versions, and they are this release's.**
  `pubspecFor` writes `^0.6.0` rather than a path into the checkout, so a new
  game travels off the machine that made it. The floors move with the set for a
  reason worth stating: a caret below 1.0.0 stops at the minor, so a seed left
  at an old line hands its author the engine of that month — it compiles, it
  runs, and the first news of how old it is comes from a name in a tutorial that
  is not there.
* **What is deliberately not here.** A camera, because that reaches for a
  renderer, and reading a file off a disk, because a headless core has no
  business doing it. Both stayed in the application this package left.

