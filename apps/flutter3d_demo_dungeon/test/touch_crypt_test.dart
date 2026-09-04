/// The crypt under two thumbs.
///
///     flutter test test/touch_crypt_test.dart
///
/// **Two buttons for a game with six verbs.** The touch build offered `use` and
/// `fire` and nothing else: the arsenal is four weapons deep and only whichever
/// one was already in hand could be fired, and the automap — `Automap`,
/// `AutomapView`, and the reveal the simulation runs every step — was behind
/// the M key and behind nothing else. Both were reachable on a keyboard and on
/// a pad, and neither on the device the touch controls exist for.
///
/// What this file holds is the claim that every verb has a finger-shaped way
/// in, and the two layout rules that keep them from being pressed by accident.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart' show startingInventory;
import 'package:flutter3d_demo_dungeon/src/touch_crypt.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';

/// The loadout this game actually starts with, from its own staging rather
/// than made up here: four slots, four of them owned, the pistol in hand.
Arsenal _opening() => startingInventory().arsenal;

Widget _crypt(
  InputState input, {
  Arsenal? arsenal,
  bool mapOn = false,
  VoidCallback? onMap,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(
    width: 900,
    height: 500,
    child: TouchCrypt(
      state: input,
      arsenal: arsenal ?? _opening(),
      mapOn: mapOn,
      onMap: onMap ?? () {},
    ),
  ),
);

void main() {
  testWidgets('every verb the crypt has can be reached with a thumb', (
    WidgetTester tester,
  ) async {
    // The whole of the complaint, as one list. Walking, firing, using and
    // jumping are held or pressed; a weapon is chosen; the map is set.
    //
    // Mutation: delete any one of the three `TouchButton`s from `TouchCrypt` —
    // its line here fails. Delete the `TouchSlots` and the weapon expectation
    // fails; delete the `TouchToggle` and the map one does.
    final input = InputState();
    var maps = 0;
    await tester.pumpWidget(_crypt(input, onMap: () => maps++));

    final walking = await tester.startGesture(
      tester.getCenter(find.byType(TouchStick)),
      pointer: 1,
    );
    await walking.moveBy(const Offset(0, -64));
    await tester.pump();
    expect(input.moveAxis.y, closeTo(1.0, 1e-6), reason: 'no way to walk');

    // A finger each, and all of them down at once — which is also the claim
    // that the three do not overlap, since a second `TouchButton` under the
    // same point would never see its pointer.
    const cluster = <(String, GameAction)>[
      ('fire', ShooterActions.fire),
      ('use', GameAction.use),
      ('jump', GameAction.jump),
    ];
    for (var i = 0; i < cluster.length; i++) {
      final (label, action) = cluster[i];
      await tester.startGesture(
        tester.getCenter(find.widgetWithText(TouchButton, label)),
        pointer: 2 + i,
      );
      await tester.pump();
      expect(input.held(action), isTrue, reason: 'no way to $label');
    }

    // The shotgun: slot two, and not the one in hand — which is the point. On
    // a phone this was the whole of the arsenal that could not be asked for.
    await tester.tap(find.text('shotgun'), pointer: 9);
    expect(input.slotRequest, 2, reason: 'no way to change weapon');

    await tester.tap(find.byType(TouchToggle), pointer: 10);
    expect(maps, 1, reason: 'no way to open the map');
  });

  testWidgets('and the map is nowhere near the trigger', (
    WidgetTester tester,
  ) async {
    // The rule the layout was rebuilt around: how often a control is wanted,
    // against how bad it is to press by accident. Firing happens every second
    // and costs nothing if it happens by mistake; the map and the weapon row
    // are wanted twice a room, and putting the fists in your hand in front of
    // a tank loses the run. So neither is inside the cluster a thumb rests in.
    //
    // Mutation: move the `TouchToggle` in `TouchCrypt` into the bottom-right
    // `Wrap` beside `fire` — both expectations fail.
    await tester.pumpWidget(_crypt(InputState()));

    final fire = tester.getRect(find.widgetWithText(TouchButton, 'fire'));
    final map = tester.getRect(find.byType(TouchToggle));
    final weapons = tester.getRect(find.byType(TouchSlots));

    expect(
      map.bottom,
      lessThan(weapons.top),
      reason: 'the map is in the weapon row',
    );
    expect(
      weapons.bottom,
      lessThan(fire.top),
      reason: 'the weapon row is in the cluster a thumb rests on',
    );
  });

  testWidgets('and says which weapon is in hand', (WidgetTester tester) async {
    // A row of four identical buttons is four guesses. `Arsenal.current` is the
    // answer and the row asks it — the same number the HUD prints, so the two
    // cannot disagree about what is being held.
    //
    // Mutation: hard-code `current: 0` in `TouchCrypt` — the pistol stops being
    // selected and this fails.
    final semantics = tester.ensureSemantics();
    final arsenal = _opening();
    await tester.pumpWidget(_crypt(InputState(), arsenal: arsenal));

    expect(arsenal.current.name, 'Pistol', reason: 'the loadout moved');
    expect(
      tester.getSemantics(find.bySemanticsLabel('pistol')),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('fists')),
      isSemantics(isSelected: false),
    );
    semantics.dispose();
  });

  testWidgets('and draws a row for a player holding nothing at all', (
    WidgetTester tester,
  ) async {
    // `Arsenal.current` throws rather than inventing a weapon to answer, and an
    // empty arsenal is a real state — a game that hands out nothing to start
    // with, which is what `Arsenal`'s own default is.
    //
    // Mutation: ask `arsenal.current` unguarded in `TouchCrypt._held` — this
    // becomes a StateError rather than a screen.
    await tester.pumpWidget(
      _crypt(
        InputState(),
        arsenal: Arsenal(slots: <WeaponDef>[Weapons.fists], owned: const []),
      ),
    );

    expect(find.text('fists'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
