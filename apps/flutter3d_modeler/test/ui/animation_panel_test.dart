/// `anim-07`'s own `AnimationPanel`: which clip is open and where the
/// scrubber sits are this widget's own state, but [AnimationPanel.onSelectClip]
/// and [AnimationPanel.onTimeChanged] report both alongside it — the seam
/// `main.dart`'s own live pose preview hangs off of.
///
///     flutter test test/ui/animation_panel_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;
import 'package:flutter3d_modeler/src/ui/animation_panel.dart';
import 'package:flutter3d_modeler/src/ui/timeline_panel.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectClip _clip(String name) => ProjectClip(
  name: name,
  tracks: <ProjectTrack>[
    ProjectTrack(
      objectId: 1,
      track: AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.translation,
        interpolation: AnimationInterpolation.linear,
        times: Float32List.fromList(<double>[0.0, 1.0]),
        values: Float32List.fromList(<double>[0, 0, 0, 1, 0, 0]),
        componentCount: 3,
      ),
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  required List<ProjectClip> clips,
  ValueChanged<int?>? onSelectClip,
  ValueChanged<double>? onTimeChanged,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: AnimationPanel(
        clips: clips,
        objects: const <ModelObject>[],
        onMoveKeys: (_) {},
        onAddClip: () {},
        onSelectClip: onSelectClip,
        onTimeChanged: onTimeChanged,
      ),
    ),
  ),
);

void main() {
  testWidgets('picking a clip in the action list reports its index', (
    WidgetTester tester,
  ) async {
    final selected = <int?>[];
    await _pump(
      tester,
      clips: <ProjectClip>[_clip('walk'), _clip('run')],
      onSelectClip: selected.add,
    );

    await tester.tap(find.text('run'));
    await tester.pump();

    expect(selected, <int?>[1]);
  });

  testWidgets(
    'a clip closing out from under the panel reports null, not silence',
    (WidgetTester tester) async {
      final selected = <int?>[];
      await _pump(
        tester,
        clips: <ProjectClip>[_clip('walk'), _clip('run')],
        onSelectClip: selected.add,
      );
      await tester.tap(find.text('run'));
      await tester.pump();
      selected.clear();

      // The clip this panel had open is gone — the same shape an undo past
      // `AddClip` leaves behind.
      await _pump(
        tester,
        clips: <ProjectClip>[_clip('walk')],
        onSelectClip: selected.add,
      );

      expect(selected, <int?>[null]);
    },
  );

  testWidgets(
    'the timeline\'s own onSeek reaches onTimeChanged with the same value',
    (WidgetTester tester) async {
      final scrubbed = <double>[];
      await _pump(
        tester,
        clips: <ProjectClip>[_clip('walk')],
        onTimeChanged: scrubbed.add,
      );
      await tester.tap(find.text('walk'));
      await tester.pump();

      // Driving the exact callback `TimelinePanel` itself fires on a drag —
      // `ui/timeline_panel_test.dart` already covers that a drag on the
      // ruler calls this with the seconds under the pointer; what this
      // panel adds is forwarding it, which is what this checks.
      final TimelinePanel timeline = tester.widget(find.byType(TimelinePanel));
      timeline.onSeek!(0.5);
      await tester.pump();

      expect(scrubbed, <double>[0.5]);
    },
  );

  testWidgets('no clip open means no timeline and no scrub to report', (
    WidgetTester tester,
  ) async {
    await _pump(tester, clips: <ProjectClip>[_clip('walk')]);

    expect(find.byType(TimelinePanel), findsNothing);
  });
}
