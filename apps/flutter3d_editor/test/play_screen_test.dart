/// `HR5`'s panel over a run of the test's own making, and over a game the
/// editor attached to rather than started.
///
///     flutter test test/play_screen_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/play/device_picker.dart';
import 'package:flutter3d_editor/src/play/play_screen.dart';
import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';
import 'package:flutter3d_editor_play/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const List<FlutterDevice> _devices = <FlutterDevice>[
  FlutterDevice(id: 'macos', name: 'macOS', platform: 'darwin'),
  FlutterDevice(id: 'R5CX', name: 'Galaxy A55', platform: 'android-arm64'),
];

Future<void> _pump(
  WidgetTester tester,
  FlutterRun run, {
  List<String>? timelines,
}) => tester.pumpWidget(
  MaterialApp(
    home: PlayScreen(
      session: run,
      onTimeline: timelines?.add ?? (String _) {},
      picker: ({required bool enabled}) => DevicePicker(
        run: run,
        enabled: enabled,
        devices: () async => _devices,
      ),
    ),
  ),
);

IconButton _button(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(ValueKey<String>(key)));

void main() {
  testWidgets('the panel offers a reload only once the game is running', (
    WidgetTester tester,
  ) async {
    final it = fakeFlutterRun();
    final timelines = <String>[];
    await it.run.start();
    await _pump(tester, it.run, timelines: timelines);

    expect(_button(tester, 'play.reload').onPressed, isNull);
    expect(_button(tester, 'play.timeline').onPressed, isNull);

    it.tool.running();
    await tester.pump();
    await tester.pump();

    expect(find.text('Running, ws://game'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('play.reload')));
    await tester.pump();
    expect(it.tool.sent.single['method'], 'app.restart');

    await tester.tap(find.byKey(const ValueKey<String>('play.timeline')));
    expect(timelines, <String>['ws://game']);
  });

  testWidgets('a device picked between runs is the next run\'s', (
    WidgetTester tester,
  ) async {
    final it = fakeFlutterRun(device: null);
    await _pump(tester, it.run);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('play.device')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galaxy A55').last);
    await tester.pumpAndSettle();
    expect(it.run.device, 'R5CX');

    await tester.tap(find.byKey(const ValueKey<String>('play.start')));
    await tester.pump();
    expect(it.started.single, <String>[
      '/game',
      'run',
      '--machine',
      '-d',
      'R5CX',
    ]);
  });

  testWidgets('and is held still while one is going', (
    WidgetTester tester,
  ) async {
    final it = fakeFlutterRun();
    await it.run.start();
    await _pump(tester, it.run);
    await tester.pump();

    final picker = tester.widget<DropdownButton<String?>>(
      find.byKey(const ValueKey<String>('play.device')),
    );
    expect(picker.onChanged, isNull);
  });

  testWidgets('an attached game is reloaded, timed and let go of', (
    WidgetTester tester,
  ) async {
    final game = FakeGame(registered: FakeGame.flutterTool());
    final run = fakeAttachedRun(game);
    final timelines = <String>[];
    await tester.runAsync(run.start);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayScreen(session: run, onTimeline: timelines.add),
      ),
    );

    // No process, so no device to pick.
    expect(find.byKey(const ValueKey<String>('play.device')), findsNothing);
    expect(find.text('Attached, ws://game/ws'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('play.reload')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(game.calls.last['method'], 's0.reloadSources');

    await tester.tap(find.byKey(const ValueKey<String>('play.timeline')));
    expect(timelines, <String>['ws://game/ws']);

    // Mutation: the owner's tooltip here would promise a Stop that ends a
    // game somebody else started, where the button only lets go of it.
    expect(
      _button(tester, 'play.start').tooltip,
      'Detach (the game keeps running)',
    );
    await tester.tap(find.byKey(const ValueKey<String>('play.start')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('Detached; the game keeps running'), findsOneWidget);
  });
}
