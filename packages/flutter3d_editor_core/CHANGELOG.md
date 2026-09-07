## 0.2.0

Edits become objects, and the stack learns what one change is.

* **A change to a document is a value now, not only a method call.**
  `EditorCommand` is a sealed hierarchy of ten — `MoveBy`, `Resize`, `AddBrush`,
  `AddLight`, `Place`, `Duplicate`, `Delete`, `SetField`, `Brighten`, `Turn` —
  each with a `says` that reads as a sentence, a `toJson` and a `fromJson`. What
  that buys is everything a method cannot do: the set can be listed, so
  `editorCommandNames` is what a tool server builds a table of tools from; a
  step can be named, so undo says what it took back rather than the word
  "undone"; and a call can arrive over a socket, which is the whole shape of
  driving this editor from outside it.

* **Nothing reverses itself, and that is the decision.** The obvious form for a
  command is a pair — do it, undo it — and there is deliberately no second half.
  Going back is implemented once, in `EditorHistory`, by putting a snapshot of
  the whole document back, for the reason `editing.dart` had already written
  down when snapshots were the only mechanism there was: an undo that
  reconstructs state is an undo with its own bugs. A level is a few hundred
  numbers and a snapshot of one costs nothing worth measuring; an inverse per
  command is ten more places for the way back to disagree with the way there,
  and the disagreement shows up as somebody's brush a quarter of a metre from
  where they left it rather than as a crash.

* **A transaction, because a drag was eating the stack.** Dragging a brush
  across a room is one thing a person did and a hundred changes to the document,
  and recorded singly they filled all sixty-four steps in about a second — so
  the change before the drag, the one anybody would want back, was gone before
  the mouse button came up. `EditorHistory.transaction` takes one snapshot on
  the way in and leaves at most one step on the way out; at most, because a drag
  that never left the grid square it started in is not a change and an undo that
  has to be pressed twice is an undo nobody trusts.

* **The undo stack, and what counts as unsaved, moved to `EditorHistory`.**
  `Editing.undo`, `redo`, `canUndo`, `canRedo`, `isDirty` and `saved` are still
  there and answer the same way; what left is the state behind them, including
  the depth the stack stood at when the file was written. "Is there unsaved
  work" is a comparison between that depth and the current one — undoing back
  past a save has to answer no and redoing forward past it yes again — so it can
  only be made where the stack is, and the dialog that closing a window raises
  hangs on it. `Editing.undoDepth` is now `EditorHistory.undoDepth`, still
  sixty-four.

* **Fourteen tests**, on the round trip through JSON, on a transaction being one
  step however many changes are inside it, on a command that cannot run
  answering false and leaving the document alone, on the sixty-fourth step
  falling off the end, and on a selection surviving an undo that did not remove
  it.

## 0.1.0

The headless half of the editor leaves the application.

* **The document layer is a package, and the reason is that nothing could
  depend on it.** `Editing`, `Handle`, `Picking`, `Placeable`, `Looks`, `OpenKind`,
  `Template` and `scaffold` were eight files in `apps/flutter3d_editor/lib/src`
  that named Flutter nowhere at all. Anything else that wanted them — a
  command-line linter for a level, a tool an agent speaks to, a service that
  validates an uploaded level before a player loads it — had to depend on an
  application, which `no package depends on an application` forbids and which
  pub cannot express in the first place: an application is not published, so
  such a dependency is true only inside this checkout.

* **Plain Dart, and the boundary is checked rather than described.** The eight
  files import `flutter3d_sim` rather than `flutter3d_game`, because every type
  the document is made of — `Level`, `Brush`, `LevelLight`, `EntityDef`,
  `EntityRegistry`, `LevelValidator`, `LevelIssue` — has been in the simulation
  since it stopped needing Flutter. `the simulation names no Flutter` in
  `tool/structure.dart` reads this package's `lib/` and `test/` and fails on the
  first `package:flutter/`, `package:flutter_test/` or `dart:ui`. It is the same
  rule `flutter3d_sim` has carried since its own split, generalised over a list
  of packages rather than copied into a thirty-first — and it keeps its name,
  which two documents and a site page quote.

* **What did not come.** `fly_camera.dart` stayed in the application because it
  reaches `package:flutter3d` for a camera, and `documents.dart` stayed because
  reading a file off a disk is the one thing a headless core has no business
  doing. Four test files came with the code and run under `dart test`; the two
  that hold the shipped templates against the genre packages stayed with the
  assets they read.
