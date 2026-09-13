import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/playtest_heatmap_view.dart';
import 'package:flutter3d_editor/src/playtest_report.dart';
import 'package:flutter_test/flutter_test.dart';

PlaytestReport _report() => const PlaytestReport(
  cellSize: 1.0,
  cells: <HeatmapCell>[
    HeatmapCell(x: 0, z: 0, samples: 4, runs: 2),
    HeatmapCell(x: 3, z: 0, samples: 1, runs: 1),
  ],
  deaths: <DeathPoint>[
    DeathPoint(seed: 5, step: 120, x: 3.5, z: 0.5),
  ],
  outcomes: <String, int>{'died': 1, 'exited': 1},
);

void main() {
  group('HeatmapLayout', () {
    test('a death point maps back to the same screen point it was placed at', () {
      final layout = HeatmapLayout(
        report: _report(),
        size: const Size(400, 400),
      );
      final at = layout.toScreen(3.5, 0.5);
      final hit = layout.hitTest(at);
      expect(hit, isNotNull);
      expect(hit!.seed, 5);
    });

    test('a tap far from every death finds nothing', () {
      final layout = HeatmapLayout(
        report: _report(),
        size: const Size(400, 400),
      );
      expect(layout.hitTest(const Offset(1.0, 1.0)), isNull);
    });

    test('an empty report still produces a usable layout', () {
      const empty = PlaytestReport(
        cellSize: 1.0,
        cells: <HeatmapCell>[],
        deaths: <DeathPoint>[],
        outcomes: <String, int>{},
      );
      final layout = HeatmapLayout(report: empty, size: const Size(200, 200));
      expect(layout.hitTest(const Offset(100, 100)), isNull);
    });
  });

  group('PlaytestHeatmapView', () {
    testWidgets('tapping a death marker calls onDeathTap with that death', (
      tester,
    ) async {
      DeathPoint? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 400,
            child: PlaytestHeatmapView(
              report: _report(),
              onDeathTap: (death) => tapped = death,
            ),
          ),
        ),
      );

      final origin = tester.getTopLeft(find.byType(PlaytestHeatmapView));
      final size = tester.getSize(find.byType(PlaytestHeatmapView));
      final layout = HeatmapLayout(report: _report(), size: size);
      await tester.tapAt(origin + layout.toScreen(3.5, 0.5));
      await tester.pumpAndSettle();

      expect(tapped, isNotNull);
      expect(tapped!.seed, 5);
      expect(tapped!.step, 120);
    });

    testWidgets('tapping empty ground calls nothing', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 400,
            child: PlaytestHeatmapView(
              report: _report(),
              onDeathTap: (_) => tapped = true,
            ),
          ),
        ),
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(tapped, isFalse);
    });
  });
}
