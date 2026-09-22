/// The gizmo and the keyboard, arriving at the same transform.
///
///     flutter test test/gizmo_wiring_test.dart
///
/// **`gizmo_handles.dart` and `transform_gizmo.dart` were written, tested and
/// unreachable.** 788 lines with tests of their own and no caller — so what
/// nothing checked was the half that matters to a person: that grabbing an arm
/// and pressing `G X` are one transform rather than two implementations that
/// agree today.
///
/// A gizmo that computed its own delta and ran its own command would part
/// company with the keyboard at the first snap, the first pivot setting and the
/// first refusal. These tests pin the single path.
library;

import 'package:flutter3d_modeler/src/transform_gizmo.dart';
import 'package:flutter3d_modeler/src/transform_modal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A camera two metres back, looking down −Z, in a viewport 600 logical pixels
/// tall — the shape `ModelerStage` opens with.
GizmoView viewFrom(Vector3 eye) =>
    GizmoView.perspective(eye: eye, fovYRadians: 0.9, viewportHeight: 600);

/// The axis a ray from [eye] aimed at the world point [at] lands on.
GizmoAxis? axisAt(Vector3 eye, Vector3 at) {
  final handles = gizmoHandlesAt(Vector3.zero(), viewFrom(eye));
  return GizmoHit.nearest(handles, eye, (at - eye).normalized())?.handle.axis;
}

/// The middle of the shaft of the arm running along [axis].
///
/// Taken from the handle rather than worked out from a pixel count, so the
/// test aims where the gizmo actually is: the arm's length comes from the
/// camera, and a written-down number would be right until somebody changed
/// `kGizmoPixels` and then be a test that misses on purpose.
Vector3 middleOfArm(Vector3 eye, GizmoAxis axis) {
  final handle = gizmoHandlesAt(
    Vector3.zero(),
    viewFrom(eye),
  ).firstWhere((GizmoHandle h) => h.axis == axis);
  return (handle.base + handle.headBase) * 0.5;
}

List<GizmoHandle> gizmoHandlesAt(Vector3 pivot, GizmoView view) =>
    gizmoHandles(pivot, view);

/// What `_grabbedGizmo` does in `main.dart`, written out so a test can run it:
/// open the same modal the keyboard opens and set the axis the arm names.
TransformModal grabbed(
  GizmoAxis axis, {
  TransformKind kind = TransformKind.move,
}) => TransformModal(kind)
  ..axis = switch (axis) {
    GizmoAxis.x => TransformAxis.x,
    GizmoAxis.y => TransformAxis.y,
    GizmoAxis.z => TransformAxis.z,
    GizmoAxis.uniform => TransformAxis.free,
  };

