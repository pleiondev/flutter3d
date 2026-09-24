/// `S9`'s own HUD: fps, draw calls, triangles, bones, on the hand-over's
/// own `rgba(11, 14, 15, 0.72)` card — and `gfx-01n`'s per-pass breakdown
/// under them.
///
///     flutter test test/ui/metrics_overlay_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' show FramePass;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/metrics_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

/// The four passes an ordinary frame runs, with the sort of numbers
/// `frame_baseline_test.dart` records for them.
const List<FramePass> _fourPasses = <FramePass>[
  (
    name: 'directional shadows',
    active: true,
    micros: 410,
    gpuMicros: null,
    drawCalls: 9,
    triangles: 0,
    pipelineSwitches: 0,
  ),
  (
    name: 'scene',
    active: true,
    micros: 2300,
    gpuMicros: null,
    drawCalls: 3,
    triangles: 1186,
    pipelineSwitches: 1,
  ),
  (
    name: 'bloom',
    active: true,
    micros: 890,
    gpuMicros: null,
    drawCalls: 9,
    triangles: 0,
    pipelineSwitches: 0,
  ),
  (
    name: 'composite',
    active: true,
    micros: 150,
    gpuMicros: null,
    drawCalls: 1,
    triangles: 0,
    pipelineSwitches: 0,
  ),
];

void main() {
  testWidgets('the four numbers are drawn as given', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: MetricsOverlay(
            fps: 59.6,
            drawCalls: 12,
            triangles: 3456,
            bones: 24,
          ),
        ),
      ),
    );

    expect(find.text('60 fps'), findsOneWidget);
    expect(find.textContaining('draw calls'), findsOneWidget);
    expect(find.textContaining('triangles'), findsOneWidget);
    expect(find.textContaining('bones'), findsOneWidget);
    expect(find.text('24 bones'), findsOneWidget);
  });

  testWidgets('the card paints the hand-over\'s own background', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: MetricsOverlay(fps: 60, drawCalls: 1, triangles: 1, bones: 0),
        ),
      ),
    );

    final DecoratedBox box = tester.widget(find.byType(DecoratedBox));
    final BoxDecoration decoration = box.decoration as BoxDecoration;
    expect(decoration.color, kMetricsOverlayBackground);
  });

  testWidgets('the panel shows four passes separately', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MetricsOverlay(
            fps: 60,
            drawCalls: 22,
            triangles: 1186,
            bones: 0,
            passes: _fourPasses,
          ),
        ),
      ),
    );

    // `gfx-01n`'s own acceptance sentence. Each pass by name, with its own
    // draws beside it — the whole point being that "the frame is up nine
    // draws" and "the shadow map is up nine draws" are different sentences
    // and only the second one is actionable.
    for (final FramePass pass in _fourPasses) {
      expect(
        find.textContaining(pass.name),
        findsOneWidget,
        reason: 'the ${pass.name} pass is not on the card',
      );
    }
    // Two passes cost nine draws each — the shadow map and the bloom ladder
    // — and the card says so twice rather than summing them into a total
    // that names neither.
    expect(find.textContaining('9 draws'), findsNWidgets(2));
    // One line per pass, each carrying its own time, draws and triangles.
    // Matched on the separator rather than on "tri", which the totals line's
    // own "triangles" also contains.
    expect(find.textContaining('draws · '), findsNWidgets(_fourPasses.length));
    expect(find.text('Frame passes'), findsOneWidget);
  });

  testWidgets('with no passes the card is the four numbers it was', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MetricsOverlay(fps: 60, drawCalls: 1, triangles: 1, bones: 0),
        ),
      ),
    );

    // A heading over nothing is worse than no heading: a renderer that
    // reported no passes would otherwise leave an empty section on a card
    // that sits over the picture.
    expect(find.text('Frame passes'), findsNothing);
  });
}
