/// `SimulationCacheStrip`: the visible half of a baked `SimulationCache` —
/// `pro-sim-03`'s own "полоса кэша".
///
///     flutter test test/ui/simulation_cache_strip_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/simulation_cache_strip.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(
  WidgetTester tester, {
  required int bakedFrameCount,
  required int targetFrameCount,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SimulationCacheStrip(
        bakedFrameCount: bakedFrameCount,
        targetFrameCount: targetFrameCount,
      ),
    ),
  ),
);

void main() {
  testWidgets('reports 0% for a bake that has not started', (
    WidgetTester tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(tester, bakedFrameCount: 0, targetFrameCount: 120);

    final semantics = tester.getSemantics(find.byType(SimulationCacheStrip));
    expect(semantics.label, contains('0 of 120'));
    expect(semantics.value, '0%');
    handle.dispose();
  });

  testWidgets('reports the exact fraction baked so far', (
    WidgetTester tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(tester, bakedFrameCount: 50, targetFrameCount: 120);

    final semantics = tester.getSemantics(find.byType(SimulationCacheStrip));
    // Mutation: swap bakedFrameCount and targetFrameCount, or drop the
    // clamp — 50/120 rounds to 42%, not 100% and not 240%.
    expect(semantics.label, contains('50 of 120'));
    expect(semantics.value, '42%');
    handle.dispose();
  });

  testWidgets('reports 100% once every target frame is cached, never past it', (
    WidgetTester tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(tester, bakedFrameCount: 120, targetFrameCount: 120);
    expect(
      tester.getSemantics(find.byType(SimulationCacheStrip)).value,
      '100%',
    );

    // A cache holding more frames than the target still reads as fully
    // covered, not over 100%.
    await show(tester, bakedFrameCount: 130, targetFrameCount: 120);
    expect(
      tester.getSemantics(find.byType(SimulationCacheStrip)).value,
      '100%',
    );
    handle.dispose();
  });

  testWidgets('a zero target with nothing baked reads as 0%, not a crash', (
    WidgetTester tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(tester, bakedFrameCount: 0, targetFrameCount: 0);
    expect(tester.getSemantics(find.byType(SimulationCacheStrip)).value, '0%');
    handle.dispose();
  });
}