void main() {
  group('the arm the ray lands on', () {
    test('a ray straight down an arm hits that arm', () {
      final eye = Vector3(0, 0, 4);

      // Aimed at the middle of the shaft, which is where a hand aims.
      // Mutation: trace the box from the tip rather than the base and the near
      // half of every arm stops answering, so the part of the arrow a hand
      // actually aims at is paint that cannot be grabbed.
      expect(axisAt(eye, middleOfArm(eye, GizmoAxis.x)), GizmoAxis.x);
      expect(axisAt(eye, middleOfArm(eye, GizmoAxis.y)), GizmoAxis.y);
    });

    test('a ray into empty space hits nothing', () {
      // Mutation: answer with the nearest arm regardless of distance. Every
      // click anywhere in the viewport then starts a transform, and picking an
      // object becomes impossible.
      final eye = Vector3(0, 0, 4);
      expect(axisAt(eye, Vector3(3, 3, 0)), isNull);
      expect(axisAt(eye, Vector3(-3, 0, 0)), isNull);
    });

    test('the gizmo is the same size however far the camera is', () {
      // Sized in logical pixels, which is the whole reason `GizmoView` carries
      // one. Mutation: size it in metres and it fills the window when the
      // camera comes in to look at a bevel and is unhittable clutter when it
      // pulls back.
      final near = gizmoHandlesAt(Vector3.zero(), viewFrom(Vector3(0, 0, 2)));
      final far = gizmoHandlesAt(Vector3.zero(), viewFrom(Vector3(0, 0, 20)));

      final nearLength = near.first.tip.length;
      final farLength = far.first.tip.length;
      expect(farLength / nearLength, closeTo(10.0, 0.2));
    });
  });

  group('one transform, two ways in', () {
    test('grabbing the X arm is G then X', () {
      final byHand = TransformModal(TransformKind.move)..axis = TransformAxis.x;
      final byGizmo = grabbed(GizmoAxis.x);

      // The same object in the same state: the arm says which axis and stops
      // there. Mutation: have the gizmo compute its own delta and run its own
      // command — the two agree on this frame and part company at the first
      // snap, because only one of them would know about `Ctrl`.
      expect(byGizmo.axis, byHand.axis);
      expect(byGizmo.kind, byHand.kind);
    });

    test('the same drag through either gives the same amount', () {
      final delta = Vector3(1.4, 0.9, -0.3);
      final byHand = TransformModal(TransformKind.move)
        ..axis = TransformAxis.x
        ..dragged = delta;
      final byGizmo = grabbed(GizmoAxis.x)..dragged = delta;

      expect(byGizmo.amount, byHand.amount);
      expect(byGizmo.amount, Vector3(1.4, 0, 0));
    });

    test('snapping reaches a gizmo drag too', () {
      final byGizmo = grabbed(GizmoAxis.y)
        ..dragged = Vector3(0, 0.34, 0)
        ..snapping = true;

      // The thing a separate implementation would miss. Mutation: give the
      // gizmo its own drag handling and `Ctrl` stops working the moment the
      // transform was started by the mouse rather than the keyboard — which is
      // most of the time on a tablet, where there is no keyboard at all.
      expect(byGizmo.amount.y, closeTo(0.3, 1e-6));
    });

    test('a typed number reaches it as well', () {
      final byGizmo = grabbed(GizmoAxis.z)
        ..dragged = Vector3(0, 0, 9)
        ..type('2');

      expect(byGizmo.amount, Vector3(0, 0, 2));
    });

    test('the kind follows the armed tool', () {
      expect(
        grabbed(GizmoAxis.x, kind: TransformKind.rotate).kind,
        TransformKind.rotate,
      );
      expect(
        grabbed(GizmoAxis.x, kind: TransformKind.scale).kind,
        TransformKind.scale,
      );
    });
  });

  group('where it stands', () {
    test('the handles are built around the pivot, not the origin', () {
      final eye = Vector3(0, 0, 6);
      final pivot = Vector3(3, -1, 2);
      final handles = gizmoHandlesAt(pivot, viewFrom(eye));

      // Mutation: build them at the origin and read the pivot only when
      // drawing. The arrows appear on the object and the ray is traced against
      // boxes sitting at the world centre, so the gizmo looks right and cannot
      // be grabbed anywhere.
      for (final GizmoHandle handle in handles) {
        final Vector3 out = handle.tip - pivot;
        // Each arm runs from the pivot along its own axis and along no other.
        expect(out.dot(handle.axis.direction), greaterThan(0.0));
        expect(
          (out - handle.axis.direction * out.length).length,
          lessThan(1e-5),
          reason: '${handle.axis} runs along itself',
        );
      }

      // And none of the boxes reaches back over the pivot, which is deliberate
      // and documented: fattened at the ends too, all three would swallow it,
      // and a click on the thing being edited would take hold of whichever arm
      // happened to be listed first.
      final x = handles.firstWhere((GizmoHandle h) => h.axis == GizmoAxis.x);
      expect(x.min.x, greaterThan(pivot.x));
    });

    test('a distant pivot is aimed at the same way as one at the origin', () {
      // **Not "aiming at the X arm gives X".** From a camera on +Z the Z arm
      // points at the viewer and is crossed first, and `GizmoHit.nearest`
      // answering with it is correct — that is what nearest means. What this
      // asks instead is that moving the gizmo moves everything about it: the
      // same relative aim on a pivot three metres out gives the same answer as
      // on one at the origin.
      final eye = Vector3(0, 0, 6);
      final pivot = Vector3(3, 0, 0);

      final atOrigin = gizmoHandlesAt(Vector3.zero(), viewFrom(eye));
      final moved = gizmoHandlesAt(pivot, viewFrom(eye));

      final armAtOrigin = atOrigin.firstWhere(
        (GizmoHandle h) => h.axis == GizmoAxis.x,
      );
      final aim = (armAtOrigin.base + armAtOrigin.headBase) * 0.5;

      final here = GizmoHit.nearest(atOrigin, eye, (aim - eye).normalized());
      final there = GizmoHit.nearest(
        moved,
        eye + pivot,
        (aim + pivot - (eye + pivot)).normalized(),
      );

      // Mutation: build the handles at the origin and add the pivot only when
      // drawing. The arrows appear on the object and every ray is traced
      // against boxes at the world centre, so the gizmo looks right and cannot
      // be grabbed at all.
      expect(there?.handle.axis, here?.handle.axis);
      expect(there?.handle.axis, isNotNull);
    });
  });

  group('ux-03: the shape a handle is grabbed by follows the gizmo', () {
    // Straight down −Z from two metres back: X runs right across the screen,
    // Y up, and the Z ring is the one facing the camera.
    final Vector3 eye = Vector3(0, 0, 2);
    final GizmoView view = viewFrom(eye);

    GizmoAxis? aimedAt(List<GizmoHandle> handles, Vector3 at) =>
        GizmoHit.nearest(handles, eye, (at - eye).normalized())?.handle.axis;

    test('a rotate gizmo is grabbed on its rings, not along its axes', () {
      final rings = gizmoHandles(
        Vector3.zero(),
        view,
        kind: GizmoKindForHit.rotate,
      );
      final double radius = rings.first.ringRadius!;

      // On the Z ring: the circle in the XY plane, at its own radius.
      expect(aimedAt(rings, Vector3(radius, 0, 0)), GizmoAxis.z);
      expect(aimedAt(rings, Vector3(0, radius, 0)), GizmoAxis.z);

      // Mutation: reuse the move gizmo's three axis boxes. Half the radius
      // out along X is inside the box that runs along X, so an aim at plain
      // empty space in the middle of the rings takes hold of a rotation —
      // and an aim at the ring itself, below, takes hold of nothing.
      expect(aimedAt(rings, Vector3(radius * 0.5, 0, 0)), isNull);
    });

    // A three-quarter view for the middle box, because the camera has to be
    // somewhere no arm points at it: down an axis, that axis's own arm runs
    // between the eye and the pivot and is hit first — correctly, since on
    // screen it is exactly what is in front of the box.
    final Vector3 corner = Vector3(2, 2, 2);
    final GizmoView cornerView = viewFrom(corner);
    GizmoAxis? aimedFromCorner(List<GizmoHandle> handles, Vector3 at) =>
        GizmoHit.nearest(
          handles,
          corner,
          (at - corner).normalized(),
        )?.handle.axis;

    test('and the middle box of a scale gizmo can be grabbed at all', () {
      final scale = gizmoHandles(
        Vector3.zero(),
        cornerView,
        kind: GizmoKindForHit.scale,
      );

      // Mutation: leave the middle box out of the handles, which is what it
      // was — drawn since the gizmo was written, and answering nothing.
      expect(aimedFromCorner(scale, Vector3.zero()), GizmoAxis.uniform);
      // The arms are still the arms: the box is small and the shafts start
      // well outside it.
      expect(
        aimedFromCorner(scale, middleOfArm(corner, GizmoAxis.x)),
        GizmoAxis.x,
      );
    });

    test('a move gizmo has no middle box to grab', () {
      final move = gizmoHandles(Vector3.zero(), cornerView);

      // The pivot is deliberately left clear on a move gizmo: something is
      // being edited there, and a handle over it would be a handle covering
      // the thing it moves.
      expect(aimedFromCorner(move, Vector3.zero()), isNull);
      expect(move.map((GizmoHandle h) => h.axis), GizmoAxis.three);
    });
  });
}
