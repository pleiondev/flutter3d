/// The undo and redo controls in the action bar — `ui-11`'s own tooltip
/// requirement.
///
/// **The tooltip says what would happen, not what the button is.** `undoSays`
/// and `redoSays` already carry the name of the step at the top of each
/// stack; the keyboard shortcut (⌘Z/⇧⌘Z, wired in `main.dart`'s own `_Keys`)
/// works with no tooltip open at all, so this widget's whole job is to put
/// those two sentences somewhere a pointer can find them, and to grey out
/// a button whose stack is empty rather than let it be pressed for nothing.
library;

import 'package:flutter/material.dart';

/// Reads its two sentences straight from a live [ModelHistory] rather than a
/// copy: this is built fresh on every `ModelerReady` rebuild, which is every
/// time a command lands or is undone, so there is nowhere for the text to go
/// stale.
class UndoRedoButtons extends StatelessWidget {
  const UndoRedoButtons({
    super.key,
    required this.canUndo,
    required this.canRedo,
    required this.undoSays,
    required this.redoSays,
    required this.onUndo,
    required this.onRedo,
  });

  final bool canUndo;
  final bool canRedo;

  /// What ⌘Z would take back, or null when there is nothing to.
  final String? undoSays;

  /// What ⇧⌘Z would put back, or null when there is nothing to.
  final String? redoSays;

  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Tooltip(
        message: undoSays == null ? 'nothing to undo' : 'undo $undoSays',
        child: IconButton(
          onPressed: canUndo ? onUndo : null,
          icon: const Icon(Icons.undo, size: 18),
        ),
      ),
      Tooltip(
        message: redoSays == null ? 'nothing to redo' : 'redo $redoSays',
        child: IconButton(
          onPressed: canRedo ? onRedo : null,
          icon: const Icon(Icons.redo, size: 18),
        ),
      ),
    ],
  );
}
