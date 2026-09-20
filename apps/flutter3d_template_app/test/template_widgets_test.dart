/// `tpl-04`'s three widgets, tested as plain Flutter widgets — no
/// `WidgetSurface`, no device, no level. Each one's own controller is the
/// thing this asserts against, the same split `template_widgets.dart`'s own
/// doc comment names: a test can drive a controller and read its state
/// without a widget in between, and it can also drive the widget itself to
/// prove the two actually agree.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_template_app/src/template_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ViewerTourController', () {
    test('starts on a placeholder before setCaptions', () {
      final tour = ViewerTourController();
      expect(tour.captions.value, <String>['…']);
      expect(tour.index.value, 0);
    });

    test('setCaptions replaces the list and resets to the first step', () {
      final tour = ViewerTourController()..index.value = 2;
      tour.setCaptions(<String>['a', 'b', 'c']);
      expect(tour.captions.value, <String>['a', 'b', 'c']);
      expect(tour.index.value, 0);
    });

    test('next and previous wrap around', () {
      final tour = ViewerTourController()..setCaptions(<String>['a', 'b', 'c']);
      tour.previous();
      expect(tour.index.value, 2, reason: 'wraps backward from the first step');
      tour.next();
      tour.next();
      expect(tour.index.value, 1, reason: 'wraps forward past the last step');
    });
  });

  testWidgets('the viewer widget shows the current caption and steps on tap', (
    tester,
  ) async {
    final tour = ViewerTourController()
      ..setCaptions(<String>['Front', 'Side', 'Top']);
    final registry = templateWidgetRegistry(
      viewerTour: tour,
      configurator: ConfiguratorController(),
      twinReading: ValueNotifier<Object?>(null),
    );

    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: registry['viewer-caption']!)),
    );

    expect(find.text('Front'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text('Side'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(find.text('Front'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(
      find.text('Top'),
      findsOneWidget,
      reason: 'wrapped backward past the first step',
    );
  });

  group('ConfiguratorController', () {
    test('starts on the first option and cycles through all three', () {
      final controller = ConfiguratorController();
      expect(controller.current, ('Red', 199.0, 'product-red'));
      controller.cycle();
      expect(controller.current, ('Blue', 219.0, 'product-blue'));
      controller.cycle();
      expect(controller.current, ('Green', 209.0, 'product-green'));
      controller.cycle();
      expect(controller.current, (
        'Red',
        199.0,
        'product-red',
      ), reason: 'wraps around');
    });
  });

  testWidgets('tapping the configurator panel cycles its own controller', (
    tester,
  ) async {
    final configurator = ConfiguratorController();
    final registry = templateWidgetRegistry(
      viewerTour: ViewerTourController(),
      configurator: configurator,
      twinReading: ValueNotifier<Object?>(null),
    );

    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: registry['configurator-panel']!)),
    );

    expect(find.text('Red'), findsOneWidget);
    await tester.tap(find.text('Red'));
    await tester.pump();
    expect(find.text('Blue'), findsOneWidget);
    expect(configurator.current.$1, 'Blue');
  });

  testWidgets('the twin dashboard shows the live reading, not a placeholder '
      'once one has come in', (tester) async {
    final reading = ValueNotifier<Object?>(null);
    final registry = templateWidgetRegistry(
      viewerTour: ViewerTourController(),
      configurator: ConfiguratorController(),
      twinReading: reading,
    );

    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: registry['twin-dashboard']!)),
    );
    expect(find.text('— °C'), findsOneWidget);

    reading.value = 63.4;
    await tester.pump();
    expect(find.text('63.4 °C'), findsOneWidget);

    reading.value = 71.28;
    await tester.pump();
    expect(find.text('71.3 °C'), findsOneWidget);
  });
}
