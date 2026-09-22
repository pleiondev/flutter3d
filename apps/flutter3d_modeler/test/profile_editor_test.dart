/// `ui-13`'s own interactive half: a drag on `ProfileEditor` turns into an
/// edit through whichever chip is armed.
///
///     flutter test test/profile_editor_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/profile_editing.dart';
import 'package:flutter3d_modeler/src/ui/profile_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A controlled [ProfileEditor] that keeps its own [curve] in `State` and
/// hands every intermediate value to [onEachChange] as well — a real editor
/// re-renders on every drag frame the same way this does, and a test that
/// only saw the last value could not tell "moved once" from "moved back to
/// where it started."
class _Harness extends StatefulWidget {
  const _Harness({
    required this.initial,
    required this.tool,
    required this.onEachChange,
  });

  final ProfileCurve initial;
  final ProfileEditTool tool;
  final ValueChanged<ProfileCurve> onEachChange;

  /// Every model coordinate this file's own tests compute is worked out
  /// against this fixed canvas size — see each test's own comment for the
  /// local-to-model arithmetic.
  static const Size canvasSize = Size(400, 400);

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late ProfileCurve _curve = widget.initial;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: _Harness.canvasSize.width,
        height: _Harness.canvasSize.height,
        child: ProfileEditor(
          curve: _curve,
          tool: widget.tool,
          onChanged: (ProfileCurve next) {
            widget.onEachChange(next);
            setState(() => _curve = next);
          },
        ),
      ),
    ),
  );
}

/// The empty curve every "adds a point" test starts from.
ProfileCurve _empty() => ProfileCurve(
  points: const <ProfilePoint>[],
  segments: const <ProfileSegment>[],
);

void main() {
  group('Point tool', () {
    testWidgets('a stationary tap on empty space adds a point there', (
      WidgetTester tester,
    ) async {
      ProfileCurve? last;
      await tester.pumpWidget(
        _Harness(
          initial: _empty(),
          tool: ProfileEditTool.point,
          onEachChange: (ProfileCurve curve) => last = curve,
        ),
      );

      // Local (100, 100) on a 400×400 canvas with the default 24-pixel
      // margin maps to model (76, 276) — see `profileEditorToModel`. No
      // competing recognizer is registered on this detector, so even a
      // stationary tap resolves to this widget's own pan recognizer once
      // the pointer lifts, rather than needing to exceed the touch slop.
      await tester.tapAt(const Offset(100, 100));
      await tester.pump();

      expect(last, isNotNull);
      expect(last!.points.length, 1);
      expect(
        (last!.points.first.position - Vector2(76, 276)).length < 1,
        isTrue,
      );
    });

    testWidgets('a drag on empty space both adds a point and drags it', (
      WidgetTester tester,
    ) async {
      ProfileCurve? last;
      await tester.pumpWidget(
        _Harness(
          initial: _empty(),
          tool: ProfileEditTool.point,
          onEachChange: (ProfileCurve curve) => last = curve,
        ),
      );

      // Down at local (100, 100) = model (76, 276), dragged 20 right to
      // local (120, 100) = model (96, 276) — one point, at the drag's own
      // end rather than where it started.
      await tester.dragFrom(const Offset(100, 100), const Offset(20, 0));
      await tester.pump();

      expect(last, isNotNull);
      expect(last!.points.length, 1);
      expect(
        (last!.points.first.position - Vector2(96, 276)).length < 1,
        isTrue,
      );
    });

    testWidgets('a drag starting on an existing point moves it, rather '
        'than adding a second one', (WidgetTester tester) async {
      final curve = ProfileCurve(
        points: <ProfilePoint>[ProfilePoint(Vector2(76, 276))],
        segments: const <ProfileSegment>[],
      );
      ProfileCurve? last;
      await tester.pumpWidget(
        _Harness(
          initial: curve,
          tool: ProfileEditTool.point,
          onEachChange: (ProfileCurve next) => last = next,
        ),
      );

      // Starts dead on the point at local (100, 100) and drags 40 right.
      await tester.dragFrom(const Offset(100, 100), const Offset(40, 0));
      await tester.pump();

      expect(last, isNotNull);
      expect(last!.points.length, 1);
      expect(last!.points.first.position.x, greaterThan(76));
    });
  });

  group('Axis tool', () {
    testWidgets('dragging a point near the axis snaps it to x = 0', (
      WidgetTester tester,
    ) async {
      // Local (44, 100) is model (20, 276) — inside the default 40-unit
      // snap distance of the axis at x = 0.
      final curve = ProfileCurve(
        points: <ProfilePoint>[ProfilePoint(Vector2(20, 276))],
        segments: const <ProfileSegment>[],
      );
      ProfileCurve? last;
      await tester.pumpWidget(
        _Harness(
          initial: curve,
          tool: ProfileEditTool.axis,
          onEachChange: (ProfileCurve next) => last = next,
        ),
      );

      // A small drag that stays within the snap distance throughout.
      await tester.dragFrom(const Offset(44, 100), const Offset(10, 0));
      await tester.pump();

      expect(last, isNotNull);
      expect(last!.points.single.position.x, 0);
    });

    testWidgets('a tap in empty space adds nothing', (
      WidgetTester tester,
    ) async {
      ProfileCurve? last;
      await tester.pumpWidget(
        _Harness(
          initial: _empty(),
          tool: ProfileEditTool.axis,
          onEachChange: (ProfileCurve next) => last = next,
        ),
      );

      await tester.dragFrom(const Offset(100, 100), const Offset(10, 0));
      await tester.pump();

      expect(last, isNull);
    });
  });

  group('Curve tool', () {
    testWidgets('a drag starting on a straight chord bends it into a '
        'quadratic', (WidgetTester tester) async {
      final curve = ProfileCurve(
        points: <ProfilePoint>[
          ProfilePoint(Vector2(0, 0)),
          ProfilePoint(Vector2(160, 0)),
        ],
        segments: const <ProfileSegment>[LineSegment()],
      );
      ProfileCurve? last;
      await tester.pumpWidget(
        _Harness(
          initial: curve,
          tool: ProfileEditTool.curve,
          // Local axisMargin = 24, model y = 0 draws at local
          // (400 - 24 - 0) = 376; the chord's own midpoint (80, 0) draws
          // at local (104, 376).
          onEachChange: (ProfileCurve next) => last = next,
        ),
      );

      await tester.dragFrom(const Offset(104, 376), const Offset(0, -40));
      await tester.pump();

      expect(last, isNotNull);
      expect(last!.segments.single, isA<QuadraticSegment>());
    });

    testWidgets('re-dragging an already-bent segment moves its own handle '
        'rather than starting a new one', (WidgetTester tester) async {
      final curve = ProfileCurve(
        points: <ProfilePoint>[
          ProfilePoint(Vector2(0, 0)),
          ProfilePoint(Vector2(160, 0)),
        ],
        segments: <ProfileSegment>[QuadraticSegment(Vector2(80, 40))],
      );
      ProfileCurve? last;
      await tester.pumpWidget(
        _Harness(
          initial: curve,
          tool: ProfileEditTool.curve,
          onEachChange: (ProfileCurve next) => last = next,
        ),
      );

      // The handle at model (80, 40) draws at local (104, 336).
      await tester.dragFrom(const Offset(104, 336), const Offset(0, -20));
      await tester.pump();

      expect(last, isNotNull);
      final segment = last!.segments.single as QuadraticSegment;
      expect(segment.control.y, greaterThan(40));
    });
  });
}
