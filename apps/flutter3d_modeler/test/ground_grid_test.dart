/// The floor and the dial, both of which are arithmetic.
///
///     flutter test test/ground_grid_test.dart
///
/// **What a test can reach here and what it cannot.** Everything the grid
/// decides — which lines exist, what colour each one is, where it stops being
/// worth drawing — is a number in an [OverlayBatch] and is held to a value
/// below. What lands on a pixel is one step further on: the line batch draws
/// with no blend and a fragment stage that passes its vertex colour through, so
/// the colour asserted here is the colour a pixel gets, and the picture that
/// proves the whole chain is the viewport's own frame test once the grid is
/// wired into the stage.
///
/// The dial is tested through its three questions rather than through a
/// painter, because a painter would mean pumping a widget to ask what a quarter
/// turn is.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_modeler/src/ground_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// An overlay that knows where the camera is, with the depth nudge switched off
/// unless a test is about the nudge — a grid vertex is then exactly where the
/// builder put it, and a position can be compared to a whole number.
MeshOverlay _overlay({required Vector3 eye, double biasPixels = 0}) {
  final overlay = MeshOverlay(
    vertexShader: const ShaderHandle(backend: 0, name: 'DebugLineVertex'),
    fragmentShader: const ShaderHandle(backend: 1, name: 'DebugLine'),
  )..biasPixels = biasPixels;
  overlay.lookFrom(
    eye: eye,
    right: Vector3(1, 0, 0),
    up: Vector3(0, 1, 0),
    pixel: 0.01,
  );
  return overlay;
}

Float32List _floatsOf(OverlayBatch batch) => Float32List.sublistView(
  batch.vertexBytes.buffer.asByteData(
    batch.vertexBytes.offsetInBytes,
    batch.vertexBytes.lengthInBytes,
  ),
);

List<Vector3> _positionsOf(OverlayBatch batch) {
  final floats = _floatsOf(batch);
  return <Vector3>[
    for (var v = 0; v < batch.vertexCount; v++)
      Vector3(
        floats[v * MeshOverlay.floatsPerVertex],
        floats[v * MeshOverlay.floatsPerVertex + 1],
        floats[v * MeshOverlay.floatsPerVertex + 2],
      ),
  ];
}

/// Linear back to sRGB, the inverse of what [MeshOverlay.asDrawn] does on the
/// way in.
///
/// The overlay is encoded inside the scene pass, so everything written there is
/// a light quantity and the composite encodes it on the way out; a colour a
/// design named has to be converted going in, or the floor comes back half
/// again as bright as the hex says. That conversion is the overlay's, and this
/// undoes it so the assertions below can go on speaking in the hex the design
/// speaks in rather than in linear fractions nobody can read.
double _toSrgb(double c) => c < 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(math.max(c, 0.0), 1.0 / 2.4) - 0.055;

/// The colour of every vertex, back in the hex the design names colours in.
///
/// Rounded to eight bits on purpose: that is the width the colour reaches a
/// pixel at, and a test that compared doubles would be a test that fails on a
/// change nobody can see.
List<int> _coloursOf(OverlayBatch batch) {
  final floats = _floatsOf(batch);
  int channel(int v, int component) =>
      (_toSrgb(floats[v * MeshOverlay.floatsPerVertex + component]) * 255)
          .round()
          .clamp(0, 255);
  return <int>[
    for (var v = 0; v < batch.vertexCount; v++)
      // The alpha is a coverage rather than a colour and is not converted, on
      // either side.
      (((floats[v * MeshOverlay.floatsPerVertex + 6] * 255).round() & 0xFF) <<
              24) |
          (channel(v, 3) << 16) |
          (channel(v, 4) << 8) |
          channel(v, 5),
  ];
}

/// Where the camera ends up for a yaw and a pitch, spelled the way
/// `OrbitController.apply` spells it. The dial's answers are only right if this
/// is what they mean.
Vector3 _eyewardOf(double yaw, double pitch) => Vector3(
  math.sin(yaw) * math.cos(pitch),
  math.sin(pitch),
  math.cos(yaw) * math.cos(pitch),
);

