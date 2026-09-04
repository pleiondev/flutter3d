/// The two controls a thumb needs that a held button cannot be.
///
///     flutter test test/touch_verbs_test.dart
///
/// **A phone was offered one kind of control and games have more than one kind
/// of verb.** [TouchButton] holds an action while a finger is on it, which is
/// right for a trigger and wrong for everything that lasts or that is chosen:
/// the platformer's sprint was unreachable on a handset because holding it
/// costs the thumb that steers, and three of the crypt's four weapons were
/// unreachable because `requestSlot` had no finger-shaped way in — the pad
/// reaches it through the d-pad and the keyboard through the number row.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

void main() {
  group('a latching control', () {
    test('turns an ordinary action on and off again', () {
      // Mutation: make `InputState.toggle` always call `press`. The second tap
      // then holds a second time rather than letting go, and the third
      // expectation fails — which is a sprint that can be turned on and never
      // off, the state a phone would have been left in.
      final input = InputState();

      input.toggle(GameAction.sprint);
      expect(input.held(GameAction.sprint), isTrue);
      input.toggle(GameAction.sprint);
      expect(input.held(GameAction.sprint), isFalse);
    });

    test('and one the player has already asked to latch', () {
      // The accessibility setting and the thumb want the same thing, and the
      // sequences that produce it are opposite: latched, a press flips and a
      // release means nothing. A widget calling press/release directly would
      // turn sprint on and be unable to turn it off.
      //
      // Mutation: drop the `_toggled.contains(action)` arm from
      // `InputState.toggle` — the second tap calls `release`, which a latched
      // action ignores, and the third expectation fails.
      final input = InputState()..setToggled(GameAction.sprint, toggled: true);

      input.toggle(GameAction.sprint);
      expect(input.held(GameAction.sprint), isTrue);
      input.toggle(GameAction.sprint);
      expect(input.held(GameAction.sprint), isFalse);
    });

    testWidgets('and the button says which way it is set', (
      WidgetTester tester,
    ) async {
      // The whole reason [TouchToggle] takes `on` rather than keeping it: a
      // control that stays on after the finger has gone has to be able to say
      // so, and one holding its own copy is the checkbox that reads off while
      // the thing is on.
      //
      // Mutation: make `TouchToggle` ignore `on` and always paint the off
      // colour — `toggled` in the semantics goes with it and this fails.
      final input = InputState();
      Widget button() => _wrap(
        TouchToggle(
          label: 'sprint',
          on: input.held(GameAction.sprint),
          onTap: () => input.toggle(GameAction.sprint),
        ),
      );

      await tester.pumpWidget(button());
      expect(
        tester.getSemantics(find.byType(TouchToggle)),
        matchesSemantics(label: 'sprint', hasToggledState: true),
      );

      await tester.tap(find.byType(TouchToggle));
      await tester.pumpWidget(button());

      expect(input.held(GameAction.sprint), isTrue);
      expect(
        tester.getSemantics(find.byType(TouchToggle)),
        matchesSemantics(
          label: 'sprint',
          hasToggledState: true,
          isToggled: true,
        ),
      );
    });

    testWidgets('and sits clear of the buttons that are held', (
      WidgetTester tester,
    ) async {
      // Not decoration: a thumb coming off the jump button must not be able to
      // land on a control that latches. The toggles are a row above the
      // cluster, which is what this measures.
      //
      // Mutation: put `toggles` into the same `Wrap` as the buttons in
      // `TouchControls` — they end up on one line and this fails.
      final input = InputState();
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 800,
            height: 600,
            child: TouchControls(
              state: input,
              buttons: const <TouchAction>[
                TouchAction(GameAction.jump, 'jump'),
              ],
              toggles: <TouchToggle>[
                TouchToggle(label: 'sprint', on: false, onTap: () {}),
              ],
            ),
          ),
        ),
      );

      final sprint = tester.getRect(find.byType(TouchToggle));
      final jump = tester.getRect(find.byType(TouchButton));

      expect(
        sprint.bottom,
        lessThan(jump.top),
        reason: 'the latch is inside the cluster a thumb rests on',
      );
    });
  });

  group('a row of numbered slots', () {
    testWidgets('asks for the one that was tapped', (
      WidgetTester tester,
    ) async {
      // The index, not the label: `slotRequest` is an index into the game's own
      // roster, and a row that reported its position in a filtered list would
      // hand the player whatever happened to be third today.
      //
      // Mutation: pass `slot + 1` to `requestSlot` in `TouchSlots` — this
      // fails on the second expectation.
      final input = InputState();
      await tester.pumpWidget(
        _wrap(
          TouchSlots(
            state: input,
            current: 0,
            slots: const <TouchSlot>[
              TouchSlot('fists'),
              TouchSlot('pistol'),
              TouchSlot('shotgun', owned: false),
            ],
          ),
        ),
      );

      expect(input.slotRequest, isNull);
      await tester.tap(find.text('pistol'));
      expect(input.slotRequest, 1);
    });

    testWidgets('and asks for one that is not owned yet', (
      WidgetTester tester,
    ) async {
      // A button that does nothing and says nothing is a button a player
      // decides is broken. `Arsenal.selectSlot` already refuses what is not
      // owned, in one place, for every device — so the row asks and lets it.
      //
      // Mutation: skip `requestSlot` for an unowned slot in `TouchSlots` —
      // this fails.
      final input = InputState();
      await tester.pumpWidget(
        _wrap(
          TouchSlots(
            state: input,
            current: 0,
            slots: const <TouchSlot>[
              TouchSlot('fists'),
              TouchSlot('rocket', owned: false),
            ],
          ),
        ),
      );

      await tester.tap(find.text('rocket'));
      expect(input.slotRequest, 1);
    });
  });
}
