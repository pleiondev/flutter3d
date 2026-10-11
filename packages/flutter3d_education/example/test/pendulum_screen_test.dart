/// The pendulum laboratory's screen on a device that draws nothing, its
/// simulation in an isolate: nothing swings until the clock is moved, and a
/// step by hand reaches the panel through the probe.
///
///     flutter test test/pendulum_screen_test.dart
@TestOn('vm')
library;

import 'package:chemlab/pendulum_main.dart';
import 'package:chemlab/src/pendulum_lab.dart';
import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter_test/flutter_test.dart';

/// Shows nothing: there is no backend to present a fake's frame.
Widget _noPresenter(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.fill,
  FilterQuality quality = FilterQuality.none,
}) => const SizedBox.expand();

/// Lets real time pass — what an isolate's messages need — and the test's
/// own clock catch up, by turns, until [done] or [tries] turns are over.
Future<void> _settle(
  WidgetTester tester,
  bool Function() done, {
  int tries = 200,
}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(microseconds: 16667));
  }
}

void main() {
  testWidgets('a step by hand swings the pendulum in its isolate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PendulumScreen(
          device: DeviceSettings(
            device: FakeBackend(),
            presenter: _noPresenter,
          ),
        ),
      ),
    );
    await _settle(tester, () => find.text('Step').evaluate().isNotEmpty);
    await _settle(tester, () => false, tries: 10);
    // The clock has not been moved: the laboratory has not stepped.
    expect(find.text('Angle: —'), findsOneWidget);
    expect(find.text('Profile: accurate'), findsOneWidget);

    await tester.tap(find.text('Step'));
    await _settle(
      tester,
      () => find.textContaining('Angle: 0.').evaluate().isNotEmpty,
    );
    final shown = tester.widget<Text>(find.textContaining('Angle: 0.')).data!;
    final angle = double.parse(shown.split(' ')[1]);
    expect(angle, inExclusiveRange(0.099, PendulumLab.releasedAt));

    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester, () => false, tries: 5);
  });
}
