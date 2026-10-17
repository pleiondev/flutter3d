/// `CommandPalette`: letters typed in order find a command, initials and
/// runs of letters rank first, the keys move and run, and a command that
/// cannot run now is listed and refuses.
///
///     flutter test test/command_palette_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the matching', () {
    test('every letter must appear, in order', () {
      // Mutation: drop `from = at + 1`. Letters may then be reused and found
      // out of order, and "cas" matches "Save a copy".
      expect(fuzzyScore('sac', 'Save a copy'), isNotNull);
      expect(fuzzyScore('cas', 'Save a copy'), isNull);
      expect(fuzzyScore('xyz', 'Save a copy'), isNull);
    });

    test('initials rank above the same letters run together in one word', () {
      // Typing the first letter of each word is how a long title is asked
      // for, and it must beat a short word that happens to spell the query.
      //
      // Mutation: drop the word-start bonus. "Sack" then scores its run of
      // three and wins on being shorter.
      final ranked = rankCommands(<PaletteCommand>[
        PaletteCommand(id: 'sack', title: 'Sack', run: () {}),
        PaletteCommand(id: 'copy', title: 'Save a copy', run: () {}),
      ], 'sac');

      expect(ranked.first.id, 'copy');
    });

    test('and a run of letters ranks above the same letters scattered', () {
      // Mutation: drop the bonus for a letter following the last match.
      // Both titles then score one word start and two letters, and the
      // shorter one, whose `d` is four letters on, wins.
      final ranked = rankCommands(<PaletteCommand>[
        PaletteCommand(id: 'scatter', title: 'Unbound', run: () {}),
        PaletteCommand(id: 'undo', title: 'Undo the last change', run: () {}),
      ], 'und');

      expect(ranked.first.id, 'undo');
    });

    test('an empty query lists everything in its own order', () {
      final all = <PaletteCommand>[
        PaletteCommand(id: 'b', title: 'Beta', run: () {}),
        PaletteCommand(id: 'a', title: 'Alpha', run: () {}),
      ];
      expect(rankCommands(all, '  '), same(all));
    });
  });

  group('the palette', () {
    late List<String> ran;

    List<PaletteCommand> commands() => <PaletteCommand>[
      PaletteCommand(
        id: 'save',
        title: 'Save',
        shortcut: '⌘S',
        run: () => ran.add('save'),
      ),
      PaletteCommand(
        id: 'saveCopy',
        title: 'Save a copy',
        run: () => ran.add('saveCopy'),
      ),
      PaletteCommand(
        id: 'redo',
        title: 'Redo',
        enabled: false,
        run: () => ran.add('redo'),
      ),
    ];

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showCommandPalette(context, commands()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    setUp(() => ran = <String>[]);

    testWidgets('typing narrows the list and Enter runs the best match', (
      WidgetTester tester,
    ) async {
      // Mutation: have Enter run `shown.first` of the unfiltered commands.
      // "Save" runs instead of "Save a copy".
      await open(tester);

      await tester.enterText(
        find.byKey(const ValueKey<String>('palette.query')),
        'copy',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('palette.row.save')),
        findsNothing,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(ran, <String>['saveCopy']);
      expect(find.byType(CommandPalette), findsNothing);
    });

    testWidgets('the arrows move which one Enter runs', (
      WidgetTester tester,
    ) async {
      // Mutation: make the arrow-down case return `handled` without moving
      // `_at`. Enter then runs the first row, "Save".
      await open(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(ran, <String>['saveCopy']);
    });

    testWidgets('a command that cannot run is shown and refuses', (
      WidgetTester tester,
    ) async {
      // Mutation: drop the `enabled` check in `_choose`. Enter on "Redo"
      // runs it and closes the palette.
      await open(tester);

      expect(find.text('⌘S'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey<String>('palette.query')),
        'redo',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(ran, isEmpty);
      expect(find.byType(CommandPalette), findsOneWidget);
    });

    testWidgets('a click runs the row clicked', (WidgetTester tester) async {
      await open(tester);

      await tester.tap(find.byKey(const ValueKey<String>('palette.row.save')));
      await tester.pumpAndSettle();

      expect(ran, <String>['save']);
    });
  });
}
