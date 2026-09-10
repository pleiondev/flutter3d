/// The dial as a widget: the one thing about it that needs a screen.
///
///     flutter test test/orientation_dial_test.dart
///
/// Where the buttons sit, which one a press lands on and where each points the
/// camera are `ground_grid_test`'s subject and need no widget. What is left
/// here is the conversion between the two coordinate systems: Flutter gives a
/// press in the box's own pixels and `OrientationGizmo` speaks in offsets from
/// the dial's centre.
///
/// What is deliberately *not* here is a test that a press between the balls
/// stops at the dial rather than reaching the viewport behind it. Two goes at
/// one passed with the dial taken out of the tree altogether, which makes it a
/// test of the harness; the guarantee is a `HitTestBehavior` on one line and is
/// better read there than asserted by something that does not assert it.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ground_grid.dart';
import 'package:flutter3d_modeler/src/orientation_dial.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gizmo = OrientationGizmo();
  final double side = (gizmo.radius + gizmo.handleRadius) * 2;

  /// The dial in a box of its own, with what it reported.
  Future<List<ViewAxis>> pumpAndTap(
    WidgetTester tester,
    Offset from, {
    double yaw = 0.0,
    double pitch = 0.0,
  }) async {
    final pressed = <ViewAxis>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: OrientationDial(
            yaw: yaw,
            pitch: pitch,
            onPressed: pressed.add,
          ),
        ),
      ),
    );
    await tester.tapAt(from);
    await tester.pump();
    return pressed;
  }

  testWidgets('a press on a ball is a press on its axis', (
    WidgetTester tester,
  ) async {
    // Where the gizmo says the −X ball is, in offsets from the centre, turned
    // into the position Flutter will report.
    final ball = gizmo
        .buttonsAt(yaw: 0, pitch: 0)
        .firstWhere((GizmoButton b) => b.axis == ViewAxis.xNegative);
    final at = Offset(side / 2 + ball.dx, side / 2 + ball.dy);

    // Mutation: hand `hitTest` the raw local position instead of subtracting
    // half the side, and this reports nothing at all — the press arrives as
    // (9, 31) rather than (−22, 0), which is thirty pixels from every ball on
    // a dial whose balls are nine pixels wide. Every press on the dial would
    // then do nothing, on a control whose entire job is to be pressed.
    expect(await pumpAndTap(tester, at), <ViewAxis>[ViewAxis.xNegative]);
  });

  testWidgets('a press inside the box but off the dial is not a button', (
    WidgetTester tester,
  ) async {
    // A corner of the square the dial lives in, which is outside the circle its
    // balls sit on: the nearest of them is thirty pixels away. The middle would
    // have been the obvious place to press for this and is wrong — with the
    // camera at rest the +Z ball is pointing straight at the viewer and sits
    // exactly there.
    expect(await pumpAndTap(tester, const Offset(2, 2)), isEmpty);
  });
}
