/// The HUD on a stereo surface: built once, redrawn from what it listens to.
///
///     flutter test test/stereo_hud_panel_test.dart
///
/// A `WidgetSurface`'s child is fixed when it is made, so the panel has to
/// tick itself; this proves it reads the listenable rather than a value fixed
/// at construction.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game_ui/hud.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty until there is a reading, then the reading', (
    WidgetTester tester,
  ) async {
    final reading = ValueNotifier<int?>(null);
    addTearDown(reading.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StereoHudPanel<int>(
          reading: reading,
          builder: (BuildContext context, int value) => Text('speed $value'),
        ),
      ),
    );
    // Mutation: build the HUD for a null reading — a builder handed nothing.
    expect(find.textContaining('speed'), findsNothing);

    reading.value = 12;
    await tester.pump();
    expect(find.text('speed 12'), findsOneWidget);

    // Mutation: read `reading.value` once in `build` without listening —
    // the panel stays at 12.
    reading.value = 13;
    await tester.pump();
    expect(find.text('speed 13'), findsOneWidget);
  });

  testWidgets('what the builder reads besides the reading is read fresh', (
    WidgetTester tester,
  ) async {
    final reading = ValueNotifier<int?>(1);
    addTearDown(reading.dispose);
    var message = 'first';
    await tester.pumpWidget(
      MaterialApp(
        home: StereoHudPanel<int>(
          reading: reading,
          builder: (BuildContext context, int value) => Text('$value $message'),
        ),
      ),
    );
    expect(find.text('1 first'), findsOneWidget);
    message = 'second';
    reading.value = 2;
    await tester.pump();
    expect(find.text('2 second'), findsOneWidget);
  });
}
