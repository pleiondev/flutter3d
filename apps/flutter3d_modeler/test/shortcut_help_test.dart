/// `shortcutTable`: the help screen's own rows, read from the live keymap
/// rather than from a second, hand-typed list of keys.
///
///     flutter test test/shortcut_help_test.dart
///
/// **`ux-10` widened what this table is for.** It used to answer "which tool
/// is on which letter", from `toolsFor` alone. The review found that this is
/// not what somebody opens a help screen to ask: they want to know how to
/// turn the model, how to save, and how to select everything — none of which
/// were on it, two of which were not bound to anything at all.
library;

import 'package:flutter3d_modeler/src/settings.dart';
import 'package:flutter3d_modeler/src/ui/keymap.dart';
import 'package:flutter3d_modeler/src/ui/shortcut_help.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

List<ShortcutEntry> tableFor(KeymapPreset preset) =>
    shortcutTable(keymapFor(preset, apple: true));

void main() {
  test('every tool the rail arms is on the table, whichever preset', () {
    for (final KeymapPreset preset in KeymapPreset.values) {
      final Set<String> labels = <String>{
        for (final ShortcutEntry entry in tableFor(preset)) entry.label,
      };
      for (final ModelerMode mode in ModelerMode.values) {
        for (final ModelerTool tool in toolsFor(mode)) {
          // Mutation: build the table from `ModelerTool.shortcut` again. It
          // then lists the default keys under every preset, so a person who
          // changed preset reads a screen about somebody else's keyboard.
          expect(
            labels,
            contains(tool.label),
            reason: '${tool.label} is missing under ${preset.id}',
          );
        }
      }
    }
  });

  test('no row is listed twice, and two meanings of one key both are', () {
    for (final KeymapPreset preset in KeymapPreset.values) {
      final List<String> rows = <String>[
        for (final ShortcutEntry entry in tableFor(preset))
          if (entry.section == ShortcutSection.tools)
            '${entry.keys}|${entry.label}',
      ];

      // The original "ровно раз": `G` moves in both object and mesh mode,
      // which is one answer given twice and belongs on one row.
      expect(rows.toSet(), hasLength(rows.length));
    }

    // And the correction `ux-10` made to it. `B` is "bake to mesh" in object
    // mode and "bevel" in mesh mode — two answers, and folding on the key
    // alone kept only the first, so the help screen never mentioned bevel.
    final Set<String> labels = <String>{
      for (final ShortcutEntry entry in tableFor(KeymapPreset.standard))
        entry.label,
    };
    expect(labels, containsAll(<String>['Bevel', 'Convert to a mesh']));
  });

  test('the three sections the review asked for are all there', () {
    final List<ShortcutEntry> table = tableFor(KeymapPreset.standard);
    Iterable<ShortcutEntry> inSection(ShortcutSection section) =>
        table.where((ShortcutEntry it) => it.section == section);

    // "Shortcut help doesn't teach the camera or the application" — the
    // review's own §3.2. Mutation: drop the camera rows, which are the ones
    // that are not keyboard bindings at all and were therefore the easiest
    // to leave out; the first question anybody asks goes unanswered again.
    expect(inSection(ShortcutSection.camera), isNotEmpty);
    expect(inSection(ShortcutSection.application), isNotEmpty);
    expect(inSection(ShortcutSection.selection), isNotEmpty);
    expect(inSection(ShortcutSection.tools), isNotEmpty);
  });

  test('the camera section follows the navigation scheme', () {
    final Keymap keymap = keymapFor(KeymapPreset.standard, apple: true);
    String orbitRow(NavigationScheme scheme) => shortcutTable(
      keymap,
      navigation: scheme,
    ).firstWhere((ShortcutEntry it) => it.label == 'Orbit').keys;

    // Two schemes, two answers. Mutation: write one sentence for both, and
    // half the people reading it are told to press a button that does
    // something else.
    expect(
      orbitRow(NavigationScheme.middleMouseOrbit),
      isNot(orbitRow(NavigationScheme.leftDragOrbit)),
    );
    expect(orbitRow(NavigationScheme.leftDragOrbit), contains('Left button'));
  });

  test('a key is written the way a person reads it', () {
    final List<ShortcutEntry> table = tableFor(KeymapPreset.standard);
    String rowFor(String label) =>
        table.firstWhere((ShortcutEntry it) => it.label == label).keys;

    // Mutation: print `LogicalKeyboardKey.keyLabel` straight, which is what
    // this did. Save reads "S", delete reads "Delete" but loses Backspace,
    // and every combination loses its modifier entirely.
    expect(rowFor('Save'), '⌘S');
    expect(rowFor('Delete'), 'Delete or Backspace');
    expect(rowFor('Object and mesh'), 'Tab');
  });

  test('a mode with nothing built yet contributes nothing new', () {
    // `ModelerMode.sculpt` is phase 4 and `toolsFor` answers empty for it;
    // the table still has to build without throwing.
    expect(() => tableFor(KeymapPreset.standard), returnsNormally);
  });
}
