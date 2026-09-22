/// `anim-07`'s own golden: `modeler-timeline`, the acceptance's own frame.
///
///     flutter test test/timeline_golden_test.dart
///     flutter test test/timeline_golden_test.dart --update-goldens
///
/// **Not through `flutter3d_testing`'s own `expectMatchesGolden`.** Every
/// golden that pipeline draws is a 3D scene through the software rasteriser —
/// `frame_test.dart`'s own group headings say so, one `Scene`/`Camera` pair
/// at a time — and `TimelinePanel` is a 2D `CustomPainter`, not a scene. This
/// uses Flutter's own `matchesGoldenFile` instead, the ordinary mechanism for
/// a widget's own picture, and a first for this application.
///
/// **The captured region is [kTimelineCanvasKey]'s own `RepaintBoundary`, not
/// the whole panel.** That boundary wraps the ruler and the rows — ticks,
/// diamonds, the playhead, drawn in vectors and never a glyph — and leaves
/// out the label column's own `Text`. A golden built from text inherits
/// whatever font the machine running the test has installed, which is
/// exactly the cross-platform fragility this repository's own 3D goldens
/// were built to avoid; capturing only the glyph-free half keeps this one
/// honestly comparable to the same pipeline's own no-GPU-no-font promise.
// A reference picture, held against a committed PNG. Tagged so a run that
// only wants the logic can skip every one of them at once:
//
//     very_good test -x golden
//
// Kept as a tag rather than a flag a test reads, because the decision belongs
// to whoever starts the run and not to the test.
@Tags(<String>['golden'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/timeline_panel.dart';
import 'package:flutter_test/flutter_test.dart';

AnimationTrack _track(List<double> times, AnimationPath path) => AnimationTrack(
  nodeIndex: 0,
  path: path,
  interpolation: AnimationInterpolation.linear,
  times: Float32List.fromList(times),
  values: Float32List(times.length * path.componentCount),
  componentCount: path.componentCount,
);

/// A small clip: a couple of keys on two tracks — the acceptance's own "с
/// небольшим клипом и парой ключей".
ProjectClip _clip() => ProjectClip(
  name: 'wave',
  tracks: <ProjectTrack>[
    ProjectTrack(
      objectId: 1,
      track: _track(<double>[0.0, 0.6, 1.4], AnimationPath.translation),
    ),
    ProjectTrack(
      objectId: 2,
      track: _track(<double>[0.3, 1.0], AnimationPath.rotation),
    ),
  ],
);

void main() {
  testWidgets('the timeline, with a small clip and a couple of keys, matches '
      'its reference', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: modelerTheme(),
        home: Scaffold(
          body: Container(
            color: ModelerColors.dark.viewport,
            width: 360,
            height: 128,
            padding: const EdgeInsets.all(8),
            child: TimelinePanel(
              clipIndex: 0,
              clip: _clip(),
              time: 0.75,
              selectedTrack: 0,
              selectedKey: 1,
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(kTimelineCanvasKey),
      matchesGoldenFile('goldens/modeler-timeline.png'),
    );
  });
}
