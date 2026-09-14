/// `S2`'s own golden: `transport-bar`, the play button's own reference —
/// screen 07's own `⌀36 on primaryContainer`.
///
///     flutter test test/transport_bar_golden_test.dart
///     flutter test test/transport_bar_golden_test.dart --update-goldens
///
/// **The captured region is [kTransportBarCanvasKey]'s own `RepaintBoundary`,
/// not the whole bar.** `transport_bar.dart`'s own class comment says why:
/// the button is drawn entirely in vectors so this golden stays independent
/// of whichever font the machine running the test has installed, the same
/// promise `timeline_golden_test.dart` already keeps for the timeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/timeline_playback.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/transport_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the paused play button matches its reference', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: modelerTheme(),
        home: Scaffold(
          body: Container(
            color: ModelerColors.dark.viewport,
            padding: const EdgeInsets.all(8),
            child: TransportBar(
              playback: const Playback(),
              frame: 0,
              editMode: TimelineEditMode.keys,
              onEditMode: (_) {},
              onPlayPause: () {},
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(kTransportBarCanvasKey),
      matchesGoldenFile('goldens/transport-bar.png'),
    );
  });
}
