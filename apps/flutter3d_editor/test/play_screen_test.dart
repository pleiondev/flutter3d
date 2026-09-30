/// `HR5`'s panel over a run of the test's own making.
///
///     flutter test test/play_screen_test.dart
library;

import 'package:flutter/material.dart';
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
      run: run,
      onTimeline: timelines?.add ?? (String _) {},
      devices: () async => _devices,
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
}
