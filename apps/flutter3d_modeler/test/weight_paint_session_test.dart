/// `WeightPaintSession`: T4.1's own `history.beginTransaction()` / one
/// `PaintWeights` per move / `endTransaction()`, driven end to end against a
/// real `ModelerCubit` and a real (software-rasterised) `ModelerStage` — no
/// fakes, the same real objects `main.dart` injects, the same shape
/// `transform_session_test.dart` already drives its own session with.
///
///     flutter test test/weight_paint_session_test.dart
library;

import 'dart:ui' show Offset, Size;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/src/element_picking.dart' show PickingView;
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/weight_paint_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/fake_graphics_backend.dart';

/// A cuboid fully bound to the first of two joints — a stroke painting onto
/// the *second* has somewhere real to move weight from, which a mesh with
/// only one joint to ever name would not: renormalizing a single influence
/// back to one leaves the very same bytes a stroke started with.
EditMesh _boundCuboid() {
  final mesh = EditMesh.cuboid();
  mesh.beginStep();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    mesh.setSkin(
      v,
      VertexAttributes(
        joints: Vector4(0, 0, 0, 0),
        weights: Vector4(1, 0, 0, 0),
      ),
    );
  }
  mesh.endStep();
  return mesh;
}

({
  ModelerCubit cubit,
  WeightPaintSession session,
  EditMesh mesh,
  int objectId,
  int jointId,
})
openedWith() {
  final it = fakeTestDevice(width: 8, height: 8);
  final mesh = _boundCuboid();
  final project = ModelProject(
    objects: <ModelObject>[
      ModelObject(
        id: 1,
        name: 'root',
        geometry: const SocketGeometry(),
        transform: Matrix4.identity(),
      ),
      // What every vertex is already fully bound to; a stroke paints onto
      // the other one, `jointId`.
      ModelObject(
        id: 4,
        name: 'other',
        geometry: const SocketGeometry(),
        transform: Matrix4.identity(),
      ),
      ModelObject(
        id: 2,
        name: 'cube',
        geometry: EditedGeometry(mesh),
        transform: Matrix4.identity(),
        skeletonIndex: 0,
      ),
    ],
    skeletons: <ProjectSkeleton>[
      ProjectSkeleton(
        joints: <int>[1, 4],
        inverseBindMatrices: <Matrix4>[Matrix4.identity(), Matrix4.identity()],
      ),
    ],
    nextId: 5,
  );
  final history = ModelHistory(project);
  final stage = ModelerStage.fromProject(
    device: it.device,
    project: history.project,
  );
  stage.frameSubject();
  final cubit = ModelerCubit()
    ..opened(
      history,
      renderer: Renderer.create(device: it.device),
      stage: stage,
    );
  final session = WeightPaintSession(
    cubit: cubit,
    history: () => (cubit.state as ModelerReady).history,
    stage: () => (cubit.state as ModelerReady).stage,
  );
  return (cubit: cubit, session: session, mesh: mesh, objectId: 2, jointId: 4);
}

ModelerReady ready(ModelerCubit cubit) => cubit.state as ModelerReady;

/// The centre of the viewport `openedWith`'s own stage was framed for — the
/// same 800×600 shape `transform_session_test.dart` already picks.
PickingView _view(ModelerCubit cubit) =>
    PickingView(camera: ready(cubit).stage.camera, size: const Size(800, 600));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one drag made of five pointer-move samples produces exactly one '
      'history step', () {
    final made = openedWith();
    final before = made.mesh.toBytes();
    final view = _view(made.cubit);

    final int? firstHit = made.session.pointerDown(
      view: view,
      at: const Offset(400, 300),
      objectId: made.objectId,
      skeletonIndex: 0,
      joint: made.jointId,
      radiusPixels: 400,
      strength: 0.2,
      mode: PaintWeightsMode.paint,
      mirror: false,
      normalize: true,
    );
    // Sanity: the ray actually landed on the cube, or every assertion
    // below would pass just as happily against a stroke that painted
    // nothing at all.
    expect(firstHit, isNotNull);

    for (var i = 0; i < 5; i++) {
      made.session.pointerMove(
        view: view,
        at: Offset(400 + i.toDouble(), 300),
        radiusPixels: 400,
        strength: 0.2,
        mode: PaintWeightsMode.paint,
        mirror: false,
        normalize: true,
      );
    }
    made.session.pointerUp();

    final history = ready(made.cubit).history;

    // Mutation: run each sample as its own step, or never close the
    // transaction at all — either leaves this at something other than
    // exactly one.
    expect(history.steps, hasLength(1));
    expect(history.canUndo, isTrue);
    expect(history.undoSays, 'paint weights');
    expect(made.mesh.toBytes(), isNot(equals(before)));

    // One undo reverts the whole stroke, not one sample of it.
    expect(history.undo(), isTrue);
    expect(made.mesh.toBytes(), before);
    expect(history.canUndo, isFalse);
  });

  test('pointerUp with nothing open is a no-op', () {
    final made = openedWith();
    final history = ready(made.cubit).history;
    made.session.pointerUp();
    expect(history.canUndo, isFalse);
    expect(made.session.isActive, isFalse);
  });

  test('a second pointerDown while one is already open does nothing new', () {
    final made = openedWith();
    final view = _view(made.cubit);
    made.session.pointerDown(
      view: view,
      at: const Offset(400, 300),
      objectId: made.objectId,
      skeletonIndex: 0,
      joint: made.jointId,
      radiusPixels: 400,
      strength: 0.2,
      mode: PaintWeightsMode.paint,
      mirror: false,
      normalize: true,
    );
    expect(made.session.isActive, isTrue);

    // Mutation: open a second transaction on top of the first —
    // `ModelHistory.beginTransaction` itself throws past that, which this
    // guard exists to never reach.
    final int? second = made.session.pointerDown(
      view: view,
      at: const Offset(400, 300),
      objectId: made.objectId,
      skeletonIndex: 0,
      joint: made.jointId,
      radiusPixels: 400,
      strength: 0.2,
      mode: PaintWeightsMode.paint,
      mirror: false,
      normalize: true,
    );
    expect(second, isNull);

    made.session.pointerUp();
    expect(ready(made.cubit).history.steps, hasLength(1));
  });

  test('a joint that is not on the named skeleton opens nothing', () {
    final made = openedWith();
    final view = _view(made.cubit);

    final int? hit = made.session.pointerDown(
      view: view,
      at: const Offset(400, 300),
      objectId: made.objectId,
      skeletonIndex: 0,
      joint: 999,
      radiusPixels: 400,
      strength: 0.2,
      mode: PaintWeightsMode.paint,
      mirror: false,
      normalize: true,
    );

    expect(hit, isNull);
    expect(made.session.isActive, isFalse);
    expect(ready(made.cubit).history.canUndo, isFalse);
  });
}
