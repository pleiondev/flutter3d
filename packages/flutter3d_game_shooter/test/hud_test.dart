/// The readouts, and the three details every game got wrong writing them.
///
///     flutter test test/hud_test.dart
///
/// Each of these is a claim about a number rather than about a picture: what
/// the fists print, what armour is drawn over, and what a key colour nobody
/// declared comes out as. A golden would say the layout is unchanged; these say
/// the reading is right, which is the part that was wrong three times.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the ammunition readout', () {
    testWidgets('prints infinity for a weapon that spends nothing', (
      WidgetTester tester,
    ) async {
      // The bug this exists to stop: `arsenal.currentAmmo` is nought for the
      // fists, which reads as a weapon that cannot fire — and it is the one
      // weapon that always can.
      final arsenal = sampleArsenal()..selectSlot(0);
      expect(arsenal.current.ammo, AmmoType.none);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AmmoReadout(arsenal: arsenal),
        ),
      );

      expect(find.text('∞'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('and the count for one that does', (WidgetTester tester) async {
      final arsenal = sampleArsenal()..selectSlot(1);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AmmoReadout(arsenal: arsenal),
        ),
      );

      expect(find.text('${arsenal.currentAmmo}'), findsOneWidget);
    });

    testWidgets('and draws nothing at all with no weapon in hand', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AmmoReadout(arsenal: Arsenal(slots: const <WeaponDef>[])),
        ),
      );

      expect(find.byType(Text), findsNothing);
    });
  });

  group('the key ring', () {
    testWidgets('draws one pip per key carried, and none for a key used', (
      WidgetTester tester,
    ) async {
      final inventory = Inventory();
      inventory.keyRing.take('blue');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: KeyPips(inventory: inventory),
        ),
      );
      expect(find.byType(DecoratedBox), findsOneWidget);

      inventory.keyRing.clear();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: KeyPips(inventory: inventory),
        ),
      );
      expect(find.byType(DecoratedBox), findsNothing);
    });

    testWidgets('and a colour nobody declared is drawn dim, not dropped', (
      WidgetTester tester,
    ) async {
      // A level may name a key this table has never heard of. A pip in grey is
      // a better answer than a missing pip the player cannot account for.
      final inventory = Inventory();
      inventory.keyRing.take('chartreuse');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: KeyPips(
            inventory: inventory,
            colours: const <String, Color>{'blue': Color(0xFF3A6BF2)},
          ),
        ),
      );

      expect(find.byType(DecoratedBox), findsOneWidget);
    });
  });

  group('the health bar', () {
    testWidgets('draws armour over health rather than beside it', (
      WidgetTester tester,
    ) async {
      // Two bars side by side reads as twice the health, which is exactly
      // wrong at the moment it matters. Armour is the share of the next hit
      // somebody else takes.
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: HealthBar(health: 100.0, armour: 0.0),
        ),
      );
      final withoutArmour = tester.getSize(find.byType(HealthBar));

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: HealthBar(health: 100.0, armour: 50.0),
        ),
      );

      expect(tester.getSize(find.byType(HealthBar)), withoutArmour);
    });
  });
}
