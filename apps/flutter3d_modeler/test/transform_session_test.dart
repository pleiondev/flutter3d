/// The modal transform, the gizmo it shares a path with, and `view-26n`'s
/// geometry snap, driven end to end against a real `ModelerCubit` and a real
/// (software-rasterised) `ModelerStage` — no fakes, the same real objects
/// `main.dart` injects.
///
///     flutter test test/transform_session_test.dart
library;

import 'dart:math' as math;
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

      made.session.dragged(
        const Offset(40, 0),
        600,
        viewOver(made.cubit),
        const Offset(340, 300),
      );

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
    made.session.dragged(
      const Offset(40, 0),
      600,
      viewOver(made.cubit),
      const Offset(340, 300),
    );

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

    made.session.dragged(
      const Offset(40, 0),
      600,
      viewOver(made.cubit),
      const Offset(340, 300),
    );
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
    made.session.dragged(
      const Offset(40, 0),
      600,
      viewOver(made.cubit),
      const Offset(340, 300),
    );

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

  group('tut-18: forget() and the other-object picker cache', () {
    // A fixed camera on +Z looking down -Z, the same one
    // `element_picking_test.dart`'s own `viewLookingAtTheCube` and
    // `geometry_snap_test.dart` already trust — used here instead of
    // whatever a `ModelerStage` happens to frame, so a snap search's answer
    // depends only on the mesh being searched, not on the camera a stage
    // built around a different project would have chosen.
    PickingView fixedView() => PickingView(
      camera: CameraNode(
        projection: PerspectiveProjection(
          fovYRadians: math.pi / 4,
          near: 0.1,
          far: 100.0,
        ),
      )..setPosition(0.0, 0.0, 5.0),
      size: const Size(800.0, 600.0),
    );

    // A project with an "edited" object under a mesh-mode selection (so
    // `modalFor` has something to anchor on) and an "other" object a
    // geometry snap can search, always sitting at the same world offset —
    // only [otherSize] tells the two documents below apart, because
    // `_otherSnapSources` rebuilds `objectToWorld` fresh from the *current*
    // project on every call regardless of the picker cache; what a stale
    // cache entry could leak is the other object's own local geometry, not
    // its transform, so that is the one thing this fixture varies.
    ModelProject sceneWith(double otherSize) => const ModelProject()
        .added(
          (int id) => ModelObject(
            id: id,
            name: 'edited',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
          ),
        )
        .added(
          (int id) => ModelObject(
            id: id,
            name: 'other',
            geometry: EditedGeometry(
              EditMesh.cuboid(size: Vector3.all(otherSize)),
            ),
            transform: Matrix4.translation(Vector3(0.5, 0.0, 0.0)),
            // The same version in both documents below — the collision
            // `tut-18`'s own row is about. A version bumped on every edit
            // would never coincide by accident, so this is chosen on
            // purpose rather than left to whatever `.added` happens to
            // default to.
            version: 7,
          ),
        );

    // Document A's own "other" object: a two-unit cube shifted along X, the
    // same fixture `geometry_snap_test.dart`'s own "a vertex within reach
    // snaps to its exact position" test uses — its corner at local
    // (1, 1, 1) sits at world (1.5, 1, 1).
    final projectA = sceneWith(2.0);
    // Document B's own "other" object: the same id, version and world
    // transform, but a cube two centimetres on a side — nothing on it sits
    // anywhere near (1.5, 1, 1) unless a stale picker built against
    // document A's own geometry answers for it instead.
    final projectB = sceneWith(0.02);

    test('opening a second document with a colliding id/version forgets the '
        "first document's own picker, rather than answering with it", () {
      final editedIdA = projectA.objects
          .firstWhere((ModelObject o) => o.name == 'edited')
          .id;
      final otherIdA = projectA.objects
          .firstWhere((ModelObject o) => o.name == 'other')
          .id;
      final editedIdB = projectB.objects
          .firstWhere((ModelObject o) => o.name == 'edited')
          .id;
      final otherIdB = projectB.objects
          .firstWhere((ModelObject o) => o.name == 'other')
          .id;
      expect(
        otherIdB,
        otherIdA,
        reason:
            'the fixture is only proving what it claims to if the '
            "second document's own object really does collide with the "
            "first's, id and version both — a fresh `ModelProject` "
            'starts numbering from the same ids again',
      );

      var historyBox = ModelHistory(projectA);
      historyBox.selection = ProjectSelection(
        mode: SelectionMode.mesh,
        objects: <int>[editedIdA],
      );
      final session = TransformSession(
        cubit: ModelerCubit(),
        history: () => historyBox,
        editMesh: () => editMeshOf(historyBox.project, historyBox.selection),
      );

      final modalA = session.modalFor('mesh.move');
      modalA.snapping = true;
      modalA.dragged = Vector3(1.51, 1.01, 1.0);
      session.updateGeometrySnap(modalA, fixedView());

      // Sanity check on the mechanism itself, before the bug this test is
      // about ever comes into play: a search that cannot find document
      // A's own corner cannot prove anything about a stale one either.
      expect(session.snapTarget, isNotNull);
      expect(session.snapTarget!.sourceId, otherIdA);
      expect(session.snapTarget!.position, Vector3(1.5, 1.0, 1.0));
      session.commit();

      // Document B opens — the same swap `_installOpened` makes — and
      // forgets the picker cache the way it now does too.
      historyBox = ModelHistory(projectB);
      historyBox.selection = ProjectSelection(
        mode: SelectionMode.mesh,
        objects: <int>[editedIdB],
      );
      session.forget();

      final modalB = session.modalFor('mesh.move');
      modalB.snapping = true;
      modalB.dragged = Vector3(1.51, 1.01, 1.0);
      session.updateGeometrySnap(modalB, fixedView());

      // Mutation: drop the `forget()` call `_installOpened` makes (or
      // this method doing nothing at all). Either leaves document A's
      // own two-unit picker in the cache, keyed by the id and version
      // document B's own tiny "other" object happens to share, and the
      // search below still finds document A's corner even though
      // document B's actual geometry there is a centimetre across.
      expect(session.snapTarget, isNull);
      session.commit();
    });

    test("without forget(), a stale picker really would answer for the "
        'colliding id/version — proving the scenario above is a real bug, '
        'not an unreachable one', () {
      final editedIdA = projectA.objects
          .firstWhere((ModelObject o) => o.name == 'edited')
          .id;
      final editedIdB = projectB.objects
          .firstWhere((ModelObject o) => o.name == 'edited')
          .id;

      var historyBox = ModelHistory(projectA);
      historyBox.selection = ProjectSelection(
        mode: SelectionMode.mesh,
        objects: <int>[editedIdA],
      );
      final session = TransformSession(
        cubit: ModelerCubit(),
        history: () => historyBox,
        editMesh: () => editMeshOf(historyBox.project, historyBox.selection),
      );

      final modalA = session.modalFor('mesh.move');
      modalA.snapping = true;
      modalA.dragged = Vector3(1.51, 1.01, 1.0);
      session.updateGeometrySnap(modalA, fixedView());
      expect(session.snapTarget, isNotNull);
      session.commit();

      historyBox = ModelHistory(projectB);
      historyBox.selection = ProjectSelection(
        mode: SelectionMode.mesh,
        objects: <int>[editedIdB],
      );
      // No `session.forget()` here — document B is opened over document
      // A's own still-cached picker, exactly what `tut-18`'s own row
      // described before this pass fixed it.

      final modalB = session.modalFor('mesh.move');
      modalB.snapping = true;
      modalB.dragged = Vector3(1.51, 1.01, 1.0);
      session.updateGeometrySnap(modalB, fixedView());

      expect(session.snapTarget, isNotNull);
      expect(session.snapTarget!.position, Vector3(1.5, 1.0, 1.0));
      session.commit();
    });
  });

  group('ux-12: the pivot and the space chips reach a drag', () {
    /// Two cubes, four metres apart, both selected and both turned a
    /// quarter-turn about Y so that "its own axes" is a different direction
    /// for each of them.
    ({ModelerCubit cubit, TransformSession session}) twoFacingApart() {
      final made = openedWith(cubes(2));
      final List<ModelObject> objects = ready(made.cubit).project.objects;
      ready(made.cubit).history.selection = ProjectSelection(
        objects: objects.map((ModelObject it) => it.id).toList(),
      );
      // The second one faces a quarter-turn round from the first.
      made.cubit.ran(
        SetTransform(
          id: objects[1].id,
          to: Matrix4.compose(
            Vector3(4, 0, 0),
            Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2),
            Vector3.all(1),
          ),
        ),
      );
      return made;
    }

    List<Vector3> placesIn(ModelerCubit cubit) => <Vector3>[
      for (final ModelObject it in ready(cubit).project.objects)
        it.transform.getTranslation(),
    ];

    test('under "individual" a turn leaves both centres where they are', () {
      final made = twoFacingApart();
      made.session.pivot = () => TransformPivot.individual;
      made.cubit.tool('object.rotate');
      final List<Vector3> before = placesIn(made.cubit);

      final PickingView view = viewOver(made.cubit);
      final Offset pivot = view.project(made.session.middleOfSelection())!;
      final Offset from = pivot + const Offset(120, 0);
      final Offset to = pivot + const Offset(0, -120);
      made.session.dragged(to - from, 600, view, to);

      // Mutation: ignore the chip and turn about the median, which is what a
      // drag did. Two objects four metres apart swing round each other
      // instead of spinning where they stand — which is the whole difference
      // between the two chips, and it was only ever honoured for a number
      // typed into the panel.
      final List<Vector3> after = placesIn(made.cubit);
      expect((after[0] - before[0]).length, lessThan(1e-6));
      expect((after[1] - before[1]).length, lessThan(1e-6));
    });

    test('and under "median" the same drag swings them round each other', () {
      final made = twoFacingApart();
      made.session.pivot = () => TransformPivot.median;
      made.cubit.tool('object.rotate');
      final List<Vector3> before = placesIn(made.cubit);

      final PickingView view = viewOver(made.cubit);
      final Offset pivot = view.project(made.session.middleOfSelection())!;
      final Offset from = pivot + const Offset(120, 0);
      final Offset to = pivot + const Offset(0, -120);
      made.session.dragged(to - from, 600, view, to);

      final List<Vector3> after = placesIn(made.cubit);
      expect((after[0] - before[0]).length, greaterThan(0.1));
    });

    test('under "local" a move follows each object\'s own axes', () {
      final made = twoFacingApart();
      made.session.space = () => TransformSpace.local;
      made.cubit.tool('object.move');
      final List<Vector3> before = placesIn(made.cubit);

      made.session.dragged(
        const Offset(60, 0),
        600,
        viewOver(made.cubit),
        const Offset(460, 300),
      );

      // Mutation: send a plain `MoveBy` with no space. Both objects then go
      // the same way whatever they are facing, and the "Local" chip means
      // nothing for a drag.
      final List<Vector3> after = placesIn(made.cubit);
      final Vector3 first = after[0] - before[0];
      final Vector3 second = after[1] - before[1];
      expect(first.length, closeTo(second.length, 1e-6));
      expect(
        first.normalized().dot(second.normalized()),
        lessThan(0.9),
        reason: 'one is a quarter-turn round from the other',
      );
    });

    test('and under "global" both go the same way', () {
      final made = twoFacingApart();
      made.session.space = () => TransformSpace.global;
      made.cubit.tool('object.move');
      final List<Vector3> before = placesIn(made.cubit);

      made.session.dragged(
        const Offset(60, 0),
        600,
        viewOver(made.cubit),
        const Offset(460, 300),
      );

      final List<Vector3> after = placesIn(made.cubit);
      expect(
        (after[0] - before[0] - (after[1] - before[1])).length,
        lessThan(1e-6),
      );
    });
  });

  group('ux-11: the transform starts with the key', () {
    test('G opens it at once, and the pointer drives it with nothing held', () {
      final made = openedWith(cubes(1));
      final id = ready(made.cubit).project.objects.single.id;
      ready(made.cubit).history.selection = ProjectSelection(objects: [id]);
      made.cubit.tool('object.move');

      expect(made.session.followsPointer, isFalse);
      made.session.startOnPress('object.move');

      // Mutation: arm the tool and wait for a button, which is the other
      // preset — under this one `X` between the key and the first move falls
      // through to whatever `X` means otherwise, which is delete.
      expect(made.session.modal, isNotNull);
      expect(made.session.followsPointer, isTrue);
      expect(
        made.session.modalKey(LogicalKeyboardKey.keyX, null),
        isTrue,
        reason: 'the axis keys belong to the transform from the key press on',
      );
      expect(made.session.modal!.axis, TransformAxis.x);
    });

    test('with nothing selected it starts nothing at all', () {
      final made = openedWith(cubes(1));
      made.cubit.tool('object.move');

      // An open transaction with nothing in it is a step somebody would have
      // to press Escape to be rid of, for a key they pressed by accident.
      made.session.startOnPress('object.move');

      expect(made.session.modal, isNull);
      expect(made.session.followsPointer, isFalse);
    });

    test('and accepting it puts the pointer back in charge of nothing', () {
      final made = openedWith(cubes(1));
      final id = ready(made.cubit).project.objects.single.id;
      ready(made.cubit).history.selection = ProjectSelection(objects: [id]);
      made.cubit.tool('object.move');
      made.session
        ..startOnPress('object.move')
        ..commit();

      expect(made.session.followsPointer, isFalse);
    });
  });

  group('ux-11: a turn follows the hand around the pivot', () {
    /// How far the object ended up turned, about whatever axis — an
    /// unconstrained turn goes about the one the camera is looking down, and
    /// what this asks is the size of the turn rather than its direction.
    double turnedBy(ModelerCubit cubit) {
      final Quaternion q = Quaternion.fromRotation(
        ready(cubit).project.objects.single.transform.getRotation(),
      );
      return 2 * math.acos(q.w.clamp(-1.0, 1.0));
    }

    test('a quarter turn of the hand is a quarter turn of the model', () {
      final made = openedWith(cubes(1));
      final id = ready(made.cubit).project.objects.single.id;
      ready(made.cubit).history.selection = ProjectSelection(objects: [id]);
      made.cubit.tool('object.rotate');
      final PickingView view = viewOver(made.cubit);
      final Offset pivot = view.project(made.session.middleOfSelection())!;

      // A hand at three o'clock, swung to twelve: a quarter turn, whatever
      // the radius. Mutation: read the horizontal travel and multiply by a
      // hundredth — the same sweep at twice the radius then turns the model
      // twice as far, and a sweep around the near side of the pivot barely
      // turns it at all.
      const double radius = 120;
      final Offset from = pivot + const Offset(radius, 0);
      final Offset to = pivot + const Offset(0, -radius);
      made.session.dragged(to - from, 600, view, to);

      expect(turnedBy(made.cubit).abs(), closeTo(math.pi / 2, 1e-4));
    });

    test(
      'and under "arm, then drag" the axis key is taken before the drag',
      () {
        final made = openedWith(cubes(1));
        final id = ready(made.cubit).project.objects.single.id;
        ready(made.cubit).history.selection = ProjectSelection(objects: [id]);
        made.cubit.tool('object.move');

        // No modal yet: the tool is armed and nothing has been dragged. This is
        // the window the review found — `X` here fell through to whatever else
        // `X` is bound to, which under the modal preset is delete.
        expect(made.session.modal, isNull);
        expect(made.session.modalKey(LogicalKeyboardKey.keyX, null), isTrue);

        made.session.dragged(
          const Offset(40, 25),
          600,
          viewOver(made.cubit),
          const Offset(440, 275),
        );

        // Mutation: drop the remembered axis on the floor. The drag then moves
        // the object in two directions after somebody asked for one.
        expect(made.session.modal!.axis, TransformAxis.x);
        final Vector3 moved = ready(
          made.cubit,
        ).project.objects.single.transform.getTranslation();
        expect(moved.x, isNot(0));
        expect(moved.y, 0);
        expect(moved.z, 0);
      },
    );

    test('Shift with an axis key names the plane across it', () async {
      final made = openedWith(cubes(1));
      final id = ready(made.cubit).project.objects.single.id;
      ready(made.cubit).history.selection = ProjectSelection(objects: [id]);
      made.cubit.tool('object.move');
      made.session.startOnPress('object.move');

      await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      made.session.modalKey(LogicalKeyboardKey.keyZ, null);
      await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      // Mutation: ignore the modifier. `Shift+Z` then means the Z axis, which
      // is the opposite of what the hand that pressed it was asking for —
      // and the person finds out by watching the model go the wrong way.
      expect(made.session.modal!.axis, TransformAxis.xy);
    });

    test('Shift is a tenth of the travel', () async {
      Future<double> movedBy({required bool precise}) async {
        final made = openedWith(cubes(1));
        final id = ready(made.cubit).project.objects.single.id;
        ready(made.cubit).history.selection = ProjectSelection(objects: [id]);
        made.cubit.tool('object.move');
        if (precise) {
          await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        made.session.dragged(
          const Offset(80, 0),
          600,
          viewOver(made.cubit),
          const Offset(400, 300),
        );
        if (precise) await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        return ready(
          made.cubit,
        ).project.objects.single.transform.getTranslation().x;
      }

      final double plain = await movedBy(precise: false);
      final double fine = await movedBy(precise: true);

      // Mutation: read the modifier nowhere. The same drag then moves the
      // object the same distance whatever is held, and there is no way to
      // place anything more finely than a pixel is worth at the distance the
      // camera happens to be at.
      expect(plain.abs(), greaterThan(0));
      expect(fine.abs(), closeTo(plain.abs() * 0.1, 1e-6));
    });
  });
}
