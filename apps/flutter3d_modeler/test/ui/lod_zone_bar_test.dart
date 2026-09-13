/// `LodZoneBar`: the 96-tall strip with zones and a draggable marker per
/// level — `pro-lod-04`'s own row, and the literal "widget test on the
/// slider" its acceptance asks for.
///
///     flutter test test/ui/lod_zone_bar_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/lod_zone_bar.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

const double _barWidth = 300;

const List<LodSpec> _threeLevels = <LodSpec>[
  LodSpec(ratio: 1.0, maxScreenFraction: 1.0),
  LodSpec(ratio: 0.5, maxScreenFraction: 0.4),
  LodSpec(ratio: 0.15, maxScreenFraction: 0.1),
];

Future<void> show(
  WidgetTester tester, {
  List<LodSpec> lods = _threeLevels,
  required void Function(int lodIndex, double maxScreenFraction)
  onThresholdChanged,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _barWidth,
          child: LodZoneBar(lods: lods, onThresholdChanged: onThresholdChanged),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('is exactly 96 tall — the plan\'s own row states the number', (
    WidgetTester tester,
  ) async {
    await show(tester, onThresholdChanged: (_, _) {});

    final Size size = tester.getSize(find.byType(LodZoneBar));
    expect(size.height, LodZoneBar.height);
    expect(LodZoneBar.height, 96);
  });

  testWidgets('draws a marker per level of detail', (
    WidgetTester tester,
  ) async {
    await show(tester, onThresholdChanged: (_, _) {});

    expect(
      find.descendant(
        of: find.byType(LodZoneBar),
        matching: find.byType(GestureDetector),
      ),
      findsNWidgets(_threeLevels.length),
    );
  });

  testWidgets(
    'dragging a marker reports the right lodIndex and a plausible new '
    'fraction',
    (WidgetTester tester) async {
      final List<(int, double)> reported = <(int, double)>[];
      await show(
        tester,
        onThresholdChanged: (int lodIndex, double fraction) =>
            reported.add((lodIndex, fraction)),
      );

      // Level 1 starts at maxScreenFraction 0.4, which on a 300-wide bar
      // is x = 120. Dragging it right by 60 logical pixels should move it
      // toward roughly 0.4 + 60/300 = 0.6.
      final Finder marker = find.byKey(const ValueKey<int>(1));
      expect(marker, findsOneWidget);

      await tester.drag(marker, const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(reported, isNotEmpty);
      // Every report during the drag has to name the marker that was
      // actually dragged.
      expect(reported.every(((int, double) r) => r.$1 == 1), isTrue);

      final double last = reported.last.$2;
      expect(last, greaterThan(0.4));
      expect(last, closeTo(0.6, 0.05));
      expect(last, inInclusiveRange(0.0, 1.0));
    },
  );

  testWidgets('dragging one marker never reports another lodIndex', (
    WidgetTester tester,
  ) async {
    final List<int> lodIndexesReported = <int>[];
    await show(
      tester,
      onThresholdChanged: (int lodIndex, double fraction) =>
          lodIndexesReported.add(lodIndex),
    );

    await tester.drag(find.byKey(const ValueKey<int>(0)), const Offset(-20, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey<int>(2)), const Offset(20, 0));
    await tester.pumpAndSettle();

    expect(lodIndexesReported, isNotEmpty);
    expect(lodIndexesReported.toSet(), <int>{0, 2});
  });

  testWidgets('a marker never reports past the ends of the strip', (
    WidgetTester tester,
  ) async {
    final List<double> fractions = <double>[];
    await show(
      tester,
      onThresholdChanged: (int lodIndex, double fraction) =>
          fractions.add(fraction),
    );

    // Level 0 starts at maxScreenFraction 1.0 (the right edge); dragging it
    // further right must clamp rather than overshoot past 1.0.
    await tester.drag(find.byKey(const ValueKey<int>(0)), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(fractions, isNotEmpty);
    expect(fractions.every((double f) => f <= 1.0), isTrue);
    expect(fractions.every((double f) => f >= 0.0), isTrue);
  });
}
