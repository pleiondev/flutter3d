/// `ux-28`'s own half of the viewport: which modifiers a click reports, what
/// a resting pointer reports, and what a drag draws when the lasso is armed.
///
///     flutter test test/viewport_element_gestures_test.dart
///
/// Through the real widget, for the reason `viewport_look_and_modal_test.dart`
/// gives: what this row changed is which pointer event means what, and that
/// decision is made in the widget. What the answers then *do* to the document
/// is `selection_rules_test.dart`'s and `element_picking_test.dart`'s, which
/// need no window at all.
library;

import 'package:flutter/gestures.dart' hide Matrix4;
import 'package:flutter/material.dart' hide Material, Matrix4;
import 'package:flutter/services.dart' hide Matrix4;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/element_picking.dart';
import 'package:flutter3d_modeler/src/modeler_viewport.dart';
import 'package:flutter3d_modeler/src/selection_box.dart';
import 'package:flutter3d_modeler/src/selection_rules.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4;

import 'support/fake_graphics_backend.dart';

ModelProject oneCube() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'cube',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: Matrix4.identity(),
  ),
);

/// What the widget reported, collected as it arrives.
final class Heard {
  final List<ElementPickIntent> picks = <ElementPickIntent>[];
  final List<Offset?> hovers = <Offset?>[];
  final List<SelectionBox> boxes = <SelectionBox>[];
}

