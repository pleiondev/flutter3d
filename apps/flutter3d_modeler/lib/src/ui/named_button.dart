/// `ui-23`'s own pattern, as a widget rather than as a dozen copies of it —
/// `ux-33`.
///
/// **A tooltip is not a name.** `IconButton.tooltip` lands in
/// `SemanticsNode.tooltip`, which `labeledTapTargetGuideline` does not read
/// and most screen readers announce after the control rather than as it; a
/// button with an icon and a tooltip is announced as "button", with no way to
/// find out which one. The fix is a `Semantics(label:)` above it — and
/// `MergeSemantics` with it, because `IconButton` builds its own inner node
/// that carries the tap action, and a label on a sibling node is a label on
/// something nobody taps.
///
/// It was written out by hand at every call site that had it and missing at
/// five that did not (`skeleton_tree.dart`, `constraints_list.dart`,
/// `morphs_panel.dart`, `texture_graph_panel.dart`, `scene_source_panel.dart`
/// — the review's own list). Three lines repeated is three lines somebody
/// leaves out; a widget is a thing that can be missing in a way a test can
/// see.
library;

import 'package:flutter/material.dart';

/// [child] — an [IconButton], ordinarily — announced as [label].
class NamedButton extends StatelessWidget {
  const NamedButton({super.key, required this.label, required this.child});

  /// What a screen reader says. The words a person would use for the thing,
  /// not the icon: "Remove this light", never "close".
  final String label;

  final Widget child;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(label: label, button: true, child: child),
  );
}
