/// `anim-07`'s own `TimelinePanel`: rows, labels, seeking, and the drag
/// that turns a diamond move into a real `MoveKeys`.
///
///     flutter test test/ui/timeline_panel_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/timeline_panel.dart';
import 'package:flutter_test/flutter_test.dart';

AnimationTrack _track({
  required int nodeIndex,
  required AnimationPath path,
  required List<double> times,
}) => AnimationTrack(
  nodeIndex: nodeIndex,
  path: path,
  interpolation: AnimationInterpolation.linear,
  times: Float32List.fromList(times),
  values: Float32List(times.length * path.componentCount),
  componentCount: path.componentCount,
);

/// Two rows: a translation track on object 1 with keys at 0 and 1 second,
/// and a rotation track on object 2 with one key at 0.5 seconds.
ProjectClip _twoRowClip() => ProjectClip(
  name: 'walk',
  tracks: <ProjectTrack>[
    ProjectTrack(
      objectId: 1,
      track: _track(
        nodeIndex: 0,
        path: AnimationPath.translation,
        times: <double>[0.0, 1.0],
      ),
    ),
    ProjectTrack(
      objectId: 2,
      track: _track(
        nodeIndex: 1,
        path: AnimationPath.rotation,
        times: <double>[0.5],
      ),
    ),
  ],
);

