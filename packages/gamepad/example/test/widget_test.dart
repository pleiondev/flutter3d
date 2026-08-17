/// The acceptance tool, checked to the extent a machine can check it.
///
///     flutter test
///
/// It cannot check the part that matters — whether a real stick feels right is
/// why this application exists — but it can check that the screen is honest about
/// what it was handed. A tool that showed a stale value, or said "no controller"
/// while one was connected, would send a person looking for a bug in the wrong
/// package.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepad/gamepad.dart';
import 'package:gamepad_example/main.dart';

/// A pad that does whatever the test says.
final class FakePad extends GamepadPlatform {
  final PadSnapshot state = PadSnapshot();
  final StreamController<PadConnection> _connections =
      StreamController<PadConnection>.broadcast();

  @override
  bool get isSupported => true;

  @override
  Stream<PadConnection> get connectionChanges => _connections.stream;

  @override
  void read(PadSnapshot out) => out.copyFrom(state);

  @override
  Future<void> dispose() async => _connections.close();
}

void main() {
  testWidgets('says there is no controller when there is none', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      PadScreen(pad: Gamepad(platform: FakePad())).wrapped,
    );
    await tester.pump();

    expect(find.text('no controller'), findsOneWidget);
  });

  testWidgets('and shows a stick where the thumb is', (
    WidgetTester tester,
  ) async {
    // Half over, which is the first acceptance item: a stick pushed halfway asks
    // for half. Read through the dead zone, so the number shown is the one the
    // game will act on rather than the raw one.
    final fake = FakePad()
      ..state.connected = true
      ..state.setAxis(PadAxis.leftStickX, 1.0);
    await tester.pumpWidget(
      PadScreen(
        pad: Gamepad(
          platform: fake,
          deadzone: const Deadzone(stick: 0.0),
        ),
      ).wrapped,
    );
    await tester.pump();

    expect(find.text('a controller is connected'), findsOneWidget);
    expect(find.text('1.00, 0.00'), findsOneWidget);
  });

  testWidgets('and a trigger as a proportion, not a light', (
    WidgetTester tester,
  ) async {
    final fake = FakePad()
      ..state.connected = true
      ..state.setAxis(PadAxis.triggerRight, 0.5);
    await tester.pumpWidget(
      PadScreen(
        pad: Gamepad(platform: fake, deadzone: const Deadzone(trigger: 0.0)),
      ).wrapped,
    );
    await tester.pump();

    expect(find.text('0.50'), findsWidgets);
  });

  testWidgets('and names a button by what a rebinding would write down', (
    WidgetTester tester,
  ) async {
    // `pad:face.south`, never `A`: checking that the identifier belongs to the
    // button under the thumb is itself an acceptance item, and it cannot be
    // checked against a label the screen invented.
    final fake = FakePad()..state.connected = true;
    await tester.pumpWidget(
      PadScreen(pad: Gamepad(platform: fake)).wrapped,
    );
    await tester.pump();

    expect(find.text('face.south'), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  testWidgets('and follows the pad from frame to frame', (
    WidgetTester tester,
  ) async {
    // The whole point of the screen is latency, so a value that only arrived once
    // would be worse than no screen at all.
    final fake = FakePad()..state.connected = true;
    await tester.pumpWidget(
      PadScreen(
        pad: Gamepad(platform: fake, deadzone: const Deadzone(stick: 0.0)),
      ).wrapped,
    );
    await tester.pump();
    expect(find.text('0.00, 0.00'), findsWidgets);

    fake.state.setAxis(PadAxis.leftStickY, -1.0);
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('0.00, -1.00'), findsOneWidget);
  });
}

extension on PadScreen {
  /// The screen inside the application that hosts it, so a `Slider` has the
  /// ancestors it needs.
  Widget get wrapped => GamepadExampleApp(home: this);
}
