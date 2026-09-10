/// The manipulator, driven by rays instead of by a hand.
///
///     flutter test test/transform_gizmo_test.dart
///
/// **A drag is a list of rays and one entry in the history.** Which arrow was
/// taken hold of, which way that arrow lets the thing go, how far along it the
/// pointer is now aiming, and what the undo stack is owed when the button comes
/// up — all of it is arithmetic on a pivot and a camera, so all of it is asked
/// here without a window, a device or a frame.
///
/// Two of these tests pay for the file on their own. One is the undo step: a
/// pointer reports sixty times a second, and a gesture recorded report by
/// report empties a sixty-four step history in a second. The other is
/// steadiness — the same selection and the same camera have to give the same
/// numbers to the last bit, because a gizmo that shivers while nothing is
/// happening is the bug people describe as "the editor flickers".
library;

import 'package:flutter3d_modeler/src/transform_gizmo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Where the camera stands for most of these: back along +Z, looking at the
/// origin.
final Vector3 _eye = Vector3(0.0, 0.0, 10.0);

/// A camera off every axis, for the questions where an arrow pointing straight
/// at the viewer would decide the answer instead of the arithmetic.
final Vector3 _oblique = Vector3(7.0, 6.0, 8.0);

/// The view a 720-pixel-tall viewport with a 0.9 radian field of view gives.
GizmoView _view([Vector3? eye]) => GizmoView.perspective(
  eye: eye ?? _eye,
  fovYRadians: 0.9,
  viewportHeight: 720.0,
);

/// Which way [from] has to point to aim at [target].
Vector3 _at(Vector3 target, [Vector3? from]) =>
    (target - (from ?? _eye)).normalized();

/// A thing being moved, and the history it is supposed to leave behind: the
/// smallest document a drag can be told about, so the count of steps means
/// exactly what it says.
final class _Doc {
  Vector3 position = Vector3.zero();
  final List<String> history = <String>[];

  /// What the caller does on every pointer report: the picture moves, nothing
  /// is recorded.
  void show(Vector3 start, GizmoDrag drag) => position = start + drag.offset;

  /// What the caller does when the button comes up: back to where it started,
  /// then the whole move at once, inside one transaction.
  void commit(Vector3 start, GizmoDrag drag) {
    if (!drag.moved) return;
    position = start;
    history.add(drag.label);
    position = start + drag.offset;
  }
}

