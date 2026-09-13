import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/playtest_heatmap_view.dart';
import 'package:flutter3d_editor/src/playtest_report.dart';
import 'package:flutter3d_editor/src/playtest_report_screen.dart';
import 'package:flutter_test/flutter_test.dart';

PlaytestReport _report() => const PlaytestReport(
  cellSize: 1.0,
  cells: <HeatmapCell>[HeatmapCell(x: 0, z: 0, samples: 4, runs: 2)],
  deaths: <DeathPoint>[DeathPoint(seed: 5, step: 120, x: 0.5, z: 0.5)],
  outcomes: <String, int>{'died': 1, 'exited': 2},
);

void main() {
  testWidgets('with no report open, the screen says so rather than showing '
      'an empty canvas', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PlaytestReportScreen()));
    expect(find.text('No report open.'), findsOneWidget);
  });

  testWidgets('a report handed in shows its own run count and outcomes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PlaytestReportScreen(initialReport: _report())),
    );
    expect(find.textContaining('3 runs'), findsOneWidget);
    expect(find.textContaining('died: 1'), findsOneWidget);
  });

  testWidgets('tapping a death opens a dialog naming its run and step', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PlaytestReportScreen(initialReport: _report())),
    );

    final view = tester.widget<PlaytestHeatmapView>(
      find.byType(PlaytestHeatmapView),
    );
    final origin = tester.getTopLeft(find.byType(PlaytestHeatmapView));
    final size = tester.getSize(find.byType(PlaytestHeatmapView));
    final layout = HeatmapLayout(report: view.report, size: size);
    await tester.tapAt(origin + layout.toScreen(0.5, 0.5));
    await tester.pumpAndSettle();

    expect(find.text('A death, from ai-01'), findsOneWidget);
    expect(find.textContaining('seed 5'), findsOneWidget);
    expect(find.textContaining('step 120'), findsOneWidget);
  });
}
