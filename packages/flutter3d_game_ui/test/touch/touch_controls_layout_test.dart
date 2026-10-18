/// A stick, a cluster, slots and a switch, laid out for two thumbs.
///
///     flutter test test/touch/touch_controls_layout_test.dart
///
/// Moved here from the dungeon demo's `touch_crypt.dart`, which is now the
/// crypt's verbs laid into this. It was `TouchCluster`'s until that and
/// `TouchControls` became one widget. What is held here is the layout's own rule:
/// what is pressed often sits where the thumb rests, and what is costly to
/// press by mistake takes a reach.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_game_ui/touch.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _held = GameAction('held');

Widget _cluster(
  InputState input, {
  List<TouchSlot> slots = const <TouchSlot>[
    TouchSlot('one'),
    TouchSlot('two'),
    TouchSlot('three', owned: false),
  ],
  int current = 0,
  VoidCallback? onToggle,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(
    width: 900,
    height: 500,
    child: TouchControls(
      state: input,
      buttons: const <TouchAction>[
        TouchAction(GameAction.use, 'use'),
        TouchAction(GameAction.jump, 'jump'),
        TouchAction(_held, 'held'),
      ],
      slots: slots,
      current: current,
      corner: TouchToggle(label: 'map', on: false, onTap: onToggle ?? () {}),
    ),
  ),
);

void main() {
  testWidgets('every control can be reached, all at once', (
    WidgetTester tester,
  ) async {
    // Mutation: drop the `for` over `buttons` — no button is found and this
    // fails; drop the toggle's `Positioned` and the switch line does.
    final input = InputState();
    var toggled = 0;
    await tester.pumpWidget(_cluster(input, onToggle: () => toggled++));

    final walking = await tester.startGesture(
      tester.getCenter(find.byType(TouchStick)),
      pointer: 1,
    );
    await walking.moveBy(const Offset(0, -64));
    await tester.pump();
    expect(input.moveAxis.y, closeTo(1.0, 1e-6), reason: 'no way to walk');

    // A finger each and all down at once, which is also the claim that the
    // buttons do not overlap.
    const buttons = <(String, GameAction)>[
      ('held', _held),
      ('use', GameAction.use),
      ('jump', GameAction.jump),
    ];
    for (var i = 0; i < buttons.length; i++) {
      final (label, action) = buttons[i];
      await tester.startGesture(
        tester.getCenter(find.widgetWithText(TouchButton, label)),
        pointer: 2 + i,
      );
      await tester.pump();
      expect(input.held(action), isTrue, reason: 'no way to $label');
    }

    await tester.tap(find.text('two'), pointer: 9);
    expect(input.slotRequest, 1, reason: 'no way to choose a slot');

    await tester.tap(find.byType(TouchToggle), pointer: 10);
    expect(toggled, 1, reason: 'no way to flip the switch');
  });

  testWidgets('the last button is the one nearest the thumb', (
    WidgetTester tester,
  ) async {
    // Mutation: reverse `buttons` in the `Wrap` — this fails.
    await tester.pumpWidget(_cluster(InputState()));
    final right = <String, double>{
      for (final label in <String>['use', 'jump', 'held'])
        label: tester.getRect(find.widgetWithText(TouchButton, label)).right,
    };
    expect(right['held'], greaterThan(right['jump']!));
    expect(right['jump'], greaterThan(right['use']!));
  });

  testWidgets('the switch and the slots are out of the cluster', (
    WidgetTester tester,
  ) async {
    // Mutation: put the slots at the cluster's own `bottom` — the second
    // expectation fails.
    await tester.pumpWidget(_cluster(InputState()));

    final held = tester.getRect(find.widgetWithText(TouchButton, 'held'));
    final toggle = tester.getRect(find.byType(TouchToggle));
    final slots = tester.getRect(find.byType(TouchSlots));

    expect(
      toggle.bottom,
      lessThan(slots.top),
      reason: 'the switch is in a row',
    );
    expect(slots.bottom, lessThan(held.top), reason: 'the slots are in reach');
  });

  testWidgets('a game with no slots and no switch gets neither', (
    WidgetTester tester,
  ) async {
    // Mutation: draw `TouchSlots` whatever `slots` holds — this fails.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 900,
          height: 500,
          child: TouchControls(
            state: InputState(),
            buttons: const <TouchAction>[TouchAction(GameAction.jump, 'jump')],
          ),
        ),
      ),
    );
    expect(find.byType(TouchSlots), findsNothing);
    expect(find.byType(TouchToggle), findsNothing);
    expect(find.byType(TouchStick), findsOneWidget);
  });
}
