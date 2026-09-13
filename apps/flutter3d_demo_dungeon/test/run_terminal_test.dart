/// `wg-02`: `FrameEffects.log` accumulates what the level says, and
/// `RunTerminal` shows it — the terminal on the crypt's own wall, proven
/// without a `WidgetSurfacePipeline` in the way, the same reason `wg-01`'s
/// own `HeatmapLayout`-style split keeps arithmetic separate from a widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_demo_dungeon/src/frame_effects.dart';
import 'package:flutter3d_demo_dungeon/src/run_terminal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FrameEffects.log', () {
    test('collects what say() records, oldest first', () {
      final effects = FrameEffects();
      effects.say('the door is locked');
      effects.say('you found a key');
      expect(effects.log.value, <String>['the door is locked', 'you found a key']);
    });

    test('a null message is not recorded', () {
      final effects = FrameEffects();
      effects.say(null);
      expect(effects.log.value, isEmpty);
    });

    test('caps at logCapacity, dropping the oldest first', () {
      final effects = FrameEffects();
      for (var i = 0; i < FrameEffects.logCapacity + 3; i++) {
        effects.say('message $i');
      }
      expect(effects.log.value, hasLength(FrameEffects.logCapacity));
      expect(effects.log.value.first, 'message 3');
      expect(effects.log.value.last, 'message ${FrameEffects.logCapacity + 2}');
    });
  });

  group('RunTerminal', () {
    testWidgets('shows nothing said yet as a placeholder line', (tester) async {
      final log = ValueNotifier<List<String>>(const <String>[]);
      await tester.pumpWidget(MaterialApp(home: RunTerminal(log: log)));
      expect(find.text('> ...'), findsOneWidget);
    });

    testWidgets('shows every line the log holds', (tester) async {
      final log = ValueNotifier<List<String>>(const <String>['first', 'second']);
      await tester.pumpWidget(MaterialApp(home: RunTerminal(log: log)));
      expect(find.text('> first'), findsOneWidget);
      expect(find.text('> second'), findsOneWidget);
    });

    testWidgets('redraws when the log changes, without a new widget instance', (
      tester,
    ) async {
      final log = ValueNotifier<List<String>>(const <String>['first']);
      await tester.pumpWidget(MaterialApp(home: RunTerminal(log: log)));
      expect(find.text('> first'), findsOneWidget);

      log.value = const <String>['first', 'second'];
      await tester.pump();

      expect(find.text('> first'), findsOneWidget);
      expect(find.text('> second'), findsOneWidget);
    });
  });
}