/// A 400×200 panel: the label column at [labelWidth] and the timeline canvas
/// filling the rest, both at the test's own fixed `pixelsPerSecond` so every
/// coordinate this file computes by hand stays exact.
Future<void> _pump(
  WidgetTester tester, {
  required ProjectClip clip,
  double time = 0.0,
  int clipIndex = 0,
  double pixelsPerSecond = 100.0,
  double labelWidth = 120.0,
  int? selectedTrack,
  int? selectedKey,
  ValueChanged<MoveKeys>? onMoveKeys,
  ValueChanged<double>? onSeek,
  void Function(int, int, {bool add})? onSelectKey,
  void Function(int, double)? onSetKey,
  Set<(int, int)> selectedKeys = const <(int, int)>{},
  bool frameSnap = false,
  ValueChanged<double>? onZoom,
  Size window = const Size(800, 600),
}) {
  tester.view
    ..physicalSize = window
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 200,
          child: TimelinePanel(
            clipIndex: clipIndex,
            clip: clip,
            time: time,
            pixelsPerSecond: pixelsPerSecond,
            labelWidth: labelWidth,
            selectedTrack: selectedTrack,
            selectedKey: selectedKey,
            onMoveKeys: onMoveKeys,
            onSeek: onSeek,
            onSelectKey: onSelectKey,
            onSetKey: onSetKey,
            selectedKeys: selectedKeys,
            frameSnap: frameSnap,
            onZoom: onZoom,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('each track gets a row labelled by its own path and object', (
    tester,
  ) async {
    await _pump(tester, clip: _twoRowClip());

    expect(find.text('Translation · obj 1'), findsOneWidget);
    expect(find.text('Rotation · obj 2'), findsOneWidget);
  });

  testWidgets('an empty clip draws no rows and does not crash', (tester) async {
    await _pump(tester, clip: const ProjectClip(tracks: <ProjectTrack>[]));

    expect(find.byType(TimelinePanel), findsOneWidget);
  });

  testWidgets('tapping the ruler reports the time it names', (tester) async {
    double? seeked;
    await _pump(tester, clip: _twoRowClip(), onSeek: (double t) => seeked = t);

    // The ruler sits to the right of the 120-wide label column, at the top
    // 24 pixels of the panel. Local x = 50 on the ruler is time 0.5 at 100
    // pixels a second.
    await tester.tapAt(const Offset(120 + 50, 10));
    await tester.pump();

    expect(seeked, isNotNull);
    expect(seeked, closeTo(0.5, 1e-9));
  });

  testWidgets(
    'dragging the diamond at track 0, key 0 reports a MoveKeys shifting '
    'that exact key',
    (tester) async {
      MoveKeys? moved;
      await _pump(
        tester,
        clip: _twoRowClip(),
        clipIndex: 3,
        onMoveKeys: (MoveKeys c) => moved = c,
      );

      // Row 0's own diamond at time 0 draws at local x = 0 within the
      // timeline canvas, y = 16 (half of the 32-tall row) below the 24-tall
      // ruler — global (120 + 0, 24 + 16) = (120, 40). A 20-pixel drag right
      // is 0.2 seconds at 100 pixels a second.
      await tester.dragFrom(const Offset(120, 40), const Offset(20, 0));
      await tester.pump();

      expect(moved, isNotNull);
      // Mutation: report the wrong clip/track/key, or the drag's own start
      // delta instead of its end-to-end one.
      expect(moved!.clipIndex, 3);
      expect(moved!.trackIndex, 0);
      expect(moved!.indices, <int>[0]);
      expect(moved!.deltaTime, closeTo(0.2, 1e-9));
    },
  );

  testWidgets('dragging track 1\'s own single key reports the right track, not '
      'always row 0', (tester) async {
    MoveKeys? moved;
    await _pump(
      tester,
      clip: _twoRowClip(),
      onMoveKeys: (MoveKeys c) => moved = c,
    );

    // Row 1's own diamond at time 0.5 draws at local x = 50, y = 32 + 16 =
    // 48 below the ruler — global (120 + 50, 24 + 48) = (170, 72).
    await tester.dragFrom(const Offset(170, 72), const Offset(-10, 0));
    await tester.pump();

    expect(moved, isNotNull);
    expect(moved!.trackIndex, 1);
    expect(moved!.indices, <int>[0]);
    expect(moved!.deltaTime, closeTo(-0.1, 1e-9));
  });

  testWidgets('a drag that starts on empty timeline space reports nothing', (
    tester,
  ) async {
    var moveKeysCalled = false;
    var setKeyCalled = false;
    await _pump(
      tester,
      clip: _twoRowClip(),
      onMoveKeys: (MoveKeys c) => moveKeysCalled = true,
      onSetKey: (int track, double time) => setKeyCalled = true,
    );

    // Far from any diamond: track 0 has keys at t=0 and t=1 (x=0, x=100),
    // this drag starts at x=250 local (within the 280-wide canvas) ->
    // global 370.
    await tester.dragFrom(const Offset(120 + 250, 40), const Offset(20, 0));
    await tester.pump();

    expect(moveKeysCalled, isFalse);
    // `S2`'s own row: a real drag, even one that started on empty space,
    // is not a tap — `onSetKey` is for `Keys` (not `Pan`), the plan's own
    // acceptance line.
    expect(setKeyCalled, isFalse);
  });

  testWidgets(
    'a tap on empty space inside a track\'s row reports that row and time',
    (tester) async {
      int? tappedTrack;
      double? tappedTime;
      await _pump(
        tester,
        clip: _twoRowClip(),
        clipIndex: 2,
        onSetKey: (int track, double time) {
          tappedTrack = track;
          tappedTime = time;
        },
      );

      // Track 0's own row, far from either of its keys at t=0/t=1 (x=0,
      // x=100 local): x=250 local -> global 370, time 2.5 at 100px/s.
      await tester.tapAt(const Offset(120 + 250, 40));
      await tester.pump();

      expect(tappedTrack, 0);
      expect(tappedTime, closeTo(2.5, 1e-9));
    },
  );

  testWidgets('a tap below the last row reports nothing', (tester) async {
    var called = false;
    await _pump(
      tester,
      clip: _twoRowClip(),
      onSetKey: (int track, double time) => called = true,
    );

    // Two rows of 32 each end at local y=64 below the 24-tall ruler —
    // global 24+64=88; this tap lands well past that, on the panel's own
    // unused remainder.
    await tester.tapAt(const Offset(120 + 40, 150));
    await tester.pump();

    expect(called, isFalse);
  });

  testWidgets('picking a diamond reports its selection even with no net move', (
    tester,
  ) async {
    (int, int)? selected;
    MoveKeys? moved;
    await _pump(
      tester,
      clip: _twoRowClip(),
      onSelectKey: (int track, int key, {bool add = false}) =>
          selected = (track, key),
      onMoveKeys: (MoveKeys c) => moved = c,
    );

    // A stationary tap on the diamond at track 0, key 0 — no competing
    // recognizer is registered on the rows detector, so it still resolves
    // through the pan recognizer's own start/end, the same way
    // `profile_editor_test.dart` documents for `ProfileEditor`.
    await tester.tapAt(const Offset(120, 40));
    await tester.pump();

    expect(selected, (0, 0));
    // Mutation: fire `onMoveKeys` even for a zero-distance drag.
    expect(moved, isNull);
  });

  testWidgets('the selected key draws distinctly (smoke: no crash with a '
      'selection set)', (tester) async {
    await _pump(tester, clip: _twoRowClip(), selectedTrack: 0, selectedKey: 1);

    expect(find.byType(TimelinePanel), findsOneWidget);
  });

  group("ux-46: a rig with real bones in it", () {
    /// Seventeen joints times translation/rotation/scale — the rig the row
    /// names, and fifty-one rows.
    ProjectClip bigRig() => ProjectClip(
      name: 'walk',
      tracks: <ProjectTrack>[
        for (var joint = 0; joint < 17; joint++)
          for (final AnimationPath path in <AnimationPath>[
            AnimationPath.translation,
            AnimationPath.rotation,
            AnimationPath.scale,
          ])
            ProjectTrack(
              objectId: joint + 1,
              track: _track(
                nodeIndex: joint,
                path: path,
                times: <double>[0.0, 1.0],
              ),
            ),
      ],
    );

    testWidgets('fifty-one tracks do not overflow at 1440x900', (
      WidgetTester tester,
    ) async {
      await _pump(tester, clip: bigRig(), window: const Size(1440, 900));

      // **The acceptance the row states.** Mutation: put the rows back in a
      // `Column`, which is how this was — fifty-one rows at the panel's own
      // row height is two and a half times the height the shell gives it,
      // and Flutter paints the overflow stripes over the bottom half.
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('and the ruler stays put while the rows scroll', (
      WidgetTester tester,
    ) async {
      await _pump(tester, clip: bigRig(), window: const Size(1440, 400));

      // A ruler that scrolled away with the rows would be worse than the
      // overflow: a key's own time is the one thing a row cannot say.
      final Finder ruler = find.byType(CustomPaint).first;
      final double before = tester.getTopLeft(ruler).dy;
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      await tester.pump();
      expect(tester.getTopLeft(ruler).dy, before);
    });

    testWidgets('a wheel over the rows asks for a new zoom', (
      WidgetTester tester,
    ) async {
      final zooms = <double>[];
      await _pump(tester, clip: _twoRowClip(), onZoom: zooms.add);

      // Inside the rows rather than at the panel's own centre: a two-track
      // clip is two rows tall, and the space under them is not the canvas
      // any more now that the rows scroll.
      final Offset at =
          tester.getTopLeft(find.byType(TimelinePanel)) +
          const Offset(200, 36);
      final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse)
        ..hover(at);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.pump();

      // Multiplicative, so a notch feels the same at every zoom — the same
      // reason `OrbitController.zoom` is. Mutation: add pixels instead, and
      // one notch is imperceptible zoomed out and a jump zoomed in.
      expect(zooms.single, greaterThan(100.0));
      expect(zooms.single, closeTo(120.0, 1e-9));
    });

    testWidgets('a dragged key lands on a frame when the profile asks', (
      WidgetTester tester,
    ) async {
      MoveKeys? moved;
      await _pump(
        tester,
        clip: _twoRowClip(),
        frameSnap: true,
        onMoveKeys: (MoveKeys c) => moved = c,
      );

      final Offset origin = tester.getTopLeft(find.byType(TimelinePanel));
      // The first diamond of the first row, dragged a little under three
      // frames' worth at 24fps and 120 pixels a second: five pixels a frame,
      // so thirteen pixels is two frames and a bit.
      final Offset from = origin + const Offset(120.0 + 0.0, 24.0 + 12.0);
      await tester.dragFrom(from, const Offset(13, 0));
      await tester.pump();

      // **The acceptance: a dragged key lands on a frame.** Mutation: report
      // the raw delta, which is what this did — `ProjectProfile.frameSnap`
      // was a field nothing read, and a clip whose keys sit a thousandth
      // either side of their frames exports as one that stutters.
      expect(moved, isNotNull);
      // The panel's own default is thirty frames a second, so a landed
      // delta is a whole number of thirtieths.
      final double frames = moved!.deltaTime * 30;
      expect(frames.round(), closeTo(frames, 1e-6));
      expect(frames, isNot(0));
    });
  });
}
