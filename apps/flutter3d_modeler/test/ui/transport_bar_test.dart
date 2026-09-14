/// `S2`'s own `TransportBar`: the play/pause button, the frame number, the
/// `Keys`/`Curves` toggle, the loop switch and the speed control.
///
/// The play button's own reference picture is `transport_bar_golden_test
/// .dart`, kept apart from the interaction tests here the same way
/// `timeline_golden_test.dart` sits apart from `timeline_panel_test.dart`.
///
///     flutter test test/ui/transport_bar_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' show AnimationWrap;
import 'package:flutter3d_modeler/src/timeline_playback.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/transport_bar.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  Playback playback = const Playback(),
  int frame = 0,
  TimelineEditMode editMode = TimelineEditMode.keys,
  ValueChanged<TimelineEditMode>? onEditMode,
  VoidCallback? onPlayPause,
  ValueChanged<bool>? onLoopChanged,
  ValueChanged<double>? onSpeedChanged,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: SizedBox(
        height: ModelerMetrics.transport,
        child: TransportBar(
          playback: playback,
          frame: frame,
          editMode: editMode,
          onEditMode: onEditMode ?? (_) {},
          onPlayPause: onPlayPause ?? () {},
          onLoopChanged: onLoopChanged,
          onSpeedChanged: onSpeedChanged,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the frame number is drawn as given', (tester) async {
    await _pump(tester, frame: 42);

    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('tapping the play button calls onPlayPause', (tester) async {
    var pressed = 0;
    await _pump(tester, onPlayPause: () => pressed++);

    await tester.tap(find.byKey(kTransportBarCanvasKey));
    await tester.pump();

    expect(pressed, 1);
  });

  testWidgets('the Keys/Curves toggle reports the segment pressed', (
    tester,
  ) async {
    TimelineEditMode? picked;
    await _pump(
      tester,
      editMode: TimelineEditMode.keys,
      onEditMode: (TimelineEditMode m) => picked = m,
    );

    await tester.tap(find.text('Curves'));
    await tester.pump();

    expect(picked, TimelineEditMode.curves);
  });

  testWidgets(
    'the loop toggle flips AnimationWrap.loop to AnimationWrap.once',
    (tester) async {
      bool? looping;
      await _pump(
        tester,
        playback: const Playback(wrap: AnimationWrap.loop),
        onLoopChanged: (bool value) => looping = value,
      );

      await tester.tap(find.byTooltip('Loop'));
      await tester.pump();

      expect(looping, isFalse);
    },
  );

  testWidgets('a null onLoopChanged disables the loop control', (tester) async {
    await _pump(tester);

    final IconButton button = tester.widget(
      find.byWidgetPredicate(
        (Widget w) => w is IconButton && w.tooltip == 'Loop',
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('picking a speed from the menu reports it', (tester) async {
    double? picked;
    await _pump(
      tester,
      playback: const Playback(speed: 1.0),
      onSpeedChanged: (double s) => picked = s,
    );

    await tester.tap(find.text('1.0x'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.0x').last);
    await tester.pumpAndSettle();

    expect(picked, 2.0);
  });
}
