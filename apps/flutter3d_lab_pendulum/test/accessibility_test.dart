/// The pendulum lab for a student who does not use a mouse, does not see
/// the screen, reads at a larger text size or asked the system for less
/// motion. The panel in the scene is a texture that neither a keyboard nor
/// a screen reader reaches, so the scene itself carries its one number as a
/// slider; the swing can be paused, and starts paused when motion is
/// reduced.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_lab_pendulum/src/lab_loading_screen.dart';
import 'package:flutter3d_lab_pendulum/src/pendulum_lab_controls.dart';
import 'package:flutter3d_lab_pendulum/src/pendulum_lab_panel.dart';
import 'package:flutter_test/flutter_test.dart';

/// The controls over a stand-in for the scene, with what they change.
final class _Lab {
  final ValueNotifier<double> length = ValueNotifier<double>(1.2);
  final ValueNotifier<bool> running = ValueNotifier<bool>(true);

  Widget app({bool disableAnimations = false, double textScale = 1.0}) =>
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: disableAnimations,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              backgroundColor: const Color(0xFF14161A),
              body: PendulumLabControls(
                lengthMeters: length,
                onChangeLength: (value) => length.value = value,
                running: running,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
}

String _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return 'nothing';
  final tooltip = context.findAncestorWidgetOfExactType<Tooltip>();
  if (tooltip != null) return tooltip.message ?? 'tooltip';
  return FocusManager.instance.primaryFocus?.debugLabel ?? 'unnamed';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every control is labelled, large enough to tap, and its text '
      'has the contrast AA asks for', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_Lab().app());

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  testWidgets('the scene is a slider for the string length that a screen '
      'reader can move', (tester) async {
    final semantics = tester.ensureSemantics();
    final lab = _Lab();
    await tester.pumpWidget(lab.app());

    final slider = find.bySemanticsLabel('String length');
    final node = tester.getSemantics(slider);
    expect(node.value, '1.20 m');
    expect(node.increasedValue, '1.30 m');
    expect(node.decreasedValue, '1.10 m');

    final sliderNode = find.semantics.byLabel('String length');
    tester.semantics.increase(sliderNode);
    await tester.pump();
    expect(lab.length.value, closeTo(1.3, 1e-9));
    expect(tester.getSemantics(slider).value, '1.30 m');

    tester.semantics.decrease(sliderNode);
    await tester.pump();
    tester.semantics.decrease(sliderNode);
    await tester.pump();
    expect(lab.length.value, closeTo(1.1, 1e-9));
    semantics.dispose();
  });

  testWidgets('Tab reaches the length first and the pause button after it', (
    tester,
  ) async {
    await tester.pumpWidget(_Lab().app());

    final order = <String>[];
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(_focused());
    }
    expect(order, <String>['String length', 'Pause the swing']);
  });

  testWidgets('with the scene focused, the arrows and plus and minus change '
      'the length within its bounds, Space pauses, and a ring shows the '
      'focus', (tester) async {
    final lab = _Lab();
    await tester.pumpWidget(lab.app());
    expect(find.byKey(PendulumLabControls.focusRingKey), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.byKey(PendulumLabControls.focusRingKey), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    expect(lab.length.value, closeTo(1.4, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(lab.length.value, closeTo(1.1, 1e-9));

    lab.length.value = 3.0;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(lab.length.value, 3.0, reason: 'clamped at the upper bound');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(lab.running.value, isFalse);
    expect(find.byTooltip('Start the swing'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(lab.running.value, isTrue);
  });

  testWidgets('the pause button stops and starts the swing', (tester) async {
    final lab = _Lab();
    await tester.pumpWidget(lab.app());

    await tester.tap(find.byTooltip('Pause the swing'));
    await tester.pump();
    expect(lab.running.value, isFalse);
    await tester.tap(find.byTooltip('Start the swing'));
    await tester.pump();
    expect(lab.running.value, isTrue);
  });

  testWidgets('with reduced motion asked for, the swing starts paused', (
    tester,
  ) async {
    final lab = _Lab();
    await tester.pumpWidget(lab.app(disableAnimations: true));
    await tester.pump();

    expect(lab.running.value, isFalse);
    expect(find.byTooltip('Start the swing'), findsOneWidget);
  });

  testWidgets('without it, the swing runs', (tester) async {
    final lab = _Lab();
    await tester.pumpWidget(lab.app());
    await tester.pump();
    expect(lab.running.value, isTrue);
  });

  group('the panel in the scene', () {
    testWidgets('names its buttons and its readout', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: PendulumLabPanel(
            lengthMeters: ValueNotifier<double>(1.2),
            onChangeLength: (_) {},
          ),
        ),
      );
      expect(find.bySemanticsLabel('Shorten the string'), findsOneWidget);
      expect(find.bySemanticsLabel('Lengthen the string'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('String length.*1.20 m', dotAll: true)),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('at twice the text size still fits the texture it is drawn '
        'into', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Center(
              child: SizedBox(
                width: 360,
                height: 220,
                child: PendulumLabPanel(
                  lengthMeters: ValueNotifier<double>(1.2),
                  onChangeLength: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the loading screen', () {
    testWidgets('spins as usual', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LabLoadingScreen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('holds still when motion is reduced', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: LabLoadingScreen(),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.bySemanticsLabel(RegExp('^Loading the lab')), findsOneWidget);
      semantics.dispose();
    });
  });
}
