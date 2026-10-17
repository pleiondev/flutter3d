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

  group('N7: players\' runs from a telemetry server', () {
    // What `cloud/server`'s `/api/telemetry/heatmap` answers: the playtest
    // report's keys, with a run id under `seed`.
    const String heatmap =
        '{"cellSize":1.0,"cells":[{"x":0,"z":0,"samples":6,"runs":3}],'
        '"deaths":[{"seed":41,"step":300,"x":0.5,"z":0.5}],'
        '"outcomes":{"won":2,"lost":1,"unfinished":0},'
        '"level":"cafe0001","says":"3 runs of cafe0001"}';

    Future<void> fetch(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.cloud_download));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fetch'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks for the open level by its digest, and draws what the '
        'server binned', (tester) async {
      // Mutation: asking for the level by path, or not at all, draws
      // somebody else's level.
      Uri? asked;
      await tester.pumpWidget(
        MaterialApp(
          home: PlaytestReportScreen(
            levelHash: 'cafe0001',
            get: (url) async {
              asked = url;
              return (status: 200, body: heatmap);
            },
          ),
        ),
      );
      await fetch(tester);

      expect(asked!.path, '/api/telemetry/heatmap');
      expect(asked!.queryParameters['level'], 'cafe0001');
      expect(find.textContaining('Players: 3 runs'), findsOneWidget);
      expect(find.byType(PlaytestHeatmapView), findsOneWidget);
    });

    testWidgets('a lost run is named as a run on the server, not a seed to '
        'play again', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlaytestReportScreen(
            levelHash: 'cafe0001',
            get: (url) async => (status: 200, body: heatmap),
          ),
        ),
      );
      await fetch(tester);

      final view = tester.widget<PlaytestHeatmapView>(
        find.byType(PlaytestHeatmapView),
      );
      final origin = tester.getTopLeft(find.byType(PlaytestHeatmapView));
      final size = tester.getSize(find.byType(PlaytestHeatmapView));
      final layout = HeatmapLayout(report: view.report, size: size);
      await tester.tapAt(origin + layout.toScreen(0.5, 0.5));
      await tester.pumpAndSettle();

      expect(find.text('A run lost, from telemetry'), findsOneWidget);
      expect(find.textContaining('run 41 on the server'), findsOneWidget);
    });

    testWidgets('a server that refuses is quoted, and nothing is drawn', (
      tester,
    ) async {
      // Mutation: drawing an empty report on a refusal looks like a level
      // nobody struggled with.
      await tester.pumpWidget(
        MaterialApp(
          home: PlaytestReportScreen(
            levelHash: 'cafe0001',
            get: (url) async => (
              status: 400,
              body: '{"says":"name the level: ?level=<its digest>"}',
            ),
          ),
        ),
      );
      await fetch(tester);

      expect(find.text('No report open.'), findsOneWidget);
      expect(find.text('name the level: ?level=<its digest>'), findsOneWidget);
    });
  });
}