void main() {
  group('the floor', () {
    test('every line is drawn in both directions, one cell at a time', () {
      const grid = GroundGrid(halfLines: 4, majorEvery: 2);
      final overlay = _overlay(eye: Vector3(0, 3, 6));

      final segments = grid.writeInto(
        overlay,
        eye: Vector3(0, 3, 6),
        fadeRadius: 1000,
      );

      // Nine lines each way, eight cells along each of them.
      expect(segments, 2 * 9 * 8);
      expect(overlay.lines.vertexCount, 2 * segments);
      // Mutation: `i <= halfLines` in the outer loop to `i < halfLines` gives
      // 128 segments. The user loses the last row and column of the floor —
      // a grid that is short on two sides, which reads as the model sitting
      // off-centre on it.
    });

    test('a line near the camera is the colour the design named', () {
      const grid = GroundGrid(halfLines: 4);
      final eye = Vector3(0, 1, 1);
      final overlay = _overlay(eye: eye);

      grid.writeInto(overlay, eye: eye, fadeRadius: 1000);
      final colours = _coloursOf(overlay.lines);
      final counted = <int, int>{};
      for (final colour in colours) {
        counted[colour] = (counted[colour] ?? 0) + 1;
      }

      expect(colours, contains(0xFF2A3234));
      // The ordinary line is the commonest thing on the floor, so a grid whose
      // ordinary lines were some other colour would show it here even if
      // #2A3234 appeared somewhere as an axis or a tenth.
      final commonest = counted.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      expect(commonest.key, 0xFF2A3234);
      // Mutation: `minorColour = 0xFF2A3234` to `0xFF2A3244` — a blue a person
      // cannot tell from this one by eye, which is the whole reason the
      // acceptance is a hex rather than "dark grey". The first expectation
      // fails, and the floor no longer matches the design's palette.
    });

    test('the two lines through the origin are coloured as axes', () {
      const grid = GroundGrid(halfLines: 4);
      final eye = Vector3(0, 4, 8);
      final overlay = _overlay(eye: eye);

      grid.writeInto(overlay, eye: eye, fadeRadius: 1000);
      final positions = _positionsOf(overlay.lines);
      final colours = _coloursOf(overlay.lines);

      // A segment at a time, because a vertex of a line running along Z sits at
      // z == 0 once without that line being the X axis.
      final alongX = <int>{};
      final alongZ = <int>{};
      for (var v = 0; v < positions.length; v += 2) {
        final from = positions[v];
        final to = positions[v + 1];
        if (from.z == 0 && to.z == 0) alongX.add(colours[v]);
        if (from.x == 0 && to.x == 0) alongZ.add(colours[v]);
      }

      expect(alongX, <int>{grid.axisXColour});
      expect(alongZ, <int>{grid.axisZColour});
      expect(alongX, isNot(alongZ));
      expect(alongX, isNot(contains(grid.minorColour)));
      // Mutation: pass `alongX` to the segment that runs along Z and `alongZ` to
      // the one that runs along X. The floor then says X where it means Z, and
      // a person reading the red line to decide which way to extrude moves the
      // geometry along the wrong axis.
    });

    test('every tenth line is the one a person counts distance by', () {
      const grid = GroundGrid(halfLines: 12);
      final eye = Vector3(0, 0, 0);
      final overlay = _overlay(eye: eye);

      grid.writeInto(overlay, eye: eye, fadeRadius: 1000);
      final positions = _positionsOf(overlay.lines);
      final colours = _coloursOf(overlay.lines);

      // The line running along Z at a given x: both ends of one of its cells sit
      // at that x, which no cell of a line running along X does.
      Set<int> lineAt(double x) => <int>{
        for (var v = 0; v < positions.length; v += 2)
          if (positions[v].x == x && positions[v + 1].x == x) colours[v],
      };

      expect(lineAt(10), <int>{grid.majorColour});
      expect(lineAt(-10), <int>{grid.majorColour});
      expect(lineAt(5), <int>{grid.minorColour});
      expect(lineAt(11), <int>{grid.minorColour});
      // Mutation: delete `if (majorEvery > 0 && index % majorEvery == 0) return
      // majorColour;` from `_inkFor`. Every line comes back #2A3234, and the
      // floor loses the count a person reads distance off — ten squares out
      // looks the same as eleven, so the grid is texture rather than a ruler.
      //
      // Mutation: `majorEvery = 10` to `5`. The fourth expectation fails: the
      // brighter line lands every five squares, which is a floor whose ruler is
      // marked in a unit the design did not ask for.
    });

    test('the far part of the floor fades towards the background', () {
      const grid = GroundGrid(halfLines: 20);
      final eye = Vector3(0, 0, 0);
      final overlay = _overlay(eye: eye);

      grid.writeInto(overlay, eye: eye, fadeRadius: 12);
      final positions = _positionsOf(overlay.lines);
      final colours = _coloursOf(overlay.lines);

      int greenAt(double distance) {
        for (var v = 0; v < positions.length; v++) {
          final away = positions[v].length;
          if ((away - distance).abs() < 0.51) return (colours[v] >> 8) & 0xFF;
        }
        fail('nothing was drawn about $distance units out');
      }

      // #2A3234 has a green of 0x32; the background's is 0x11. Near the camera
      // the line is its own colour, and it is dimmer the further out it goes.
      expect(greenAt(2), 0x32);
      expect(greenAt(7), lessThan(0x32));
      expect(greenAt(10), lessThan(greenAt(7)));
      expect(greenAt(10), greaterThan(0x11));
      // Mutation: `strengthAt` returning 1.0 always. Every one of these is 0x32,
      // and the user gets the grid this class exists to avoid: at a shallow
      // angle the far lines land a fraction of a pixel apart and the distance
      // crawls with moiré whenever the camera moves.
    });

    test('a line that has faded out is not written at all', () {
      const grid = GroundGrid(halfLines: 20);
      final eye = Vector3(0, 0, 0);
      final near = _overlay(eye: eye);
      final far = _overlay(eye: eye);

      final close = grid.writeInto(near, eye: eye, fadeRadius: 6);
      final everything = grid.writeInto(far, eye: eye, fadeRadius: 1000);

      expect(close, lessThan(everything ~/ 4));
      for (final at in _positionsOf(near.lines)) {
        expect(at.length, lessThan(6 + grid.spacing));
      }
      // Mutation: `strength <= _invisible` to `strength < 0` in `_segment`.
      // `close` becomes all 3280 segments — most of them a colour within one
      // 8-bit level of the background, so the batch is four times the size for
      // pixels nobody can see.
    });

    test('the floor is nudged towards the eye, the way the overlay nudges', () {
      const grid = GroundGrid(halfLines: 2);
      final eye = Vector3(0, 5, 0);
      final overlay = _overlay(eye: eye, biasPixels: 12);

      grid.writeInto(overlay, eye: eye, fadeRadius: 1000);

      // The camera is straight above, so the whole floor should have lifted.
      for (final at in _positionsOf(overlay.lines)) {
        expect(at.y, greaterThan(0));
      }
      // Mutation: write the two vertices straight into `overlay.lines` instead
      // of calling `overlay.edge`. Every y is then exactly 0, and the user sees
      // the grid flicker in and out along every face of an object whose
      // underside sits on the ground plane.
    });

    test('the fade is flat near the camera and gone at its radius', () {
      const grid = GroundGrid(solidFraction: 0.4);
      final eye = Vector3(0, 0, 0);

      double at(double distance) =>
          grid.strengthAt(Vector3(distance, 0, 0), eye: eye, fadeRadius: 10);

      expect(at(0), 1.0);
      expect(at(3.9), 1.0);
      // Four units of plateau, then six of ramp, so half way down the ramp is
      // seven units out.
      expect(at(7), closeTo(0.5, 1e-9));
      expect(at(10), 0.0);
      expect(at(40), 0.0);
      // Mutation: `solid` computed as `fadeRadius * 0.0`, so the ramp starts at
      // the camera. `at(3.9)` comes out at 0.61 — a floor that is never its own
      // colour, which also takes #2A3234 off the screen entirely and fails two
      // of the tests above.
    });

    test('height alone quietens the floor under a camera looking down', () {
      const grid = GroundGrid();
      final under = Vector3.zero();

      // The same point of the floor, directly beneath the camera every time, so
      // height is the only thing that can dim it.
      final low = grid.strengthAt(under, eye: Vector3(0, 1, 0), fadeRadius: 10);
      final high = grid.strengthAt(
        under,
        eye: Vector3(0, 8, 0),
        fadeRadius: 10,
      );
      final higher = grid.strengthAt(
        under,
        eye: Vector3(0, 9, 0),
        fadeRadius: 10,
      );

      expect(low, 1.0);
      expect(high, lessThan(1.0));
      expect(higher, lessThan(high));
      // Mutation: `point.distanceTo(eye)` to a floor-plane distance,
      // `math.sqrt(dx * dx + dz * dz)`. The point under the camera reads 1.0
      // however high the camera climbs, so the exact
      // top-down view — the one a modeller spends most of the day in — is a
      // grid at full strength however far the camera pulls back, which is the
      // moiré this class exists to avoid.
    });

    test('a fade radius of zero is no fade rather than no floor', () {
      const grid = GroundGrid(halfLines: 4);
      final eye = Vector3(0, 3, 6);
      final overlay = _overlay(eye: eye);

      final segments = grid.writeInto(overlay, eye: eye, fadeRadius: 0);

      expect(segments, 2 * 9 * 8);
      expect(_coloursOf(overlay.lines), contains(grid.minorColour));
      expect(grid.strengthAt(Vector3(500, 0, 0), eye: eye, fadeRadius: 0), 1.0);
      // Mutation: `if (fadeRadius <= 0) return 1.0;` to `return 0.0;`. Not one
      // segment is written, so a caller that asks for the grid before its camera
      // has a distance — the first frame of the viewport — gets an empty
      // viewport, which reads as a broken build rather than as a floor waiting
      // for a number.
    });

    test('the fade moves the colour and leaves the ink its own alpha', () {
      const grid = GroundGrid();
      // A half-transparent ink, so an alpha that came from anywhere else would
      // have to be a coincidence.
      final faded = grid.fadedColour(0x802A3234, 0.25);
      final whole = grid.fadedColour(0x802A3234, 1.0);

      // A [Vector4] holds its components at single precision, so 0x80/255 comes
      // back a few parts in a hundred million off and the tolerance is the width
      // of the storage rather than a hedge about the arithmetic.
      expect(faded.w, closeTo(0x80 / 255, 1e-6));
      expect(whole.w, closeTo(0x80 / 255, 1e-6));
      expect(faded.y, lessThan(whole.y));
      // Mutation: `colour.w` to `mix` in `fadedColour`. The alpha comes back as
      // the fade strength in place of the ink's own, and because the line batch
      // draws with no blend the picture is unchanged, which is
      // the trap: anything else reading these vertices — a picker, a second pass
      // that does blend, a test of the batch — sees a fade the grid deliberately
      // kept out of a channel nothing reads.
    });

    test('a floor with no major lines is a floor, not a crash', () {
      const grid = GroundGrid(halfLines: 4, majorEvery: 0);
      final eye = Vector3(0, 3, 6);
      final overlay = _overlay(eye: eye);

      grid.writeInto(overlay, eye: eye, fadeRadius: 100);

      // Mutation: drop the `majorEvery > 0 &&` half of the guard in `_inkFor`,
      // keeping the modulo, and this throws `IntegerDivisionByZeroException` on
      // the first line off the origin. Nought is a real setting — it is how a
      // caller asks for an even floor with no counting lines in it — so the
      // guard is what makes the setting exist rather than merely be accepted.
      final colours = _coloursOf(overlay.lines);
      expect(colours, contains(grid.minorColour));
      expect(colours, isNot(contains(grid.majorColour)));
    });

    test('a solid fraction of more than the whole still fades', () {
      const grid = GroundGrid(solidFraction: 2.0);
      final eye = Vector3.zero();

      // Mutation: drop the `.clamp(0.0, 0.95)` on `solidFraction`. The solid
      // part is then twice the fade radius, `distance <= solid` catches every
      // point inside it, and the arm that returns zero past the radius is
      // unreachable — a floor that is asked to fade and does not, drawn all the
      // way to the horizon at full strength, which is what the fade exists to
      // prevent.
      expect(
        grid.strengthAt(Vector3(9.9, 0, 0), eye: eye, fadeRadius: 10),
        lessThan(1.0),
      );
      expect(grid.strengthAt(Vector3(11, 0, 0), eye: eye, fadeRadius: 10), 0.0);
    });

    test('a strength from outside the range is still a colour', () {
      const grid = GroundGrid();

      // `fadedColour` is public and `strengthAt` is not its only caller: view-11
      // draws the dial's own lines through it, and pro-eng-07 will draw seams.
      // Mutation: drop the `.clamp(0.0, 1.0)` on the strength, and a caller
      // passing 2 gets colour components past one — which a backend clamps, or
      // wraps, or leaves as a NaN once it has been through a tone curve, and
      // which of those it does is a thing nobody wants to find out per platform.
      final over = grid.fadedColour(grid.minorColour, 2.0);
      final whole = grid.fadedColour(grid.minorColour, 1.0);
      final under = grid.fadedColour(grid.minorColour, -1.0);
      final none = grid.fadedColour(grid.minorColour, 0.0);

      expect(over.x, closeTo(whole.x, 1e-9));
      expect(over.y, closeTo(whole.y, 1e-9));
      expect(under.x, closeTo(none.x, 1e-9));
      expect(under.y, closeTo(none.y, 1e-9));
    });

    test('a cell fades by where its middle is, not by where it starts', () {
      const grid = GroundGrid(halfLines: 4, solidFraction: 0.0);
      // On the floor and off to one side, so the cells of a line run towards
      // the camera and away from it and the two ends of one cell are at
      // measurably different distances.
      final eye = Vector3(4.5, 0, 0);
      final overlay = _overlay(eye: eye);

      final segments = grid.writeInto(overlay, eye: eye, fadeRadius: 4.0);

      // Mutation: take the strength at `from` rather than at `(from + to) / 2`,
      // which is the shorter line and is what the comment above `_segment`
      // argues against. The cells at the edge of the fade are then kept or
      // dropped by the end that happens to be listed first, so a line's last
      // visible cell is a whole cell longer on one side of the camera than the
      // other, and the fade stops being a circle.
      expect(segments, 45);
    });
  });

  group('the dial', () {
    const dial = OrientationGizmo();

    test('pressing −X turns the camera a quarter turn', () {
      final view = dial.viewAlong(ViewAxis.xNegative, fromYaw: 0);

      expect(view.yaw, closeTo(math.pi / 2, 1e-12));
      expect(view.pitch, closeTo(0, 1e-12));
      // Mutation: `math.atan2(eyeward.x, eyeward.z)` to
      // `math.atan2(-eyeward.x, eyeward.z)`. The yaw is −π/2 and every button
      // sends the camera to the opposite side of the model from the one it
      // names, which is the failure this whole file's convention is about.
    });

    test('a press on the −X button is what asks for that quarter turn', () {
      final buttons = dial.buttonsAt(yaw: 0, pitch: 0);
      final minusX = buttons.firstWhere((b) => b.axis == ViewAxis.xNegative);

      final hit = dial.hitTest(buttons, minusX.dx, minusX.dy);
      expect(hit, ViewAxis.xNegative);
      expect(dial.viewAlong(hit!, fromYaw: 0).yaw, closeTo(math.pi / 2, 1e-12));
      // Mutation: `ViewAxis.xNegative => Vector3(-1, 0, 0)` to `Vector3(1, 0,
      // 0)`. The button that says −X is drawn on the +X side of the dial and
      // `hit` comes back as `xPositive`: pressing the ball on the left takes a
      // person to the view from the right.
      //
      // Mirroring the dial instead — negating `dx` — is *not* caught here, and
      // it cannot be: the press in this test is taken from the button's own
      // position, so a dial that is mirrored is a dial that agrees with itself.
      // What catches that is where the buttons stand, two tests below.
    });

    test('every button leaves the camera looking down its own axis', () {
      for (final axis in ViewAxis.values) {
        final view = dial.viewAlong(axis, fromYaw: 0.7);
        final gaze = -_eyewardOf(view.yaw, view.pitch);
        expect(
          gaze.dot(axis.direction),
          greaterThan(0.9999),
          reason: '$axis should be looked along',
        );
      }
      // Mutation: swap the pole's pitch — `eyeward.y > 0 ? -maxPitch :
      // maxPitch`. The dot for the two Y buttons goes to −0.99995, and a person
      // pressing "top" gets the view from underneath the floor.
      //
      // The four level views have a pitch of exactly zero, so nothing about
      // their pitch can be mutated to fail this. That is why `viewAlong` is two
      // cases rather than an `asin` whose sign no test could reach.
    });

    test('the top and bottom views keep the yaw the camera came in with', () {
      final top = dial.viewAlong(ViewAxis.yNegative, fromYaw: 1.234);
      final bottom = dial.viewAlong(ViewAxis.yPositive, fromYaw: 1.234);

      expect(top.yaw, 1.234);
      expect(top.pitch, closeTo(OrientationGizmo.maxPitch, 1e-12));
      expect(bottom.yaw, 1.234);
      expect(bottom.pitch, closeTo(-OrientationGizmo.maxPitch, 1e-12));
      // Mutation: return `yaw: 0` at the pole instead of `fromYaw`. Going to the
      // top view then spins the whole model round underneath the camera on the
      // one view where a person is reading its outline.
    });

    test('the turn is the short way round', () {
      const around = 2 * math.pi;
      final view = dial.viewAlong(ViewAxis.zNegative, fromYaw: around + 0.1);

      expect((view.yaw - (around + 0.1)).abs(), lessThan(math.pi));
      expect(view.yaw, closeTo(around, 1e-12));
      // Mutation: `_nearestTurn` returning `target + turn * 0`. The yaw is 0,
      // which is the same view, and the animation gets there by spinning the
      // model a full turn — 0.1 radians of travel written as 6.28.
    });

    test('a button stands where its axis points on screen', () {
      final buttons = dial.buttonsAt(yaw: 0, pitch: 0);
      GizmoButton of(ViewAxis axis) =>
          buttons.firstWhere((b) => b.axis == axis);

      expect(of(ViewAxis.xPositive).dx, closeTo(dial.radius, 1e-12));
      expect(of(ViewAxis.xPositive).dy, closeTo(0, 1e-12));
      // Flutter's y grows downwards, so the up axis is at a negative offset.
      expect(of(ViewAxis.yPositive).dy, closeTo(-dial.radius, 1e-12));
      expect(of(ViewAxis.zPositive).facing, closeTo(1, 1e-12));
      expect(of(ViewAxis.zNegative).facing, closeTo(-1, 1e-12));
      // Mutation: `dy: -radius * direction.dot(up)` to `dy: radius * …`. The
      // dial is drawn upside down, so the ball a person presses for the top view
      // is the one sitting at the bottom of it. Mirroring the dial left to
      // right — negating `dx` — fails the first expectation here for the same
      // reason, and nothing else in the file catches it.
    });

    test('a pitched camera keeps every button on the dial\'s sphere', () {
      final buttons = dial.buttonsAt(yaw: 0.4, pitch: 0.3);

      // The three axes the buttons are projected onto are the camera's own, so
      // they are perpendicular and of unit length, and every button lands on the
      // sphere of the dial's radius however the camera is turned. A basis that
      // is only orthonormal at pitch zero — world up in place of the camera's —
      // pulls the balls off that sphere as soon as the camera tilts.
      for (final button in buttons) {
        final depth = dial.radius * button.facing;
        expect(
          math.sqrt(
            button.dx * button.dx + button.dy * button.dy + depth * depth,
          ),
          // The dot products come off single-precision vectors, so a ten
          // thousandth of a pixel is as close as twenty-two of them get.
          closeTo(dial.radius, 1e-4),
          reason: '${button.axis} has left the circle the dial is drawn as',
        );
      }
      // Mutation: `up` to world up, `Vector3(0, 1, 0)`. Of a radius of 22 the Z
      // buttons come out at 21.17 and the X ones at 21.85, while the Y pair
      // stands at 22.94 — outside the circle a painter draws the dial as, on the
      // one axis a tilted camera foreshortens most.
    });

    test('a camera above the model faces the up axis at it', () {
      GizmoButton of(List<GizmoButton> buttons, ViewAxis axis) =>
          buttons.firstWhere((b) => b.axis == axis);
      final above = dial.buttonsAt(yaw: 0.4, pitch: 0.3);
      final below = dial.buttonsAt(yaw: 0.4, pitch: -0.3);

      // A positive pitch puts the eye above the target, so +Y is the ball
      // turned towards the viewer and the one a painter fills; from underneath
      // it is the hollow one.
      expect(of(above, ViewAxis.yPositive).facing, greaterThan(0));
      expect(of(below, ViewAxis.yPositive).facing, lessThan(0));
      // Orbiting towards +X walks the +Z ball left of the dial's centre, the way
      // the model itself swings left in the viewport, and looking down at the
      // floor tips it below the centre as well.
      expect(of(above, ViewAxis.zPositive).dx, lessThan(0));
      expect(of(above, ViewAxis.zPositive).dy, greaterThan(0));
      // Mutation: `sinPitch` to `-sinPitch` in `eyeward`. With the camera above
      // the model the +Y ball's facing comes back −0.296, so the painter fills
      // the ball for the view from underneath and, where two balls overlap, the
      // hit test hands the press to the one pointing away. The default orbit
      // pitch is 0.35, so this is the ordinary case rather than a corner of one.
      //
      // Mutation: `right` to `Vector3(cosYaw, 0, sinYaw)`. The third fails: the
      // dial spins the opposite way to the model as the camera orbits, which is
      // invisible at yaw zero and wrong everywhere else.
      //
      // Mutation: `up` to world up, `Vector3(0, 1, 0)`. The fourth fails at −0:
      // the balls of the horizontal axes stay on the dial's equator however far
      // the camera climbs, so the dial reads as a camera that never left the
      // ground while the viewport beside it looks down at the floor.
    });

    test('the buttons come back furthest away first', () {
      final buttons = dial.buttonsAt(yaw: 0.4, pitch: 0.3);

      expect(buttons.first.facing, lessThan(buttons.last.facing));
      for (var i = 1; i < buttons.length; i++) {
        expect(buttons[i - 1].facing, lessThanOrEqualTo(buttons[i].facing));
      }
      // Mutation: `b.facing.compareTo(a.facing)` in the sort. A painter drawing
      // the list in order then paints the far balls over the near ones, and the
      // dial reads inside out.
    });

    test('seen down an axis, the button facing the viewer takes the press', () {
      final buttons = dial.buttonsAt(yaw: 0, pitch: 0);

      // +Z and −Z are both at the centre of the dial; only `facing` separates
      // them.
      expect(dial.hitTest(buttons, 0, 0), ViewAxis.zPositive);
      // Mutation: choose by distance alone (`distance < bestDistance` as the
      // only test). The two are the same distance away, the first one in a
      // back-to-front list wins, and pressing the ball that is pointing at you
      // sends the camera to the far side of the model.
    });

    test('a press on the rim of a ball still counts as a press on it', () {
      final buttons = dial.buttonsAt(yaw: 0, pitch: 0);
      final plusX = buttons.firstWhere((b) => b.axis == ViewAxis.xPositive);

      // The design draws these balls at about ⌀11, so six pixels from the middle
      // is a press on the paint and still a long way from the next ball along.
      expect(dial.hitTest(buttons, plusX.dx + 6, plusX.dy), ViewAxis.xPositive);
      expect(dial.hitTest(buttons, plusX.dx, plusX.dy - 6), ViewAxis.xPositive);
      // Mutation: `handleRadius = 9.0` to `4.0`. The press six pixels out comes
      // back null: the target is then smaller than the ball a person can see, so
      // a press that visibly landed on the paint does nothing and the dial reads
      // as broken rather than as fussy.
    });

    test('two buttons equally turned, and the nearer one takes the press', () {
      // Both perpendicular to the eye, which is what the four side buttons are
      // when the camera is level: `facing` is the same number for each, so the
      // rule that puts the one turned towards the viewer first has nothing to
      // choose between them and distance is all that is left.
      const buttons = <GizmoButton>[
        GizmoButton(axis: ViewAxis.zPositive, dx: -4, dy: 0, facing: 0),
        GizmoButton(axis: ViewAxis.xPositive, dx: 4, dy: 0, facing: 0),
      ];

      // Mutation: replace the tie-break clause with `false`, keeping the
      // facing comparison — half of the rule the comment above `hitTest`
      // states. The first button in the list then wins every tie, and the list
      // is ordered furthest-away-first on purpose, so a press a pixel from one
      // ball turns the camera to the axis of the other one.
      expect(dial.hitTest(buttons, 3, 0), ViewAxis.xPositive);
      expect(dial.hitTest(buttons, -3, 0), ViewAxis.zPositive);
    });

    test('a press between the buttons hits nothing', () {
      final buttons = dial.buttonsAt(yaw: 0, pitch: 0);

      expect(
        dial.hitTest(buttons, dial.radius * 0.71, dial.radius * 0.71),
        null,
      );
      // Mutation: `distance > handleRadius` to `distance > handleRadius * 100`.
      // Every press anywhere near the corner of the viewport — including one
      // meant for the model behind the dial — snaps the camera to an axis, and
      // the press in the −X test above lands on +Z instead.
    });
  });
}
