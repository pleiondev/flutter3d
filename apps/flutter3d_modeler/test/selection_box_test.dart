/// What a dragged rectangle means, and where it stops being one.
///
///     flutter test test/selection_box_test.dart
///
/// **Four of the five groups need no geometry at all**, which is the point of
/// `selection_box.dart` being separate from the overlay that draws it: whether
/// a drag is a box, and what a box does to a set of ids, are questions about
/// two points and a modifier. The numbers below are logical pixels because that
/// is what a pointer arrives in.
///
/// The last group is the seam. `pickElementsIn` has been tested since view-10
/// against a cube whose corners are known numbers, but it has never had a
/// caller; this file writes the first one, so the cube comes back for one test
/// to show a drag going all the way through to a selection. [screenOf] is the
/// perspective divide done by hand for the same reason
/// `element_picking_test.dart` does it: asking `PickingView` where a corner
/// lands and then dragging a box there would pass with the y axis flipped.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, PointerDeviceKind, Rect, Size;

import 'package:flutter3d/flutter3d.dart'
    show CameraNode, PerspectiveProjection;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/element_picking.dart';
import 'package:flutter3d_modeler/src/selection_box.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const Size viewport = Size(800.0, 600.0);
const double fovY = math.pi / 4.0;
const double eyeZ = 5.0;

/// Where [world] lands on screen, worked out here rather than asked of the code
/// under test.
Offset screenOf(Vector3 world) {
  final focal = 1.0 / math.tan(fovY / 2.0);
  final depth = eyeZ - world.z;
  final aspect = viewport.width / viewport.height;
  return Offset(
    ((world.x * focal / (aspect * depth)) + 1.0) * viewport.width / 2.0,
    (1.0 - world.y * focal / depth) * viewport.height / 2.0,
  );
}

/// The camera on +Z, looking down -Z, which is where an unrotated node looks.
PickingView viewLookingAtTheCube() => PickingView(
  camera: CameraNode(
    projection: PerspectiveProjection(fovYRadians: fovY, near: 0.1, far: 100.0),
  )..setPosition(0.0, 0.0, eyeZ),
  size: viewport,
);

/// A mesh with the tree a viewport keeps beside it.
MeshPicker pickerFor(EditMesh mesh) =>
    MeshPicker(mesh, MeshBvh(mesh, MeshLayoutPlan()..build(mesh)));

/// The live vertex at [point], so a test can name a corner without depending on
/// the order `EditMesh.cuboid` happens to add them in.
int vertexAt(EditMesh mesh, Vector3 point) {
  final at = Vector3.zero();
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    if (mesh.positionOf(vertex, at).distanceTo(point) < 1e-6) return vertex;
  }
  fail('no vertex at $point');
}

SelectionBox _dragged(
  Offset from,
  Offset to, {
  PointerDeviceKind pointer = PointerDeviceKind.mouse,
}) => SelectionBox(from: from, pointer: pointer)..to = to;

