/// `S2`'s own golden: `curve-editor`, the acceptance's own frame — a small
/// cubic clip with a couple of keys, the same shape `modeler-timeline.png`
/// itself was built from.
///
///     flutter test test/curve_editor_golden_test.dart
///     flutter test test/curve_editor_golden_test.dart --update-goldens
///
/// **The captured region is [kCurveEditorCanvasKey]'s own `RepaintBoundary`,
/// not the whole widget.** That boundary wraps the curve line, the keys and
/// the tangent handles — drawn in vectors and never a glyph — and leaves out
/// the component chips and the Euler read-out above it, both of them
/// `Text`. Capturing only the glyph-free half keeps this golden independent
/// of whichever font the machine running the test has installed, the same
/// promise `timeline_golden_test.dart` already keeps for the timeline.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_modeler/src/ui/curve_editor.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

AnimationTrack _clip() => AnimationTrack(
  nodeIndex: 0,
  path: AnimationPath.translation,
  interpolation: AnimationInterpolation.cubicSpline,
  times: Float32List.fromList(<double>[0.0, 0.6, 1.4]),
  values: Float32List.fromList(<double>[
    0, 0, 0, 0, 0, 0, 2, 0, 0, // key 0: flat in, value 0, out slope 2
    -1, 0, 0, 3, 0, 0, 1, 0, 0, // key 1: value 3
    0, 0, 0, 1, 0, 0, 0, 0, 0, // key 2: value 1, flat out
  ]),
  componentCount: 3,
);

void main() {
  testWidgets('the curve editor, with a small cubic clip and a couple of keys, '
      'matches its reference', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: modelerTheme(),
        home: Scaffold(
          body: Container(
            color: ModelerColors.dark.viewport,
            width: 360,
            height: 160,
            padding: const EdgeInsets.all(8),
            child: CurveEditor(
              clipIndex: 0,
              trackIndex: 0,
              track: _clip(),
              selectedKeyIndex: 1,
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(kCurveEditorCanvasKey),
      matchesGoldenFile('goldens/curve-editor.png'),
    );
  });
}
