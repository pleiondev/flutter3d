/// `S2`'s own `CurveEditor`: the curve, its keys and its tangent handles,
/// over one track's own component — [SetKey] from a key dragged vertically,
/// [SetTangent] from a handle dragged the same way.
///
/// The curve's own reference picture is `curve_editor_golden_test.dart`,
/// kept apart from the interaction tests here the same way
/// `timeline_golden_test.dart` sits apart from `timeline_panel_test.dart`.
///
///     flutter test test/ui/curve_editor_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;
import 'package:flutter3d_modeler/src/ui/curve_editor.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/timeline_panel.dart' show timeToX;
import 'package:flutter_test/flutter_test.dart';

/// A translation track, two keys: (0s, 0) and (1s, 10), linear.
AnimationTrack _linearTrack() => AnimationTrack(
  nodeIndex: 0,
  path: AnimationPath.translation,
  interpolation: AnimationInterpolation.linear,
  times: Float32List.fromList(<double>[0.0, 1.0]),
  values: Float32List.fromList(<double>[0, 0, 0, 10, 0, 0]),
  componentCount: 3,
);

/// The same two keys, cubic — tangents default to zero until sculpted.
AnimationTrack _cubicTrack() => AnimationTrack(
  nodeIndex: 0,
  path: AnimationPath.translation,
  interpolation: AnimationInterpolation.cubicSpline,
  times: Float32List.fromList(<double>[0.0, 1.0]),
  values: Float32List.fromList(<double>[
    0, 0, 0, // key 0 in-tangent
    0, 0, 0, // key 0 value
    0, 0, 0, // key 0 out-tangent
    0, 0, 0, // key 1 in-tangent
    10, 0, 0, // key 1 value
    0, 0, 0, // key 1 out-tangent
  ]),
  componentCount: 3,
);

/// [value]'s own screen y, at [height], the exact inverse of what
/// `CurveEditor`'s own painter draws it at — the same formula, so a test can
/// drive a drag onto a key or a handle without knowing the widget's private
/// fields.
double _valueToY(double value, double min, double max, double height) {
  final margin = height * kCurveEditorVerticalMargin;
  final usable = height - margin * 2;
  final t = (value - min) / (max - min);
  return margin + (1.0 - t) * usable;
}

Future<Rect> _pump(
  WidgetTester tester, {
  required AnimationTrack track,
  int? selectedKeyIndex,
  ValueChanged<int>? onSelectKey,
  ValueChanged<SetKey>? onSetKey,
  ValueChanged<SetTangent>? onSetTangent,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 220,
          child: CurveEditor(
            clipIndex: 0,
            trackIndex: 0,
            track: track,
            selectedKeyIndex: selectedKeyIndex,
            onSelectKey: onSelectKey,
            onSetKey: onSetKey,
            onSetTangent: onSetTangent,
          ),
        ),
      ),
    ),
  );
  return tester.getRect(find.byKey(kCurveEditorCanvasKey));
}

void main() {
  testWidgets('renders without crashing, cubic or linear', (tester) async {
    await _pump(tester, track: _linearTrack());
    expect(find.byType(CurveEditor), findsOneWidget);

    await _pump(tester, track: _cubicTrack());
    expect(find.byType(CurveEditor), findsOneWidget);
  });

  testWidgets(
    'dragging key 1 vertically issues a SetKey at the same time, with only '
    'the shown component changed',
    (tester) async {
      SetKey? command;
      final canvas = await _pump(
        tester,
        track: _linearTrack(),
        onSetKey: (SetKey c) => command = c,
      );

      // Component 0 ranges 0..10 across the two keys; key 1 sits at
      // (time=1, value=10) — screen (100, top of the range).
      final startY = canvas.top + _valueToY(10, 0, 10, canvas.height);
      final start = Offset(canvas.left + timeToX(1.0, 100.0), startY);
      // Drag down by a fifth of the usable range's own pixel span — comes
      // out to a value change of roughly -2, whatever the exact number is:
      // this test cares that the *other* two components stay 0, not what
      // component 0 lands on precisely.
      await tester.dragFrom(start, const Offset(0, 20));
      await tester.pump();

      expect(command, isNotNull);
      expect(command!.clipIndex, 0);
      expect(command!.trackIndex, 0);
      expect(command!.time, closeTo(1.0, 1e-6));
      // Mutation: touch y/z as well as x, or lose the original y/z
      // entirely rather than carrying them through unedited.
      expect(command!.values[1], 0.0);
      expect(command!.values[2], 0.0);
      // A downward screen drag lowers the value.
      expect(command!.values[0], lessThan(10.0));
    },
  );

  testWidgets('picking a key reports its index', (tester) async {
    int? selected;
    final canvas = await _pump(
      tester,
      track: _linearTrack(),
      onSelectKey: (int i) => selected = i,
    );

    final y = canvas.top + _valueToY(0, 0, 10, canvas.height);
    final at = Offset(canvas.left + timeToX(0.0, 100.0), y);
    await tester.tapAt(at);
    await tester.pump();

    expect(selected, 0);
  });

  testWidgets(
    'dragging key 0\'s own out-tangent handle issues a SetTangent, leaving '
    'the in-tangent untouched',
    (tester) async {
      SetTangent? command;
      final canvas = await _pump(
        tester,
        track: _cubicTrack(),
        onSetTangent: (SetTangent c) => command = c,
      );

      // Key 0 sits at (0s, value 0); its out-handle is `handleLength`
      // seconds to the right, at the key's own value (a flat tangent).
      const handleLength = 10.0 / 100.0;
      final keyY = canvas.top + _valueToY(0, 0, 10, canvas.height);
      final handleX = canvas.left + timeToX(handleLength, 100.0);
      await tester.dragFrom(Offset(handleX, keyY), const Offset(0, -20));
      await tester.pump();

      expect(command, isNotNull);
      expect(command!.clipIndex, 0);
      expect(command!.trackIndex, 0);
      expect(command!.index, 0);
      // Dragging up steepens a positive out-slope.
      expect(command!.outTangent, isNotNull);
      expect(command!.outTangent![0], greaterThan(0.0));
      expect(command!.inTangent, isNull);
    },
  );
}
