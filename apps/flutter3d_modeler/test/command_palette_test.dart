/// `ux-25`'s own palette: what it lists, what it says about the entries that
/// cannot be run from here, and what typing finds.
///
///     flutter test test/command_palette_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart'
    show ProjectSelection, SelectionMode;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/settings.dart' show KeymapPreset;
import 'package:flutter3d_modeler/src/ui/command_palette.dart';
import 'package:flutter3d_modeler/src/ui/keymap.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

final Keymap _keymap = keymapFor(KeymapPreset.standard, apple: false);

List<PaletteEntry> _entries({
  ModelerMode mode = ModelerMode.object,
  Set<String> unavailable = const <String>{},
}) => paletteEntries(
  mode: mode,
  animation: AnimationSubmode.pose,
  keymap: _keymap,
  unavailable: unavailable,
);

PaletteEntry _find(List<PaletteEntry> entries, String id) =>
    entries.firstWhere((PaletteEntry it) => it.id == id);

void main() {
  group('what the palette lists', () {
    test('every tool of every built mode, whichever mode is open', () {
      final List<PaletteEntry> entries = _entries();

      // Mutation: list the open mode's rail alone — which is what the rail
      // itself already does. A person looking for "Bevel" from object mode
      // then finds nothing, and the palette answers "there is no such
      // command" about a command there is.
      expect(_find(entries, 'mesh.bevel').label, 'Bevel');
      expect(_find(entries, 'object.duplicate').label, 'Duplicate');
      expect(_find(entries, 'weights.paint').label, isNotEmpty);
    });

    test('and says which mode the ones from elsewhere need', () {
      final List<PaletteEntry> entries = _entries();

      final PaletteEntry bevel = _find(entries, 'mesh.bevel');
      expect(bevel.enabled, isFalse);
      expect(bevel.disabledBecause, contains('Mesh'));

      // The open mode's own are runnable.
      expect(_find(entries, 'object.duplicate').enabled, isTrue);
    });

    test('the key each one answers to, from the live preset', () {
      final List<PaletteEntry> entries = _entries(mode: ModelerMode.mesh);

      // Mutation: read `ModelerTool.shortcut` rather than the preset. The
      // palette then teaches a key the person's own settings do not bind,
      // which is worse than teaching none — `ux-10`'s own finding.
      expect(_find(entries, 'mesh.extrude').keys, 'E');
      final List<PaletteEntry> school = paletteEntries(
        mode: ModelerMode.mesh,
        animation: AnimationSubmode.pose,
        keymap: keymapFor(KeymapPreset.toolKeys, apple: false),
      );
      expect(_find(school, 'mesh.extrude').keys, 'Shift+E');
    });

    test('an entry that would refuse says so before it is chosen', () {
      final List<PaletteEntry> entries = _entries(
        unavailable: unavailableTools(
          mode: ModelerMode.object,
          selection: const ProjectSelection(),
        ),
      );

      // Mutation: offer everything and let the command refuse afterwards. The
      // palette then looks like a list of things that work, and the answer
      // arrives in the status line after the fact.
      expect(_find(entries, 'object.delete').enabled, isFalse);
      expect(
        _find(entries, 'object.delete').disabledBecause,
        contains('selec'),
      );
      // The ones that make a selection rather than needing one stay live.
      expect(_find(entries, 'object.add').enabled, isTrue);
      expect(_find(entries, 'object.select').enabled, isTrue);
    });

    test('and with something selected they are all live again', () {
      expect(
        unavailableTools(
          mode: ModelerMode.mesh,
          selection: const ProjectSelection(
            mode: SelectionMode.mesh,
            objects: <int>[1],
            elements: <int>[3],
          ),
        ),
        isEmpty,
      );
    });
  });

  group('finding one', () {
    test('three letters of a label find it', () {
      final PaletteEntry bevel = _find(_entries(), 'mesh.bevel');

      // The acceptance this row states.
      expect(paletteMatches(bevel, 'bev'), isTrue);
      expect(paletteMatches(bevel, 'BEV'), isTrue);
      expect(paletteMatches(bevel, 'mesh.'), isTrue);
      expect(paletteMatches(bevel, 'lathe'), isFalse);
    });

    test('an empty search shows everything', () {
      final PaletteEntry bevel = _find(_entries(), 'mesh.bevel');
      expect(paletteMatches(bevel, ''), isTrue);
      expect(paletteMatches(bevel, '   '), isTrue);
    });
  });

  group('the dialog', () {
    testWidgets('typing narrows the list and a tap answers with the id', (
      WidgetTester tester,
    ) async {
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: modelerTheme(),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () async {
                  chosen = await showCommandPalette(
                    context,
                    entries: _entries(mode: ModelerMode.mesh),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Everything in the mesh rail, before a word is typed. Bevel is the
      // ninth of them and `ux-18` gave every row a second line saying what
      // the tool does, so it starts below the fold — which is what the
      // field above the list is for.
      expect(find.text('Extrude'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'bev');
      await tester.pumpAndSettle();

      expect(find.text('Bevel'), findsOneWidget);
      expect(find.text('Extrude'), findsNothing);

      await tester.tap(find.text('Bevel'));
      await tester.pumpAndSettle();

      expect(chosen, 'mesh.bevel');
    });

    testWidgets('a disabled entry cannot be chosen', (
      WidgetTester tester,
    ) async {
      String? chosen = 'untouched';
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: modelerTheme(),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () async {
                  chosen = await showCommandPalette(
                    context,
                    // Object mode is open, so the mesh rail is listed and
                    // disabled.
                    entries: _entries(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bevel');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bevel'));
      await tester.pumpAndSettle();

      // Still open, still nothing chosen: the row says which mode it needs
      // rather than pretending to run.
      expect(chosen, 'untouched');
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets("ux-18: a row says what the command does, and a refusal "
        'takes that line instead', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: modelerTheme(),
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showCommandPalette(
                  context,
                  entries: _entries(mode: ModelerMode.mesh),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'dissolve');
      await tester.pumpAndSettle();

      final ModelerTool dissolve = toolsFor(
        ModelerMode.mesh,
      ).firstWhere((ModelerTool it) => it.id == 'mesh.dissolve');
      expect(find.text(dissolve.about), findsOneWidget);

      // And where there is a reason the row cannot run, that wins the line:
      // being told why something is greyed matters more right now than
      // being told what it would have done.
      await tester.enterText(find.byType(TextField), 'lathe');
      await tester.pumpAndSettle();
      expect(find.textContaining('Object mode'), findsOneWidget);
    });
  });
}
