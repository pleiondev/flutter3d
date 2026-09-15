/// Screen 19's own chrome: the close button pops the route, the metrics
/// card and budget bars are on screen, the transport's own play button
/// reaches [GamePreviewScreen.onPlayPause], and "Show wireframe" is a
/// disabled toggle with a reason rather than a control wired to nothing.
///
///     flutter test test/ui/game_preview_screen_test.dart
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/timeline_playback.dart';
import 'package:flutter3d_modeler/src/ui/budget_bars.dart';
import 'package:flutter3d_modeler/src/ui/game_preview_screen.dart';
import 'package:flutter3d_modeler/src/ui/metrics_overlay.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/transport_bar.dart';
import 'package:flutter_test/flutter_test.dart';

Renderer _testRenderer() {
  final it = cpuTestDevice();
  return Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
}

/// A fixed number of frames rather than `pumpAndSettle` — this screen keeps
/// its own `Ticker` running for as long as it is mounted, and
/// `pumpAndSettle` waits for *no* frame to be scheduled at all, which never
/// happens here — `autorig_dialog_test.dart`'s own `_settle`.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  // Past `MaterialPageRoute`'s own 300ms transition, not merely up to it —
  // this screen's own `Ticker` keeps a frame scheduled indefinitely, so
  // `pumpAndSettle` never returns and a pump landing exactly on the
  // transition's own duration is one frame short of it finishing.
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _open(WidgetTester tester, {VoidCallback? onPlayPause}) async {
  final Renderer renderer = _testRenderer();
  final ModelerStage stage = ModelerStage.build(device: renderer.device);
  stage.frameSubject();
  final ModelProject project = const ModelProject();

  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () => showGamePreviewScreen(
              context,
              renderer: renderer,
              stage: stage,
              project: project,
              readiness: ExportReadiness.check(project),
              baseSettings: const RenderSettings(),
              playback: const Playback(),
              frame: ValueNotifier<int>(3),
              onPlayPause: onPlayPause ?? () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
}

void main() {
  Future<void> withScreen(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    tester.view.physicalSize = const ui.Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await body();
  }

  testWidgets('opens as a full-screen route, over the metrics card, budget '
      'bars and transport', (tester) async {
    await withScreen(tester, () async {
      await _open(tester);

      expect(find.byType(MetricsOverlay), findsOneWidget);
      expect(find.byType(BudgetBars), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: 'the frame it opened at');
    });
  });

  testWidgets('"Show wireframe" is a disabled toggle with a reason', (
    tester,
  ) async {
    await withScreen(tester, () async {
      await _open(tester);

      final SwitchListTile tile = tester.widget(find.byType(SwitchListTile));
      expect(tile.value, isFalse);
      expect(tile.onChanged, isNull);
      expect(find.text('Show wireframe'), findsOneWidget);
      expect(find.textContaining('not built'), findsOneWidget);
    });
  });

  testWidgets('the compact transport bar\'s play button reaches onPlayPause', (
    tester,
  ) async {
    await withScreen(tester, () async {
      var pressed = 0;
      await _open(tester, onPlayPause: () => pressed++);

      await tester.tap(find.byKey(kTransportBarCompactCanvasKey));
      await _settle(tester);

      expect(pressed, 1);
    });
  });

  testWidgets('closing pops back to whatever opened it', (tester) async {
    await withScreen(tester, () async {
      await _open(tester);
      expect(find.text('Preview'), findsOneWidget);

      await tester.tap(find.byTooltip('Close preview'));
      await _settle(tester);

      expect(find.text('Preview'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });
}
