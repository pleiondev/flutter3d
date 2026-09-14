/// The modal transform, the gizmo it shares a path with, and `view-26n`'s
/// geometry snap, driven end to end against a real `ModelerCubit` and a real
/// (software-rasterised) `ModelerStage` — no fakes, the same real objects
/// `main.dart` injects.
///
///     flutter test test/transform_session_test.dart
library;

import 'dart:ui' show Offset, Size;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/src/element_picking.dart' show PickingView;
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/transform_gizmo.dart';
import 'package:flutter3d_modeler/src/transform_modal.dart';
import 'package:flutter3d_modeler/src/transform_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// [count] cubes, spaced four metres apart along X so their positions are
/// never mistaken for one another.
ModelProject cubes(int count) {
  var project = const ModelProject();
  for (var i = 0; i < count; i++) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: String.fromCharCode(97 + i),
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.translation(Vector3(4.0 * i, 0, 0)),
      ),
    );
  }
  return project;
}

/// A cubit with [project] open over a real device, and the [TransformSession]
/// `main.dart` would build over it.
({ModelerCubit cubit, TransformSession session}) openedWith(
  ModelProject project,
) {
  final it = cpuTestDevice(width: 8, height: 8);
  final history = ModelHistory(project);
  final stage = ModelerStage.fromProject(
    device: it.device,
    project: history.project,
  );
  final cubit = ModelerCubit()
    ..opened(
      history,
      renderer: Renderer.create(device: it.device),
      stage: stage,
    );
  final session = TransformSession(
    cubit: cubit,
    history: () => (cubit.state as ModelerReady).history,
    editMesh: () => editMeshOf(
      (cubit.state as ModelerReady).history.project,
      (cubit.state as ModelerReady).history.selection,
    ),
  );
  return (cubit: cubit, session: session);
}

ModelerReady ready(ModelerCubit cubit) => cubit.state as ModelerReady;

/// A view looking straight down −Z, matching the camera every fresh stage
/// opens with.
PickingView viewOver(ModelerCubit cubit) =>
    PickingView(camera: ready(cubit).stage.camera, size: const Size(800, 600));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('middleOfSelection is the average of the selected objects, not just '
      'the first or the last', () {
    final made = openedWith(cubes(2));
    final ids = ready(made.cubit).project.objects.map((o) => o.id).toList();
    ready(made.cubit).history.selection = ProjectSelection(objects: ids);

    expect(made.session.middleOfSelection(), Vector3(2.0, 0, 0));
  });

  test(
    'a drag with the move tool armed opens a modal and moves the object',
    () {
      final made = openedWith(cubes(1));
      final id = ready(made.cubit).project.objects.single.id;
      ready(made.cubit).history.selection = ProjectSelection(objects: [id]);
      made.cubit.tool('object.move');

      made.session.dragged(const Offset(40, 0), 600, viewOver(made.cubit));

      // Mutation: never call `applyModal`, or call it with a zero step. A drag
      // that opens the transaction but never runs a command would leave the
      // object exactly where it started, which is not a drag at all.
      final moved = ready(made.cubit).project.objects.single;
      expect(moved.transform.getTranslation().x, isNot(0));
      expect(made.session.modal, isNotNull);
    },
  );

  test('commit closes the transaction, and a second commit is a no-op', () {
    final made = openedWith(cubes(1));
    final id = ready(made.cubit).project.objects.single.id;
    ready(made.cubit).history.selection = ProjectSelection(objects: [id]);
    made.cubit.tool('object.move');
    made.session.dragged(const Offset(40, 0), 600, viewOver(made.cubit));

    made.session.commit();
    expect(made.session.modal, isNull);
    final afterFirstCommit = ready(made.cubit).project.objects.single.transform;

    // Mutation: `commit` closing a transaction that is not open, or ending it
    // twice. `ModelHistory.endTransaction` without a matching `begin` is
    // exactly the bug a guard on `_modal == null` exists to prevent.
    made.session.commit();
    expect(
      ready(made.cubit).project.objects.single.transform,
      afterFirstCommit,
    );
  });

  test('cancel undoes the drag and puts the object back exactly', () {
    final made = openedWith(cubes(1));
    final id = ready(made.cubit).project.objects.single.id;
    ready(made.cubit).history.selection = ProjectSelection(objects: [id]);
    made.cubit.tool('object.move');
    final before = ready(
      made.cubit,
    ).project.objects.single.transform.getTranslation();

    made.session.dragged(const Offset(40, 0), 600, viewOver(made.cubit));
    made.session.cancel();

    expect(made.session.modal, isNull);
    expect(
      ready(made.cubit).project.objects.single.transform.getTranslation(),
      before,
    );
  });

  test('Escape while a transform is going on takes it, and cancels', () {
    final made = openedWith(cubes(1));
    final id = ready(made.cubit).project.objects.single.id;
    ready(made.cubit).history.selection = ProjectSelection(objects: [id]);
    made.cubit.tool('object.move');
    made.session.dragged(const Offset(40, 0), 600, viewOver(made.cubit));

    final taken = made.session.modalKey(LogicalKeyboardKey.escape, null);

    expect(taken, isTrue);
    expect(made.session.modal, isNull);
  });

  test('grabbing a gizmo arm opens the same modal G would, with that axis '
      'already set', () {
    final made = openedWith(cubes(1));
    final id = ready(made.cubit).project.objects.single.id;
    ready(made.cubit).history.selection = ProjectSelection(objects: [id]);
    made.cubit.tool('object.rotate');

    made.session.grabbedGizmo(GizmoAxis.y);

    // Mutation: a gizmo that ran its own command instead of opening the same
    // modal `G` opens — the two would part company at the first snap.
    expect(made.session.modal?.kind, TransformKind.rotate);
    expect(made.session.modal?.axis, TransformAxis.y);
  });
}
