/// The undo and redo controls in the action bar — `ui-11`'s own tooltip
/// requirement.
///
/// **The tooltip says what would happen, not what the button is.** `undoSays`
/// and `redoSays` already carry the name of the step at the top of each
/// stack; the keyboard shortcut (⌘Z/⇧⌘Z, wired in `ModelerKeys`) works with
/// no tooltip open at all, so this widget's whole job is to put
/// those two sentences somewhere a pointer can find them, and to grey out
/// a button whose stack is empty rather than let it be pressed for nothing.
library;

import 'package:flutter/material.dart';

/// Undo and redo, each with a tooltip saying what it would do.
///
/// Handed its two sentences rather than reading them itself; the caller reads
/// them off the live `ModelHistory` on every `ModelerReady` rebuild, which is
/// every time a command lands or is undone, so there is nowhere for the text
/// to go stale.
class UndoRedoButtons extends StatelessWidget {
  /// The pair, with each button's state and sentence handed in.
  const UndoRedoButtons({
    super.key,
    required this.canUndo,
    required this.canRedo,
    required this.undoSays,
    required this.redoSays,
    required this.onUndo,
    required this.onRedo,
  });

  /// Whether there is a step to undo; the button is greyed out otherwise.
  final bool canUndo;

  /// Whether there is a step to redo; the button is greyed out otherwise.
  final bool canRedo;

  /// What ⌘Z would take back, or null when there is nothing to.
  final String? undoSays;

  /// What ⇧⌘Z would put back, or null when there is nothing to.
  final String? redoSays;

  /// Undo the last step.
  final VoidCallback onUndo;

  /// Redo the last undone step.
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    // `ui-23`'s own pass: `Tooltip.message` becomes a `SemanticsNode.tooltip`,
    // not its `label` — a hover hint most screen readers never read.
    // `MergeSemantics` folds an explicit `Semantics(label:)` down onto
    // `IconButton`'s own inner, actually-tappable node.
    final undoLabel = undoSays == null ? 'nothing to undo' : 'undo $undoSays';
    final redoLabel = redoSays == null ? 'nothing to redo' : 'redo $redoSays';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MergeSemantics(
          child: Semantics(
            label: undoLabel,
            button: true,
            child: Tooltip(
              message: undoLabel,
              child: IconButton(
                onPressed: canUndo ? onUndo : null,
                icon: const Icon(Icons.undo, size: 18),
              ),
            ),
          ),
        ),
        MergeSemantics(
          child: Semantics(
            label: redoLabel,
            button: true,
            child: Tooltip(
              message: redoLabel,
              child: IconButton(
                onPressed: canRedo ? onRedo : null,
                icon: const Icon(Icons.redo, size: 18),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