void main() {
  test('a ray along X grabs the X arrow and moves the thing along X', () {
    final handles = gizmoHandles(Vector3.zero(), _view());
    expect(handles, hasLength(3));

    // Aimed at a point most of the way along the X arrow, which is where a
    // hand puts the cursor when it means "move this sideways".
    final drag = GizmoDrag.start(handles, _eye, _at(Vector3(0.8, 0.0, 0.0)));
    expect(drag, isNotNull, reason: 'the ray was aimed down the X arrow');
    // Mutation: label each handle with the next axis round
    // (`axis: GizmoAxis.values[(axis.index + 1) % 3]`), which leaves every
    // arrow drawn and grabbable exactly where it is and only changes which way
    // it lets a thing go. That is the shape this gets wrong in practice — the
    // arrow under the hand points right and the object walks up into the air.
    // Run: this fails with `GizmoAxis.y`, and so do four other tests.
    expect(drag!.axis, GizmoAxis.x);

    // Four reports of a hand sliding to the right, each aimed that much
    // further along the arrow than where it took hold.
    final doc = _Doc();
    final start = Vector3.copy(doc.position);
    for (final x in <double>[0.4, 0.9, 1.3, 1.55]) {
      drag.moveTo(_eye, _at(drag.grabbed + Vector3(x, 0.0, 0.0)));
      doc.show(start, drag);
    }

    // Mutation: drop the `/ spread` from the closest approach in `moveTo`. The
    // thing still moves along X and still follows the pointer's direction, so
    // it looks plausible — it just travels the wrong distance (1.467 instead
    // of 1.55 from this camera, and further out the more of an angle the
    // camera is at), which is a manipulator that never quite lands where it
    // was aimed. Run: this fails, the axis checks do not.
    //
    // A millionth rather than a billionth because `Vector3` is Float32List
    // underneath: 1.55 stored in it is 1.549999952, and a tolerance tight
    // enough to catch that would be a test that fails on arithmetic nobody
    // here chose.
    expect(doc.position.x, closeTo(1.55, 1e-6));
    expect(doc.position.y, 0.0, reason: 'the X arrow does not lift it');
    expect(doc.position.z, 0.0);
  });

  test('the whole drag is one step, not one per pointer report', () {
    final handles = gizmoHandles(Vector3.zero(), _view());
    final drag = GizmoDrag.start(handles, _eye, _at(Vector3(0.8, 0.0, 0.0)))!;
    final doc = _Doc();
    final start = Vector3.copy(doc.position);

    for (final x in <double>[0.4, 0.9, 1.3, 1.55]) {
      drag.moveTo(_eye, _at(drag.grabbed + Vector3(x, 0.0, 0.0)));
      doc.show(start, drag);
      expect(
        doc.history,
        isEmpty,
        reason: 'nothing is recorded until the button comes up',
      );
    }
    expect(drag.moves, 4, reason: 'four reports of the pointer');

    // Mutation: `_offset.add(wanted)` instead of `_offset.setFrom(wanted)` in
    // `moveTo` — an accumulating drag rather than one that answers where the
    // pointer is now. The thing then travels 2.85 metres for a hand that moved
    // 1.55, and it runs away faster the longer the drag lasts. Run: this
    // fails, and so does the count of reports above — one of the four lands on
    // the total the previous three already reached and is dropped as no
    // movement at all.
    expect(drag.offset.x, closeTo(1.55, 1e-6));

    doc.commit(start, drag);
    // **The whole point.** One press of undo puts it back, not four because a
    // pointer happened to be moving.
    expect(doc.history, hasLength(1));
    expect(doc.history.single, 'move by 1.55, 0.00, 0.00');
    expect(
      doc.position.x,
      closeTo(1.55, 1e-6),
      reason: 'committing leaves it exactly where the drag left it',
    );

    // Mutation: make `moved` answer `true` unconditionally. A wobble inside
    // one pixel then leaves a step behind, and an undo that has to be pressed
    // twice because the first press does nothing visible is an undo nobody
    // trusts. Run: `moved` below fails, and the empty history with it.
    final nothing = GizmoDrag.start(
      handles,
      _eye,
      _at(Vector3(0.8, 0.0, 0.0)),
    )!;
    final still = _Doc();
    nothing.moveTo(_eye, _at(nothing.grabbed));
    expect(nothing.moved, isFalse);
    still.commit(Vector3.zero(), nothing);
    expect(still.history, isEmpty);
  });

  test('the modifier snaps the travel, not the position', () {
    // The thing does not start on any round number, which is the case a model
    // read from a file is always in.
    final start = Vector3(0.13, 0.0, -0.07);
    final handles = gizmoHandles(start, _view());
    final drag = GizmoDrag.start(
      handles,
      _eye,
      _at(start + Vector3(0.8, 0.0, 0.0)),
    )!;
    expect(drag.axis, GizmoAxis.x);

    drag.moveTo(_eye, _at(drag.grabbed + Vector3(1.55, 0.0, 0.0)), snap: true);

    // Mutation: round where the thing ends up rather than how far it went —
    // `grabbed + line * travelled`, each component onto the quarter metre. The
    // travel comes out 1.5837 instead of 1.50, because the thing is dragged
    // onto somebody's grid rather than by the amount the hand asked for. On a
    // model whose parts were placed by its author at no round number at all,
    // that tears a wheel off its axle the moment the modifier goes down. Run:
    // this fails.
    expect(drag.offset.x, closeTo(1.5, 1e-6));

    // The two below are honest guards rather than mutation-tested assertions:
    // every mutation tried that puts a snapped drag off its axis also gets the
    // travel wrong, so the line above fails first and these never run. They
    // stay because "snapped" must not come to mean "and also sideways".
    expect(drag.offset.y, 0.0);
    expect(drag.offset.z, 0.0);

    // Mutation: `(travelled / step).floorToDouble()`. A hand that has moved
    // 1.55 metres reads as 1.5 either way, which is why this second aim is
    // here: 1.63 rounds up to 1.75 and floors down to 1.50, and a modifier
    // that always rounds down is one that drags things short of where they
    // were aimed. Run: this fails.
    drag.moveTo(_eye, _at(drag.grabbed + Vector3(1.63, 0.0, 0.0)), snap: true);
    expect(drag.offset.x, closeTo(1.75, 1e-6));

    // And without the modifier the hand is believed exactly.
    drag.moveTo(_eye, _at(drag.grabbed + Vector3(1.63, 0.0, 0.0)));
    expect(drag.offset.x, closeTo(1.63, 1e-6));
  });

  test('the same pivot and camera draw the same gizmo every time', () {
    final pivot = Vector3(0.4, -1.2, 0.9);
    final view = _view();
    final first = gizmoGeometry(gizmoHandles(pivot, view)).buffer.asUint8List();

    for (var frame = 2; frame <= 6; frame++) {
      final next = gizmoGeometry(
        gizmoHandles(pivot, view),
      ).buffer.asUint8List();
      // Mutation: give `gizmoHandles` a counter of its own and ease the length
      // towards its target from the last call's value — the shape every
      // "smoothed" gizmo takes. Nothing about the picture is wrong in a still
      // frame, and it shivers for a few frames after every camera move. Run:
      // frame 2 differs from frame 1 and this fails.
      expect(
        next,
        orderedEquals(first),
        reason: 'frame $frame is a different gizmo from the first',
      );
    }

    // And it is not steady because it ignores the camera: move the eye and the
    // numbers move with it. Without this, returning a constant would pass the
    // check above.
    final moved = gizmoGeometry(
      gizmoHandles(pivot, _view(Vector3(0.0, 0.0, 20.0))),
    ).buffer.asUint8List();
    expect(moved, isNot(orderedEquals(first)));
  });

  test('the gizmo is the same size on screen at any distance', () {
    final near = gizmoHandles(Vector3.zero(), _view(Vector3(0.0, 0.0, 10.0)));
    final far = gizmoHandles(Vector3.zero(), _view(Vector3(0.0, 0.0, 20.0)));

    final nearLength = near.first.tip.length;
    final farLength = far.first.tip.length;

    // Mutation: drop the depth factor from `GizmoView.worldSize`, so the arrows
    // are a fixed length in metres. The two lengths then match, and the gizmo
    // fills the window when the camera comes in to look at a bevel and becomes
    // a few unclickable pixels when it pulls back to see the whole model. Run:
    // this fails.
    expect(
      farLength,
      closeTo(nearLength * 2.0, 1e-9),
      reason: 'twice as far away is twice as long in the world',
    );
    // Which is the same number of pixels on screen, and that is the point.
    expect(farLength / 20.0, closeTo(nearLength / 10.0, 1e-12));

    // An orthographic camera is the one case where distance does not enter
    // into it: the picture does not change as the eye backs away, so neither
    // does the gizmo. Mutation: make `worldSize` multiply by depth regardless
    // of `perspective` — the arrows then grow while the model stands still.
    // Run: this fails.
    Vector3 orthoTip(double z) => gizmoHandles(
      Vector3.zero(),
      GizmoView.orthographic(
        eye: Vector3(0.0, 0.0, z),
        height: 4.0,
        viewportHeight: 720.0,
      ),
    ).first.tip;
    expect(orthoTip(30.0).x, closeTo(orthoTip(10.0).x, 1e-12));
  });

  test('a press that misses every arrow belongs to the camera', () {
    final handles = gizmoHandles(Vector3.zero(), _view(_oblique));

    // The pivot itself, from a camera that is down none of the three arrows.
    // The middle of the gizmo is the thing being edited, and a click there has
    // to reach the model rather than take hold of whichever arm was listed
    // first.
    // Mutation: fatten the grab boxes at their ends as well as sideways
    // (`_minOf(base, tip) - Vector3.all(slack)`). All three boxes then swallow
    // the pivot and this fails — which is the bug where clicking the object
    // you can see starts dragging it along an axis you did not choose.
    expect(
      GizmoHit.nearest(handles, _oblique, _at(Vector3.zero(), _oblique)),
      isNull,
    );

    // Well clear of all three, which is most of the window.
    expect(
      GizmoHit.nearest(
        handles,
        _oblique,
        _at(Vector3(0.0, -3.0, 0.0), _oblique),
      ),
      isNull,
      reason: 'there is no arrow along −Y',
    );
    expect(GizmoDrag.start(handles, _oblique, Vector3(0.0, -1.0, 0.0)), isNull);

    // And the arrows themselves are all reachable from a camera like this one,
    // or the miss above would be proving nothing.
    for (final axis in GizmoAxis.values) {
      final target = axis.direction * 1.0;
      final hit = GizmoHit.nearest(handles, _oblique, _at(target, _oblique));
      expect(hit?.axis, axis, reason: 'the $axis arrow can be taken hold of');
    }
  });

  test('an arrow aimed at the viewer refuses to move rather than bolt', () {
    // Looking straight down the Z arrow: it is grabbable, because it is drawn
    // right there under the cursor, and there is no point of it the pointer is
    // meaningfully nearer to aiming at.
    final handles = gizmoHandles(Vector3.zero(), _view());
    final drag = GizmoDrag.start(handles, _eye, _at(Vector3.zero()))!;
    expect(drag.axis, GizmoAxis.z);

    expect(drag.moveTo(_eye, _at(Vector3(0.0, 0.0, -0.5))), isFalse);

    // And a hand two hundredths of a metre off exactly down the axis, which is
    // what a real pointer gives: still no point of the line it is meaningfully
    // nearer to aiming at.
    //
    // Mutation: narrow the guard to `spread <= 0.0`, so only a ray exactly
    // along the axis is refused. This aim, two centimetres off it, then sends
    // the object 8.71 metres down Z on one report of the pointer — out of the
    // window, and back from somewhere else on the next report. Run: the aim
    // below answers true and both checks after it fail.
    expect(drag.moveTo(_eye, _at(Vector3(0.02, 0.0, 0.0))), isFalse);
    expect(drag.offset, Vector3.zero());
    expect(drag.moved, isFalse);
  });

  test('the X arrow is #FF6B8A', () {
    final handles = gizmoHandles(Vector3.zero(), _view());
    final x = handles.firstWhere((GizmoHandle it) => it.axis == GizmoAxis.x);

    // Mutation: give the X arrow `kGizmoTintY`. Every channel below is out by
    // more than two, and what a person sees is a green arrow moving things
    // sideways — three arms of colours that no longer mean anything.
    expect(((x.colour.x * 255.0).round() - 0xFF).abs(), lessThanOrEqualTo(2));
    expect(((x.colour.y * 255.0).round() - 0x6B).abs(), lessThanOrEqualTo(2));
    expect(((x.colour.z * 255.0).round() - 0x8A).abs(), lessThanOrEqualTo(2));

    // The other two are the same three numbers rotated, so no arrow is heavier
    // than the others. Mutation: darken Y to `0x4A9F3B` and the sum below
    // stops matching. Run: this fails.
    for (final handle in handles) {
      final channels = <int>[
        (handle.colour.x * 255.0).round(),
        (handle.colour.y * 255.0).round(),
        (handle.colour.z * 255.0).round(),
      ]..sort();
      expect(channels, <int>[0x6B, 0x8A, 0xFF]);
    }
  });

  test('an arrow is grabbable where it is drawn', () {
    // **The picture and the target are one description.** Built apart they
    // agree until the day one of them is tidied, and that day the gizmo is
    // drawn in one place and grabbable in another — which reads as the mouse
    // being broken rather than as the gizmo being wrong.
    final handles = gizmoHandles(Vector3(1.0, 2.0, 3.0), _view(_oblique));

    for (final handle in handles) {
      final direction = handle.axis.direction;
      expect(
        handle.headBase.distanceTo(handle.base),
        greaterThan(0.0),
        reason: 'the shaft has some length before the head starts',
      );

      // Every point of the drawn arrow, from the root of the shaft to the very
      // point of the head, is inside the box a ray is traced against.
      // Mutation: start the box where the head starts rather than at the base,
      // so the box covers the arrowhead alone. The shaft is then drawn but not
      // grabbable, and three quarters of what a person aims at does nothing.
      // Run: this fails at the base, and four other tests go with it.
      for (final at in <Vector3>[
        handle.base,
        handle.headBase,
        handle.tip,
        handle.base + direction * 0.001,
      ]) {
        for (var axis = 0; axis < 3; axis++) {
          expect(at[axis], greaterThanOrEqualTo(handle.min[axis] - 1e-12));
          expect(at[axis], lessThanOrEqualTo(handle.max[axis] + 1e-12));
        }
      }

      // And the box is wider than the drawn shaft, or nobody can put a mouse
      // on it. Mutation: `slack` of exactly the shaft's own radius, which is
      // the tempting tidy-up — the target is then the two pixels of line that
      // are drawn, and only a very still hand can grab it. Run: this fails.
      for (var axis = 0; axis < 3; axis++) {
        if (direction[axis] != 0.0) continue;
        expect(
          handle.max[axis] - handle.min[axis],
          greaterThan(handle.shaftRadius * 4.0),
        );
      }
    }
  });
}