void main() {
  group('the rectangle two corners make', () {
    test('is the same region whichever way it was dragged', () {
      const start = Offset(400.0, 300.0);
      const end = Offset(310.0, 220.0);

      // Up and to the left is the same instruction as down and to the right.
      // Mutation: `Rect.fromLTRB(from.dx, from.dy, to.dx, to.dy)` in place of
      // `Rect.fromPoints`. Run, and the backwards drag comes back as
      // `Rect.fromLTRB(400.0, 300.0, 310.0, 220.0)` — negative width, negative
      // height, `isEmpty` true — so `isBox` is false and `pickElementsIn`
      // refuses it. Half of the drags a person makes select nothing.
      expect(_dragged(start, end).rect, _dragged(end, start).rect);
      expect(
        _dragged(start, end).rect,
        const Rect.fromLTRB(310.0, 220.0, 400.0, 300.0),
      );
    });

    test('starts as no rectangle at all', () {
      // A box begins at the pointer-down, before there is a second corner, and
      // it has to be answerable then: the overlay asks for `rect` on the frame
      // the button goes down. Mutation: `to = to ?? Offset.zero` for
      // `to ?? from`, which is the plausible way to spell "no second corner
      // yet". Run, and the first line fails with
      // `Rect.fromLTRB(0.0, 0.0, 120.0, 90.0)` — the press drags a rectangle
      // out of the viewport's corner, so the overlay paints a box nobody has
      // drawn and a release on the frame after pointer-down replaces the
      // selection with whatever that quarter of the screen covers.
      final box = SelectionBox(
        from: const Offset(120.0, 90.0),
        pointer: PointerDeviceKind.mouse,
      );
      expect(box.rect, Rect.zero.shift(const Offset(120.0, 90.0)));
      expect(box.isBox, isFalse);
      expect(box.mode, SelectionBoxMode.replace);
    });
  });

  group('a drag is a box only once it has grown', () {
    test('a wobble under the threshold stays a click', () {
      // Three pixels across and two down, which is a hand letting go of a
      // mouse button. Mutation: `isBox => !rect.isEmpty`. Run, and this wobble
      // becomes a box: in replace mode it selects whatever slice of the front
      // face those three pixels covered and throws the rest of the selection
      // away, so a shaky click loses the selection.
      expect(
        _dragged(const Offset(100.0, 100.0), const Offset(103.0, 102.0)).isBox,
        isFalse,
      );

      // Exactly the threshold counts. Mutation: `>` for `>=`. Run, and a drag
      // of exactly four pixels is a click, which puts the one number this file
      // is about on the wrong side of its own boundary.
      expect(
        _dragged(const Offset(100.0, 100.0), const Offset(100.0, 104.0)).isBox,
        isTrue,
      );

      // A hair under four. Mutation: `cursorBoxSlop = 3.5`, which is the kind
      // of drift a tidy-up makes without anybody arguing for it. Run, and this
      // drag comes back a box. Between the three-pixel wobble and this, the
      // constant is held to the interval (3.75, 4.0] — a real is never pinned
      // to a point by a boundary pair, and the interval is narrow enough that
      // the doc's "half the pick slack" cannot become something else in
      // silence.
      expect(
        _dragged(const Offset(100.0, 100.0), const Offset(100.0, 103.75)).isBox,
        isFalse,
      );
    });

    test('two pixels wide and three hundred tall is a box', () {
      // Somebody selecting a column of vertices, which is the most precise
      // gesture in the set. Mutation: `rect.shortestSide >= boxSlopFor(...)`.
      // Run, and this comes back false: the deliberate thin box is read as a
      // click on wherever the drag started, and in replace mode the column the
      // person wanted becomes one element.
      expect(
        _dragged(const Offset(200.0, 40.0), const Offset(202.0, 340.0)).isBox,
        isTrue,
      );
    });

    test('a fingertip has to travel three times as far', () {
      const from = Offset(200.0, 200.0);
      const to = Offset(206.0, 205.0);

      // Six pixels is a millimetre of glass, which is inside the roll of a
      // thumb pressing a button. Mutation: drop the switch in `boxSlopFor` and
      // answer `cursorBoxSlop` for everything. Run, and the touch case fails:
      // every tap on a touchscreen that rolls a millimetre becomes a replace
      // box and clears the selection.
      expect(
        _dragged(from, to, pointer: PointerDeviceKind.touch).isBox,
        isFalse,
      );
      expect(_dragged(from, to).isBox, isTrue);

      // An unknown device is a finger, matching `pickSlackFor`. Mutation: send
      // `unknown` to `cursorBoxSlop`. Run, and this fails.
      expect(
        _dragged(from, to, pointer: PointerDeviceKind.unknown).isBox,
        isFalse,
      );

      // A stylus and a trackpad put a visible hotspot where the person aimed,
      // so they are cursors.
      expect(
        _dragged(from, to, pointer: PointerDeviceKind.stylus).isBox,
        isTrue,
      );
      expect(
        _dragged(from, to, pointer: PointerDeviceKind.trackpad).isBox,
        isTrue,
      );
    });

    test('twelve pixels of fingertip is a box, and ten is a thumb', () {
      const from = Offset(200.0, 200.0);

      // The test above holds `fingerBoxSlop` from underneath only: a six-pixel
      // drag expected false needs the number to be more than six and asks
      // nothing else of it. Mutation: `fingerBoxSlop = 999.0`. Run, and the
      // first line here fails, which is every touch drag on the device
      // becoming a click on wherever the finger landed and a box gesture that
      // a touchscreen cannot make at all.
      expect(
        _dragged(
          from,
          const Offset(200.0, 212.0),
          pointer: PointerDeviceKind.touch,
        ).isBox,
        isTrue,
      );

      // Ten is still inside the eight to ten millimetres of glass a fingertip
      // covers, so it is a press that rolled. With the line above, the
      // constant is held to (10.0, 12.0], and with the four-pixel pair in the
      // first test that is the three the doc argues.
      expect(
        _dragged(
          from,
          const Offset(200.0, 210.0),
          pointer: PointerDeviceKind.touch,
        ).isBox,
        isFalse,
      );
    });
  });

  group('the modifiers being held', () {
    test('name the mode, and control wins over shift', () {
      expect(
        SelectionBoxMode.forModifiers(extend: false, subtract: false),
        SelectionBoxMode.replace,
      );
      expect(
        SelectionBoxMode.forModifiers(extend: true, subtract: false),
        SelectionBoxMode.add,
      );
      expect(
        SelectionBoxMode.forModifiers(extend: false, subtract: true),
        SelectionBoxMode.subtract,
      );

      // Both down at once. Mutation: put the `(true, _)` case first, so shift
      // wins. Run, and this fails. The mutation that matters more is answering
      // `replace` when the pair is ambiguous — somebody holding two amending
      // modifiers is the one person certainly not asking for the whole
      // selection to be discarded.
      expect(
        SelectionBoxMode.forModifiers(extend: true, subtract: true),
        SelectionBoxMode.subtract,
      );
    });
  });

  group('what a released box does to the selection', () {
    test('a bare box replaces, however much it caught', () {
      // Mutation: return `selection` for the replace case. Run, and this fails
      // — a plain box then only ever grows the selection and there is no
      // gesture left that means "these and nothing else".
      expect(
        applyBox(<int>{1, 2, 3}, <int>{7, 8}, mode: SelectionBoxMode.replace),
        <int>{7, 8},
      );

      // A box over empty space clears, which is what a drag across the
      // background means and the only way back to nothing selected.
      expect(
        applyBox(<int>{1, 2}, <int>{}, mode: SelectionBoxMode.replace),
        isEmpty,
      );
    });

    test('shift adds, and adding something already selected keeps it', () {
      // The case a toggle gets wrong. `applyPick` removes on a shift-click of
      // something already selected because a click has no other subtract
      // gesture; a box has control, so shift here is a union.
      //
      // Mutation: `<T>{...selection, ...caught}` replaced by the symmetric
      // difference — `{...selection, ...caught}` less `selection ∩ caught`.
      // Run, and this fails on id 2: dragging a shift box over a region that
      // overlaps what is already selected silently drops the overlap, which is
      // the half the person was trying to keep and cannot see.
      expect(
        applyBox(<int>{1, 2}, <int>{2, 3}, mode: SelectionBoxMode.add),
        <int>{1, 2, 3},
      );

      // Order: what was already selected keeps its place and the new catch
      // lands after it, so the last member is the most recently caught.
      // Mutation: `<T>{...caught, ...selection}`. Run, and this fails — the
      // active id jumps back to something picked two gestures ago whenever a
      // box overlaps the existing selection.
      expect(
        applyBox(<int>{1, 2}, <int>{2, 3}, mode: SelectionBoxMode.add).toList(),
        <int>[1, 2, 3],
      );
    });

    test('control subtracts, and subtracting what was never there is quiet', () {
      // Mutation: `caught.where((held) => !selection.contains(held))` — the
      // difference taken the other way round. Run, and this fails: a subtract
      // box hands back the part of its own catch that was not selected, so
      // control-dragging over a selection selects the things it was told to
      // remove.
      expect(
        applyBox(<int>{1, 2, 3}, <int>{2}, mode: SelectionBoxMode.subtract),
        <int>{1, 3},
      );

      // Half of what the box caught was never selected, which is what every
      // subtract drag across a partly-selected region looks like. Nothing is
      // an error and nothing is added.
      expect(
        applyBox(<int>{1, 2}, <int>{2, 9}, mode: SelectionBoxMode.subtract),
        <int>{1},
      );

      // Mutation: `selection.difference(caught)` reads the same and is the same
      // answer, which was run — the whole suite stays green. The `where` is
      // kept because it is the spelling that states the order, and the version
      // above is the one that was got wrong first.
      expect(
        applyBox(<int>{1, 2}, <int>{7}, mode: SelectionBoxMode.subtract),
        <int>{1, 2},
      );
    });

    test('every mode answers with a copy nothing can edit afterwards', () {
      final live = <int>{1, 2};

      // The copying is `Set.unmodifiable`'s doing, not the `where`'s, so the
      // mutation has to skip it: `caught.isEmpty && mode == subtract` short
      // circuits to `selection` itself before the switch. Run, and this comes
      // back `Set:[1, 2, 3]` against `Set:[1, 2]` — the cubit's next edit of
      // its own set silently rewrites the value it has already published.
      final taken = applyBox(live, <int>{}, mode: SelectionBoxMode.subtract);
      live.add(3);
      expect(taken, <int>{1, 2});

      // Mutation: `Set<T>.of` for `Set<T>.unmodifiable`. Run, and this fails.
      expect(() => taken.add(4), throwsUnsupportedError);

      // Replace is where the aliasing hazard is live rather than theoretical:
      // it is the bare drag, the default mode, and its answer is the set
      // `pickElementsIn` just built. Mutation:
      // `mode == SelectionBoxMode.replace ? caught : Set<T>.unmodifiable(...)`,
      // which is the shortcut somebody takes on the grounds that replace
      // changes nothing. Run, and the line after the edit fails with
      // `Set:[7, 8, 9]` against `Set:[7, 8]` — the picker's working set is
      // published, and whatever it does next rewrites a selection already
      // handed out.
      final enclosed = <int>{7, 8};
      final replaced = applyBox(
        <int>{1, 2},
        enclosed,
        mode: SelectionBoxMode.replace,
      );
      enclosed.add(9);
      expect(replaced, <int>{7, 8});
      expect(() => replaced.add(4), throwsUnsupportedError);

      // Add builds a set of its own, so no amount of editing the arguments
      // afterwards can catch a path that forgot the wrapper; the edit is what
      // catches it. Mutation:
      // `mode == SelectionBoxMode.add ? <T>{...selection, ...caught} : ...`.
      // Run, and the union comes back writable, `add(3)` succeeds and this
      // line fails for want of the throw.
      final joined = applyBox(<int>{1}, <int>{2}, mode: SelectionBoxMode.add);
      expect(() => joined.add(3), throwsUnsupportedError);
    });
  });

  group('the whole gesture, against the cube', () {
    test('a shift box over the top of the front face adds both corners', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final left = vertexAt(mesh, Vector3(-1.0, 1.0, 1.0));
      final right = vertexAt(mesh, Vector3(1.0, 1.0, 1.0));

      // A drag up and to the left, from just outside the top right corner of
      // the front face to just outside the top left one. It is deliberately
      // backwards: this is the drag a person makes about half the time, and it
      // is the one a caller keeping the corners as they came gets wrong.
      final box = _dragged(
        screenOf(Vector3(1.15, 0.85, 1.0)),
        screenOf(Vector3(-1.15, 1.15, 1.0)),
      )..mode = SelectionBoxMode.add;
      expect(
        box.isBox,
        isTrue,
        reason: 'four hundred and sixteen pixels wide, fifty-four tall',
      );

      final caught = pickElementsIn(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        rect: box.rect,
        level: ElementLevel.vertex,
      );

      // The cuboid is two units deep, so the two back corners at y = 1 sit at
      // depth six against the front face's four, and the divide pulls them in
      // to x = 279.29 and x = 520.71 — well inside this box across — at
      // y = 179.29, which is thirty-three pixels under its lower edge of
      // 146.09. They are left out because the box is tight, and that is the
      // thing to pin: drop its lower edge from `Vector3(1.15, 0.85, 1.0)` to
      // `Vector3(1.15, 0.6, 1.0)`, which puts the edge at y = 191.36, and this
      // comes back `Set:[2, 3, 6, 7]` against `Set:[7, 6]` — a box read as any
      // looser than it was drawn takes the back of the cube with it.
      expect(caught.ids.toSet(), <int>{left, right});

      // The vertex the person had already selected survives the box, which is
      // the whole of what shift is for.
      final before = <int>{vertexAt(mesh, Vector3(-1.0, -1.0, 1.0))};
      expect(applyBox(before, caught.ids.toSet(), mode: box.mode), <int>{
        ...before,
        left,
        right,
      });
    });
  });
}
