/// `ux-03`: a press on a gizmo arm becomes a drag, through the real pointer
/// event stream rather than through the arithmetic underneath it.
///
///     flutter test test/gizmo_drag_events_test.dart
///
/// **Why the events and not `GizmoDrag`.** Everything about where an arrow is
/// and how far a drag moves an object was already covered, by tests that call
/// the geometry directly — and all of them passed against a build where
/// taking hold of an arm and pulling did nothing at all. What was missing was
/// the handler: `_down` called `onGizmoDrag` and returned *before* recording
/// the press, so `_move` saw no drag in progress and `_up` fell through to a
/// pick, which cleared the selection somebody had just grabbed. The live run
/// saw it as "You · move" landing on the history with a zero delta.
library;

import 'package:flutter/gestures.dart' hide Matrix4;
import 'package:flutter/material.dart' hide Material, Matrix4;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/element_picking.dart';
import 'package:flutter3d_modeler/src/modeler_viewport.dart';
import 'package:flutter3d_modeler/src/object_picking.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/transform_gizmo.dart';
import 'package:flutter3d_modeler/src/transform_modal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

/// One cube at the origin, which is also where the gizmo goes.
ModelProject oneCube() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'cube',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: Matrix4.identity(),
  ),
);

/// What a drag through the viewport reported.
final class Reported {
  final List<Offset> drags = <Offset>[];
  int done = 0;
  int picks = 0;

  Offset get travel =>
      drags.fold(Offset.zero, (Offset sum, Offset it) => sum + it);
}

void main() {
  testWidgets('a press on an arm, fifty pixels of travel, and a release: '
      'one drag, one done, no pick', (WidgetTester tester) async {
    final it = cpuTestDevice(width: 64, height: 64);
    final project = oneCube();
    final stage = ModelerStage.fromProject(device: it.device, project: project);
    final reported = Reported();
    GizmoAxis? grabbed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: ModelerViewport(
              renderer: Renderer.create(device: it.device),
              stage: stage,
              onFrame: () {},
              gizmoPivot: Vector3.zero(),
              gizmoKind: TransformKind.move,
              onGizmoDrag: (GizmoAxis axis) => grabbed = axis,
              onDragTool: (Offset delta, double _, PickingView _, Offset _) =>
                  reported.drags.add(delta),
              onDragDone: () => reported.done++,
              onPick: (PickResult _, {required bool extend}) =>
                  reported.picks++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The stage opens on a three-quarter view, where the X arm runs right and
    // a little down the screen; thirty pixels along it is on the shaft, well
    // inside the ninety-six the arm is drawn over and well outside the
    // fifteen per cent it leaves clear around the pivot.
    final Offset middle = tester.getCenter(find.byType(ModelerViewport));
    final Offset onTheArm = middle + const Offset(30, 0);

    final TestGesture gesture = await tester.startGesture(
      onTheArm,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(grabbed, isNotNull, reason: 'the press did not reach the gizmo');

    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    // Mutation: return from `_down` without recording the press. `drags` is
    // then empty — `_move` finds no start — `done` stays zero, and `picks`
    // becomes one, which is the selection being dropped.
    expect(reported.drags, isNotEmpty);
    expect(reported.travel.dx, closeTo(50, 0.5));
    expect(reported.done, 1);
    expect(reported.picks, 0);
  });

  testWidgets('a press on nothing takes hold of nothing', (
    WidgetTester tester,
  ) async {
    final it = cpuTestDevice(width: 64, height: 64);
    final stage = ModelerStage.fromProject(
      device: it.device,
      project: oneCube(),
    );
    final reported = Reported();
    GizmoAxis? grabbed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: ModelerViewport(
              renderer: Renderer.create(device: it.device),
              stage: stage,
              onFrame: () {},
              gizmoPivot: Vector3.zero(),
              onGizmoDrag: (GizmoAxis axis) => grabbed = axis,
              onDragTool: (Offset delta, double _, PickingView _, Offset _) =>
                  reported.drags.add(delta),
              onDragDone: () => reported.done++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // A corner, which no arm reaches: the gizmo is ninety-six pixels long and
    // this is nearly two hundred away along both axes.
    final Offset middle = tester.getCenter(find.byType(ModelerViewport));
    final TestGesture gesture = await tester.startGesture(
      middle + const Offset(-180, -180),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    // Mutation: hand `_gizmoUnder`'s answer straight to `onGizmoDrag` without
    // checking it for null, or fatten the arms until they meet each other
    // round the pivot. A click anywhere in the viewport would then arm a
    // transform along whichever axis was listed first.
    //
    // Whether the drag itself reaches `onDragTool` is the armed tool's own
    // business — here one is wired unconditionally, so it does, and in the
    // application there is one only while a transform is armed.
    expect(grabbed, isNull);
    expect(reported.done, 1);
  });
}
