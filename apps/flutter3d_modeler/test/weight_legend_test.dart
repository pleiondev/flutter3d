/// `WeightLegend`'s own shape: a 140×8 bar between "0" and "1", pinned to
/// the top-right corner of whatever `Stack` it sits in.
///
///     flutter test test/weight_legend_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/weight_legend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: const Scaffold(body: Stack(children: <Widget>[WeightLegend()])),
    ),
  );

  testWidgets('shows the 0..1 endpoints around a 140x8 bar', (tester) async {
    await pump(tester);

    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    final bar = find.descendant(
      of: find.byType(WeightLegend),
      matching: find.byType(Container),
    );
    final size = tester.getSize(bar);
    expect(size.width, kWeightLegendWidth);
    expect(size.height, kWeightLegendHeight);
  });

  testWidgets('is pinned to the top-right corner', (tester) async {
    await pump(tester);

    final positioned = tester.widget<Positioned>(
      find.descendant(
        of: find.byType(WeightLegend),
        matching: find.byType(Positioned),
      ),
    );
    expect(positioned.top, 12);
    expect(positioned.right, 12);
  });

  testWidgets('the bar reads the five stops, in order', (tester) async {
    await pump(tester);

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(WeightLegend),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, kWeightLegendColors);
  });
}
