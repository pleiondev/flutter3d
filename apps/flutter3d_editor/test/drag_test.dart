/// A thing dragged with the mouse, without a mouse.
///
///     flutter test test/drag_test.dart
///
/// **A drag is a list of rays and one entry in the history.** Everything the
/// gesture is made of — which bar was taken hold of, which way that bar lets
/// the thing go, where the pointer is now pointing on that line, and what the
/// undo stack is left holding — is arithmetic on a document, so it is asked
/// here without a window, a device or a frame.
///
/// The last of those is the one that pays for this file. A pointer reports
/// sixty times a second and the document moves on every report; recorded one
/// by one that is sixty steps a second, so the sixty-four a person has are
/// gone before the button comes up and the change they actually wanted back
/// went with them. What this asserts is that the whole drag undoes in one
/// press — and it fails, loudly, the moment the transaction around it goes.
library;

import 'package:flutter3d_editor/src/editor_state.dart';
import 'package:flutter3d_editor/src/scene_dressing.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// One brush, two metres across, at the origin — and something else beside it
/// so that "the document moved" cannot be true of the whole level at once.
Editing _open() => Editing(
  level: Level.fromJson(<String, Object?>{
    'version': 1,
    'materials': <String, Object?>{
      'stone': <String, Object?>{
        'baseColor': <double>[0.7, 0.7, 0.7, 1.0],
      },
    },
    'brushes': <Object?>[
      <String, Object?>{
        'at': <double>[0.0, 0.0, 0.0],
        'size': <double>[2.0, 2.0, 2.0],
        'material': 'stone',
      },
      <String, Object?>{
        'at': <double>[8.0, 0.0, 0.0],
        'size': <double>[2.0, 2.0, 2.0],
        'material': 'stone',
      },
    ],
  }),
  path: 'memory.json',
);

/// Where the camera stands for every drag here: back along +Z, looking at the
/// origin, so no axis of the cage is anywhere near edge on.
final Vector3 _eye = Vector3(0.0, 0.0, 10.0);

/// Which way [_eye] has to point to aim at [target].
Vector3 _at(Vector3 target) => (target - _eye).normalized();

/// The cage the editor draws around the selected brush, as bars.
///
/// The same numbers `SceneDressing.placeMarker` uses — its own size, six per
/// cent proud of it — written here rather than reached through a device.
List<GizmoBar> _barsAround(Editing editing) => gizmoBarsAround(
  editing.where!,
  (editing.brush?.size ?? Vector3.all(kGizmoSize)) * 1.06,
);

/// How many steps deep the history is, found the only way it can be asked:
/// by going back until there is nowhere left to go.
int _undoDepth(Editing editing) {
  var steps = 0;
  while (editing.canUndo) {
    editing.undo();
    steps++;
  }
  return steps;
}

