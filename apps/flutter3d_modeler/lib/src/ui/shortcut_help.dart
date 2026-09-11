/// The in-app shortcut table — `ui-32n`'s own "без второго источника правды
/// для клавиш": read from `toolsFor(ModelerMode)`, the one table `ui-07`
/// already built, rather than a second list of keys kept beside it that
/// could drift.
///
/// **One row per key, not per tool.** Several modes arm the same family of
/// operation on the same letter — `G`/`R`/`S` move, rotate and scale in both
/// object and mesh mode — and a help screen listing `G` twice with the same
/// answer both times is a longer table saying the same thing, not a more
/// complete one. The first mode to use a key names the row; every later
/// mode that reaches for the same key is folded into it rather than
/// appended beside it.
library;

import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'tools.dart';

/// One row of the shortcut table: the key, and what it does.
final class ShortcutEntry {
  const ShortcutEntry({required this.label, required this.shortcut});

  /// The first tool this key was found on, across every mode in
  /// [ModelerMode.values] order.
  final String label;

  final LogicalKeyboardKey shortcut;
}

/// Every shortcut [toolsFor] hands out across every mode, each key exactly
/// once — `ui-32n`'s own worked example.
List<ShortcutEntry> shortcutTable() {
  final seen = <LogicalKeyboardKey>{};
  return <ShortcutEntry>[
    for (final ModelerMode mode in ModelerMode.values)
      for (final ModelerTool tool in toolsFor(mode))
        if (seen.add(tool.shortcut))
          ShortcutEntry(label: tool.label, shortcut: tool.shortcut),
  ];
}
