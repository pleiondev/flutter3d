/// The console: what the editor said, kept after the strip has moved on;
/// what the game being played printed and posted, read from where Play
/// keeps it; and a filter over all three.
///
///     flutter test test/console_panel_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/console_panel.dart';
import 'package:flutter3d_editor/src/editor_cubit.dart';
import 'package:flutter3d_editor/src/editor_theme.dart';
import 'package:flutter3d_editor_play/attach.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_cubit_helpers.dart';

/// A game with a console and events and nothing behind them.
final class _Game with PlayedGame {
  @override
  final Watched<List<String>> console = Watched<List<String>>(const <String>[]);

  @override
  final Watched<List<PostedEvent>> events = Watched<List<PostedEvent>>(
    const <PostedEvent>[],
  );

  @override
  final Watched<PlayState> state = Watched<PlayState>(const PlayIdle());

  @override
  String get title => 'test game';

  @override
  bool get ownsTheGame => false;

  @override
  Future<void> start() async {}

  @override
  Future<String?> hotSwap() async => null;

  @override
  Future<String?> hotRestart() async => null;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

Widget _console(EditorLog log, {PlayedGame? game}) => MaterialApp(
  theme: editorTheme(),
  home: Scaffold(
    body: ConsolePanel(log: log, game: game),
  ),
);

/// Every line on screen, top to bottom. The list is built newest first —
/// it is reversed so it stays scrolled to the bottom — so the rows are read
/// in the other order.
List<String> _lines(WidgetTester tester) => <String>[
  for (final row in tester.widgetList<SelectableText>(
    find.descendant(
      of: find.byKey(const ValueKey<String>('console.lines')),
      matching: find.byType(SelectableText),
    ),
  ))
    row.textSpan!.toPlainText(),
].reversed.toList();

void main() {
  test('the cubit keeps every sentence it says, repeats included', () {
    // The strip shows one at a time; the log is where the one before went.
    //
    // Mutation: drop `log.add` from `_updateReady`. `say` stops being kept
    // and only the opening line is left.
    final cubit = EditorCubit()
      ..opened(openTestDocument(), looks: noLooks)
      ..say('nothing selected')
      ..say('nothing selected')
      ..setAxis(EditorAxis.y);
    addTearDown(cubit.close);

    expect(
      <String>[for (final e in cubit.log.entries) e.text],
      <String>[
        '/levels/test.json: opened 2 brushes',
        'nothing selected',
        'nothing selected',
      ],
    );
  });

  test('and a failure is kept as one', () {
    final cubit = EditorCubit()..failed(StateError('no device'));
    addTearDown(cubit.close);

    expect(cubit.log.entries.single.error, isTrue);
  });

  testWidgets('shows what the editor said, newest last, and keeps up', (
    WidgetTester tester,
  ) async {
    // Mutation: build the editor tab from the log once rather than through
    // `ListenableBuilder`. The line added after the panel is up never
    // appears.
    final log = EditorLog(clock: () => DateTime(2026, 10, 8, 9, 5, 7))
      ..add('opened 2 brushes');
    await tester.pumpWidget(_console(log));

    log.add('moved');
    await tester.pump();

    expect(_lines(tester), <String>[
      '09:05:07  opened 2 brushes',
      '09:05:07  moved',
    ]);
  });

  testWidgets('the filter keeps the lines that contain it', (
    WidgetTester tester,
  ) async {
    // Mutation: make `_keeps` answer true for everything. Both lines stay.
    final log = EditorLog()
      ..add('saved crypt.json')
      ..add('nothing selected');
    await tester.pumpWidget(_console(log));

    await tester.enterText(
      find.byKey(const ValueKey<String>('console.filter')),
      'SAVED',
    );
    await tester.pump();

    expect(_lines(tester), hasLength(1));
    expect(_lines(tester).single, endsWith('saved crypt.json'));
  });

  testWidgets("the game tab is the game's own console, as it grows", (
    WidgetTester tester,
  ) async {
    // What Play keeps is read as it is: the same lines the Play screen
    // shows, with nothing copied out of them.
    //
    // Mutation: show `game.events` under the Game tab. The printed lines
    // never appear.
    final game = _Game();
    game.console.value = <String>['flutter: level up'];
    await tester.pumpWidget(_console(EditorLog(), game: game));

    await tester.tap(find.byKey(const ValueKey<String>('console.game')));
    await tester.pump();
    expect(_lines(tester), <String>['flutter: level up']);

    game.console.value = <String>['flutter: level up', 'flutter: died'];
    await tester.pump();
    expect(_lines(tester).last, 'flutter: died');
  });

  testWidgets('the events tab numbers what the game posted', (
    WidgetTester tester,
  ) async {
    final game = _Game();
    game.events.value = const <PostedEvent>[
      PostedEvent(
        sequence: 3,
        kind: 'player.died',
        time: null,
        data: <String, Object?>{'at': 'pit'},
      ),
    ];
    await tester.pumpWidget(_console(EditorLog(), game: game));

    await tester.tap(find.byKey(const ValueKey<String>('console.events')));
    await tester.pump();

    expect(_lines(tester), <String>['#3  player.died  {"at":"pit"}']);
  });

  testWidgets('with no game it says how to get one', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_console(EditorLog()));

    await tester.tap(find.byKey(const ValueKey<String>('console.game')));
    await tester.pump();

    expect(_lines(tester).single, startsWith('No game is being played'));
  });
}