void main() {
  test('a drag along a bar moves the brush and leaves one step', () {
    final editing = _open()..select(Piece.brush, 0);
    final bars = _barsAround(editing);

    // The top near bar that runs along X: at the cage's own +Y +Z corner, and
    // three metres of it to aim at.
    final grip = Vector3(0.0, 1.06, 1.06);
    final drag = AxisDrag.start(bars, editing, _eye, _at(grip));
    expect(drag, isNotNull, reason: 'the ray was aimed down a bar of the cage');
    expect(drag!.axis, EditorAxis.x);

    // Four reports of a pointer sliding to the right, each aimed at a point
    // that much further along the bar than where the hand took hold — which is
    // what a hand moving a hand's width across a trackpad looks like to this.
    for (final x in <double>[0.4, 0.9, 1.3, 1.55]) {
      drag.moveTo(editing, _eye, _at(drag.grabbed + Vector3(x, 0.0, 0.0)));
    }
    expect(
      editing.level.brushes[0].centre.x,
      closeTo(1.5, 1e-9),
      reason: 'the brush follows the pointer, snapped to the quarter metre',
    );
    expect(editing.level.brushes[0].centre.y, 0.0);
    expect(editing.level.brushes[0].centre.z, 0.0);
    expect(
      editing.level.brushes[1].centre.x,
      8.0,
      reason: 'only what is selected moves',
    );

    expect(
      editing.canUndo,
      isFalse,
      reason: 'nothing is recorded until the button comes up',
    );
    expect(drag.finish(editing), isTrue);
    expect(
      editing.level.brushes[0].centre.x,
      closeTo(1.5, 1e-9),
      reason: 'ending the drag leaves the brush exactly where it was dragged',
    );

    // **The whole point.** One press of undo, and the level is back — not
    // four, one per report of a pointer that happened to be moving.
    expect(editing.history.undoSays, 'drag by 1.50, 0.00, 0.00');
    expect(_undoDepth(editing), 1);
    expect(editing.level.brushes[0].centre.x, 0.0);
  });

  test('the bar that was grabbed is the axis the thing moves along', () {
    // The same document, the same pointer travel, an upright bar instead: what
    // changes is the axis, and only the axis.
    final editing = _open()..select(Piece.brush, 0);
    final grip = Vector3(1.06, 0.0, 1.06);
    final drag = AxisDrag.start(_barsAround(editing), editing, _eye, _at(grip));
    expect(drag?.axis, EditorAxis.y);

    drag!.moveTo(editing, _eye, _at(drag.grabbed + Vector3(0.0, 2.0, 0.0)));
    final centre = editing.level.brushes[0].centre;
    expect(centre.y, closeTo(2.0, 1e-9));
    expect(centre.x, 0.0, reason: 'a vertical bar does not move it sideways');
    expect(centre.z, 0.0);
  });

  test('a drag that goes nowhere leaves the history alone', () {
    // A grab, a wobble inside the same grid square, and a release: an undo
    // that has to be pressed twice because one press does nothing visible is
    // an undo nobody trusts.
    final editing = _open()..select(Piece.brush, 0);
    final grip = Vector3(0.0, 1.06, 1.06);
    final drag = AxisDrag.start(_barsAround(editing), editing, _eye, _at(grip));

    drag!.moveTo(editing, _eye, _at(drag.grabbed + Vector3(0.05, 0.0, 0.0)));
    expect(drag.finish(editing), isFalse);
    expect(editing.canUndo, isFalse);
    expect(editing.level.brushes[0].centre.x, 0.0);
  });

  test('a press that misses every bar is the camera, not the brush', () {
    // **The decision the press has to make, and it makes it from a ray.** The
    // middle of the brush's own face is drawn geometry and no bar of the cage,
    // so it turns the camera — which is what keeps looking around reachable
    // without a modifier or a second button.
    final editing = _open()..select(Piece.brush, 0);
    final bars = _barsAround(editing);

    expect(
      AxisDrag.start(bars, editing, _eye, _at(Vector3(0.0, 0.0, 1.0))),
      isNull,
      reason: 'the face of the brush is not a bar',
    );
    expect(
      AxisDrag.start(bars, editing, _eye, _at(Vector3(0.0, 6.0, 0.0))),
      isNull,
      reason: 'the ceiling above it is not a bar either',
    );

    // And a document with nothing selected has no cage at all, so nothing to
    // take hold of: the camera is all one button does.
    final nothing = _open();
    expect(
      AxisDrag.start(bars, nothing, _eye, _at(Vector3(0.0, 1.06, 1.06))),
      isNull,
    );
  });

  test('the bars a click meets are the bars the cage draws', () {
    // Every bar sits on the cage: on two of the three faces its axis is not,
    // and along the third for the cage's whole width. Four of each, twelve in
    // all, which is what makes the picture and the target the same thing.
    final size = Vector3(4.0, 2.0, 6.0);
    final bars = gizmoBarsAround(Vector3(1.0, 2.0, 3.0), size);
    expect(bars, hasLength(12));

    for (final axis in EditorAxis.values) {
      expect(bars.where((GizmoBar it) => it.axis == axis), hasLength(4));
    }

    final along = bars.where((GizmoBar it) => it.axis == EditorAxis.x);
    for (final bar in along) {
      final centre = (bar.min + bar.max) / 2.0;
      expect(
        bar.max.x - bar.min.x,
        closeTo(size.x + kGrabMargin * 2, 1e-5),
        reason: 'a bar along X is as long as the cage is wide',
      );
      expect((centre.y - 2.0).abs(), closeTo(size.y / 2.0, 1e-5));
      expect((centre.z - 3.0).abs(), closeTo(size.z / 2.0, 1e-5));
      expect(
        bar.max.y - bar.min.y,
        greaterThan(kGrabMargin * 2),
        reason: 'wider than the drawn bar, or nobody can put a mouse on it',
      );
    }
  });
}
