/// `S9`'s own HUD: fps, draw calls, triangles, bones, on the hand-over's
/// own `rgba(11, 14, 15, 0.72)` card.
///
///     flutter test test/ui/metrics_overlay_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/metrics_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
