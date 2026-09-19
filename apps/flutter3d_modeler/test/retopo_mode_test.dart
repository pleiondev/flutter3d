/// `pro-rt-03`, end to end: a quad drawn by hand in the real editor, over
/// the cube a launch opens on.
///
///     flutter test test/retopo_mode_test.dart
///
/// `RetopoOverlay` had a painter test and no caller. What this holds is that
/// four clicks in the Retopo mode are four corners on the overlay and then
/// one `DrawQuad` on the history — and that with nothing to draw between,
/// the mode says which two things to select rather than swallowing clicks.
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_modeler/src/modeler_viewport.dart';
import 'package:flutter3d_modeler/src/ui/properties/object_row.dart';
import 'package:flutter3d_modeler/src/ui/retopo_overlay.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tutorial_screenshots_support.dart';

/// Every `RetopoOverlay` on screen — a `CustomPaint` whose painter is one.
Iterable<RetopoOverlay> _overlays(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((CustomPaint it) => it.painter)
    .whereType<RetopoOverlay>();

Future<void> _click(WidgetTester tester, Offset at) async {
  final TestGesture press = await tester.startGesture(
    at,
    kind: PointerDeviceKind.mouse,
  );
  await press.up();
  await settleFrames(tester);
}

void main() {
  testWidgets('with nothing to draw between, the mode says what to select', (
    WidgetTester tester,
  ) async {
    await launchModeller(tester, fonts: true);
    await switchMode(tester, ModelerMode.retopo);

    // `retopo.quad` is the tool the mode arms, and a launch has one object.
    // Mutation: route every click to the quad regardless. The mode then has
    // no way to pick the two objects it is asking for.
    expect(find.textContaining('shift-click the mesh'), findsOneWidget);
    expect(_overlays(tester), isEmpty);
  });

  testWidgets('four clicks are four corners, and then one quad', (
    WidgetTester tester,
  ) async {
    await launchModeller(tester, fonts: true);

    // A second mesh to draw onto: a plane, converted, which is how a
    // retopology is started — and the cube it is traced over, picked first
    // so that the plane is the active one.
    await openByTooltip(tester, 'Add a primitive');
    await tester.tap(find.text('Plane').last);
    await settleFrames(tester);
    await tester.tap(find.byIcon(Icons.change_circle_outlined));
    await settleFrames(tester);
    await tester.tap(find.byType(ObjectRow).first);
    await settleFrames(tester);
    // Shift held until the row's own double-tap timer has run out: a row
    // can be double-clicked to rename it, so a single click is not a click
    // until three hundred milliseconds have passed, and the modifiers are
    // read when it becomes one.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byType(ObjectRow).last);
    await settleFrames(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await settleFrames(tester);

    await switchMode(tester, ModelerMode.retopo);
    expect(find.text('Quad · 0 of 4 points'), findsOneWidget);
    expect(_overlays(tester), hasLength(1));
    // The plane's own one face is the grid, and no quad is open.
    expect(_overlays(tester).single.quads, isNotEmpty);
    expect(_overlays(tester).single.active, isNull);
    expect(_overlays(tester).single.sourceAlpha, kSourceClear);

    // Four points round the middle of the picture, which is the cube.
    final Offset middle = tester.getCenter(find.byType(ModelerViewport));
    const List<Offset> round = <Offset>[
      Offset(-30, -30),
      Offset(30, -30),
      Offset(30, 30),
      Offset(-30, 30),
    ];
    for (var i = 0; i < 3; i++) {
      await _click(tester, middle + round[i]);
      // Mutation: keep the corners and never hand them to the painter. The
      // card counts and the picture shows nothing of what was placed.
      expect(find.text('Quad · ${i + 1} of 4 points'), findsOneWidget);
      expect(_overlays(tester).single.active, hasLength(i + 1));
      expect(_overlays(tester).single.sourceAlpha, kSourceFaint);
    }

    final int facesBefore = _overlays(tester).single.quads.length;
    await _click(tester, middle + round[3]);

    // One command, one step, and the corners are gone. Mutation: run the
    // command per corner, or never — either way there is no "draw a quad"
    // on top of the history for undo to name.
    expect(find.text('Quad · 0 of 4 points'), findsOneWidget);
    expect(find.byTooltip('undo draw a quad'), findsOneWidget);
    expect(_overlays(tester).single.quads.length, facesBefore + 1);

    // `DrawQuad` leaves the target alone selected, and the mode goes on
    // drawing between the same two: the next click is a corner, not a
    // complaint.
    await _click(tester, middle + round[0]);
    expect(find.text('Quad · 1 of 4 points'), findsOneWidget);
  });
}
