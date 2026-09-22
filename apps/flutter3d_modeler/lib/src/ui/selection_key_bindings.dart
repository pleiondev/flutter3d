/// The select-all/-none/-invert keyboard bindings — `view-24n`'s own row.
///
/// **A function rather than three more lines inline in `ModelerKeys`**,
/// because `A` is not free to bind unconditionally: `object.add` already
/// claims plain `A` in object mode (`ui-07`'s own tool table), and a
/// modeller where pressing `A` sometimes adds a box and sometimes selects
/// everything, depending on which line of a map happened to be written
/// last, is not one a person can predict from the keyboard alone. Pulled
/// out to its own file so this decision is a pure function `ModelerKeys`
/// calls rather than a widget method with nowhere else to be exercised
/// from.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tools.dart';

/// `A` selects everything, unless [tools] — the current mode's own list —
/// already binds that key to something else, in which case `A` is left for
/// that tool and select-all is not offered at all rather than silently
/// losing to it. `Alt+A` (deselect) and `Ctrl+I` (invert) never collide with
/// a plain-letter tool shortcut, so both are bound unconditionally.
Map<ShortcutActivator, VoidCallback> selectionKeyBindings({
  required List<ModelerTool> tools,
  required VoidCallback onSelectAll,
  required VoidCallback onSelectNone,
  required VoidCallback onInvertSelection,
}) => <ShortcutActivator, VoidCallback>{
  if (!tools.any((tool) => tool.shortcut == LogicalKeyboardKey.keyA))
    const SingleActivator(LogicalKeyboardKey.keyA): onSelectAll,
  const SingleActivator(LogicalKeyboardKey.keyA, alt: true): onSelectNone,
  const SingleActivator(LogicalKeyboardKey.keyI, control: true):
      onInvertSelection,
};
