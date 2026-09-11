/// `shortcutTable`: `ui-32n`'s own help-screen table, checked against
/// `toolsFor` rather than against a second, hand-typed list of keys.
///
///     flutter test test/shortcut_help_test.dart
library;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter3d_modeler/src/ui/shortcut_help.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every shortcut toolsFor hands out, across every mode, appears in '
      'the table — the row\'s own worked example', () {
    final fromTools = <LogicalKeyboardKey>{
      for (final ModelerMode mode in ModelerMode.values)
        for (final ModelerTool tool in toolsFor(mode)) tool.shortcut,
    };
    final fromTable = <LogicalKeyboardKey>{
      for (final ShortcutEntry entry in shortcutTable()) entry.shortcut,
    };

    expect(fromTable, fromTools);
  });

  test('no shortcut appears twice — the row\'s own "ровно раз"', () {
    final shortcuts = <LogicalKeyboardKey>[
      for (final ShortcutEntry entry in shortcutTable()) entry.shortcut,
    ];

    expect(shortcuts.toSet(), hasLength(shortcuts.length));
  });

  test('a key shared by object and mesh mode is one row, labelled from '
      'whichever mode came first', () {
    // Both `object.select` and `mesh.select` arm on Q — the same family of
    // operation, so the table names it once.
    final objectSelect = toolsFor(
      ModelerMode.object,
    ).firstWhere((ModelerTool t) => t.id == 'object.select');
    final row = shortcutTable().firstWhere(
      (ShortcutEntry e) => e.shortcut == objectSelect.shortcut,
    );

    expect(row.label, objectSelect.label);
  });

  test('a mode with nothing built yet contributes nothing new', () {
    // ModelerMode.sculpt is phase 4 and toolsFor answers an empty list for
    // it; the table still has to build without throwing.
    expect(() => shortcutTable(), returnsNormally);
  });
}