Future<Heard> pumpViewport(WidgetTester tester, {bool lasso = false}) async {
  final heard = Heard();
  // A fake device rather than the software rasteriser: `ModelerViewport`
  // renders at its widget's constraints, not at the size the device was made
  // with, so the 64x64 here bought nothing and every rebuild rasterised the
  // whole box in debug Dart. Nothing in this file reads a pixel — these are
  // pointer tests. See `support/fake_graphics_backend.dart`.
  final device = FakeBackend();
  final ModelerStage stage = ModelerStage.fromProject(
    device: device,
    project: oneCube(),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: ModelerViewport(
            renderer: Renderer.create(device: device),
            stage: stage,
            onFrame: () {},
            lassoSelect: lasso,
            onElementPick:
                (
                  PickingView _,
                  Offset _,
                  PointerDeviceKind _, {
                  required ElementPickIntent intent,
                }) => heard.picks.add(intent),
            onElementHover: (PickingView _, Offset? at, PointerDeviceKind _) =>
                heard.hovers.add(at),
            onBox: (SelectionBox box, PickingView _) => heard.boxes.add(box),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return heard;
}

/// A click that does not travel, with [keys] held down over it.
Future<void> clickWith(
  WidgetTester tester,
  List<LogicalKeyboardKey> keys,
) async {
  for (final LogicalKeyboardKey key in keys) {
    await simulateKeyDownEvent(key);
  }
  await tester.tapAt(
    tester.getCenter(find.byType(ModelerViewport)),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  for (final LogicalKeyboardKey key in keys.reversed) {
    await simulateKeyUpEvent(key);
  }
}

void main() {
  // Under `flutter test` there is no Impeller, so a device opened here would
  // fall through to the software rasteriser and rasterise the whole viewport
  // in Dart — measured at 19 seconds for this file's two tests against 3 with
  // the fake. Nothing below reads a pixel. See
  // `support/fake_graphics_backend.dart`.
  setUp(useFakeGraphicsBackend);

  group('ux-28: what a click reports', () {
    testWidgets('nothing held is the plain pick', (WidgetTester tester) async {
      final Heard heard = await pumpViewport(tester);

      await clickWith(tester, const <LogicalKeyboardKey>[]);

      expect(heard.picks, <ElementPickIntent>[ElementPickIntent.replace]);
    });

    testWidgets('alt is the loop', (WidgetTester tester) async {
      final Heard heard = await pumpViewport(tester);

      await clickWith(tester, const <LogicalKeyboardKey>[
        LogicalKeyboardKey.altLeft,
      ]);

      // Mutation: keep reading shift alone, as this widget did before the
      // row. Alt-click then means a plain click, and the loop key is a key
      // that does nothing at all.
      expect(heard.picks, <ElementPickIntent>[ElementPickIntent.loop]);
    });

    testWidgets('and control on top of it is the ring', (
      WidgetTester tester,
    ) async {
      final Heard heard = await pumpViewport(tester);

      await clickWith(tester, const <LogicalKeyboardKey>[
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.controlLeft,
      ]);

      expect(heard.picks, <ElementPickIntent>[ElementPickIntent.ring]);
    });

    testWidgets('the command key stands in for control', (
      WidgetTester tester,
    ) async {
      final Heard heard = await pumpViewport(tester);

      // Mutation: read `isControlPressed` alone. On a Mac, where control
      // with the left button is the system's own secondary click and never
      // arrives here at all, the ring would be unreachable.
      await clickWith(tester, const <LogicalKeyboardKey>[
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.metaLeft,
      ]);

      expect(heard.picks, <ElementPickIntent>[ElementPickIntent.ring]);
    });
  });

  group('ux-28: what a resting pointer reports', () {
    testWidgets('a hover says where it is', (WidgetTester tester) async {
      final Heard heard = await pumpViewport(tester);

      final TestGesture pointer = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await pointer.addPointer(
        location: tester.getCenter(find.byType(ModelerViewport)),
      );
      addTearDown(pointer.removePointer);
      await pointer.moveTo(
        tester.getCenter(find.byType(ModelerViewport)) + const Offset(10, 10),
      );
      await tester.pump();

      expect(heard.hovers, isNotEmpty);
      expect(heard.hovers.last, isNotNull);
    });

    testWidgets('and a pointer that leaves says so', (
      WidgetTester tester,
    ) async {
      final Heard heard = await pumpViewport(tester);

      final TestGesture pointer = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await pointer.addPointer(
        location: tester.getCenter(find.byType(ModelerViewport)),
      );
      addTearDown(pointer.removePointer);
      await pointer.moveTo(const Offset(2000, 2000));
      await tester.pump();

      // Mutation: report only hovers. The highlight then stays on whatever
      // the pointer passed over on its way out, for as long as the person is
      // looking somewhere else — a selection that is not one.
      expect(heard.hovers.last, isNull);
    });
  });

  group('ux-28: a drag with the lasso armed', () {
    testWidgets('draws a loop rather than a rectangle', (
      WidgetTester tester,
    ) async {
      final Heard heard = await pumpViewport(tester, lasso: true);

      final Offset middle = tester.getCenter(find.byType(ModelerViewport));
      final TestGesture drag = await tester.startGesture(
        middle,
        kind: PointerDeviceKind.mouse,
      );
      for (final Offset step in const <Offset>[
        Offset(40, 0),
        Offset(0, 40),
        Offset(-40, 0),
      ]) {
        await drag.moveBy(step);
        await tester.pump();
      }
      await drag.up();
      await tester.pump();

      expect(heard.boxes, hasLength(1));
      // Mutation: build the box without the tool's own flag. The drag is
      // then a rectangle whatever button is lit, and the lasso is a tool
      // that changes nothing.
      expect(heard.boxes.single.isLasso, isTrue);
      expect(heard.boxes.single.trail, hasLength(greaterThan(3)));
    });

    testWidgets('and with it unarmed the same drag is a rectangle', (
      WidgetTester tester,
    ) async {
      final Heard heard = await pumpViewport(tester);

      final Offset middle = tester.getCenter(find.byType(ModelerViewport));
      final TestGesture drag = await tester.startGesture(
        middle,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(40, 40));
      await tester.pump();
      await drag.up();
      await tester.pump();

      expect(heard.boxes.single.isLasso, isFalse);
      expect(heard.boxes.single.trail, isNull);
    });
  });
}
