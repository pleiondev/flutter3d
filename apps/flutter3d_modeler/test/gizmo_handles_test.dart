/// The gizmo's handles, read back out of the batches they were written into.
///
///     flutter test test/gizmo_handles_test.dart
///
/// **What a test can reach here and what it cannot.** Every decision this file
/// makes is a vertex and a colour in an [OverlayBatch] — where a shaft starts,
/// how wide a head is on screen, which plane a ring lies in, which handle is
/// lit — and each of them is held to a number below. What lands on a pixel is
/// one step further on, and it is the same step `ground_grid_test.dart` stops
/// at: the batches are drawn with a fragment stage that passes its vertex
/// colour through, so the colour asserted here is the colour a pixel gets.
///
/// Nothing here builds a camera, a device or a widget. The gizmo's arms come
/// from `transform_gizmo.dart`, which is arithmetic, and the overlay is told
/// where the eye is by hand.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_modeler/src/gizmo_handles.dart';
import 'package:flutter3d_modeler/src/mesh_overlay_builder.dart';
import 'package:flutter3d_modeler/src/transform_gizmo.dart';
import 'package:flutter3d_modeler/src/transform_modal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The world size of one logical pixel at one unit of distance, for every
/// camera below. Small enough that a gizmo ten units out is a few units across,
/// which is the scale a person actually models at.
const double _pixel = 0.01;

/// An overlay that knows where the camera is, with the nudge towards the eye
/// switched off unless a test is about the nudge — a vertex is then exactly
/// where the drawing put it, and a position can be compared to the arithmetic
/// that produced it.
MeshOverlay _overlay({required Vector3 eye, double biasPixels = 0}) {
  final overlay = MeshOverlay(
    vertexShader: const ShaderHandle(backend: 0, name: 'DebugLineVertex'),
    fragmentShader: const ShaderHandle(backend: 1, name: 'DebugLine'),
  )..biasPixels = biasPixels;
  overlay.lookFrom(
    eye: eye,
    right: Vector3(1, 0, 0),
    up: Vector3(0, 1, 0),
    pixel: _pixel,
  );
  return overlay;
}

/// The arms the same camera would be hit-tested against.
List<GizmoHandle> _handlesAt(Vector3 pivot, Vector3 eye) =>
    gizmoHandles(pivot, GizmoView(eye: eye, pixel: _pixel));

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
/// way in. The overlay is encoded inside the scene pass, so a colour named as a
/// hex is converted going in; this undoes that, so the assertions below can go
/// on speaking in the hex the design speaks in.
double _toSrgb(double c) => c < 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(math.max(c, 0.0), 1.0 / 2.4) - 0.055;

/// The colour of every vertex, back in the hex the design names colours in and
/// rounded to the eight bits it reaches a pixel at.
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

/// Where a run of [count] vertices starting at [from] is centred.
///
/// **The middle of a quad is the one thing about it that does not depend on
/// which way the camera is facing.** Both shapes the overlay draws here — a
/// band and a camera-facing square — put their vertices an equal distance
/// either side of a centre line, so the sideways offsets cancel and what is
/// left is the point the drawing asked for. Comparing individual corners
/// instead would be a test of `MeshOverlay`'s quad winding, which is that
/// file's business.
Vector3 _centreOf(List<Vector3> at, int from, int count) {
  var sum = Vector3.zero();
  for (var v = from; v < from + count; v++) {
    sum += at[v];
  }
  return sum / count.toDouble();
}

/// How many logical pixels across the shape drawn as the six vertices at
/// [from] is, seen from [eye].
///
/// **One measure for both shapes, and it is the same two corners either way.**
/// A quad is written as `a b c a c d`, so the first and the last vertex of a
/// run are the two ends of one side of it: across a band that side is the
/// width, and across a camera-facing square it is the side. Dividing by the
/// world size of a pixel at the shape's centre undoes the distance, so what
/// comes back is the number the drawing asked [MeshOverlay] for. Only true
/// with the nudge towards the eye switched off, which is why every caller
/// below leaves `biasPixels` at zero: with a nudge the centre is no longer the
/// point the size was worked out at.
double _pixelsAcross(List<Vector3> at, int from, Vector3 eye) =>
    (at[from + 5] - at[from]).length /
    (_pixel * (_centreOf(at, from, 6) - eye).length);

void _expectNear(Vector3 got, Vector3 wanted, {double within = 1e-4}) {
  expect(got.x, closeTo(wanted.x, within), reason: 'x of $got');
  expect(got.y, closeTo(wanted.y, within), reason: 'y of $got');
  expect(got.z, closeTo(wanted.z, within), reason: 'z of $got');
}

/// A colour as `0xAARRGGBB`, which is how [_coloursOf] hands them back, from
/// one of the gizmo's `0xRRGGBB` tints.
int _opaque(int tint) => 0xFF000000 | tint;

void main() {
  const drawing = GizmoDrawing();
  final pivot = Vector3.zero();

  group('a move', () {
    test('draws a shaft and a head per axis, on the arm the ray is traced '
        'against', () {
      final eye = Vector3(0, 0, 10);
      final overlay = _overlay(eye: eye);
      final handles = _handlesAt(pivot, eye);

      drawing.writeInto(
        overlay,
        pivot: pivot,
        handles: handles,
        kind: TransformKind.move,
      );

      // Six vertices of band and six of square, three times over.
      expect(overlay.handles.vertexCount, 3 * 12);
      expect(overlay.lines.isEmpty, isTrue);
      expect(overlay.fill.isEmpty, isTrue);

      final at = _positionsOf(overlay.handles);
      for (var i = 0; i < handles.length; i++) {
        final handle = handles[i];
        _expectNear(
          _centreOf(at, i * 12, 6),
          (handle.base + handle.headBase) * 0.5,
        );
        _expectNear(
          _centreOf(at, i * 12 + 6, 6),
          (handle.headBase + handle.tip) * 0.5,
        );
      }
      // Mutation: `overlay.ribbon(handle.base, handle.headBase, …)` to
      // `overlay.ribbon(handle.base, handle.tip, …)`. The X shaft's centre comes
      // back at 5.52 where the arm puts it at 4.32, and the shaft is then drawn
      // straight through the head — an arrow with no point on it, which is the
      // one part of it that says which way it goes.
      //
      // Mutation: drop the `overlay.point(…)` call. The count is 18 rather than
      // 36 and every arrow loses its head.
    });

    test('the head is the number of pixels across the design asked for, '
        'however far away it is', () {
      double headPixels(Vector3 eye) {
        final overlay = _overlay(eye: eye);
        drawing.writeInto(
          overlay,
          pivot: pivot,
          handles: _handlesAt(pivot, eye),
          kind: TransformKind.move,
        );
        final at = _positionsOf(overlay.handles);
        // Two corners of one side of the X arrow's head, and how far the head
        // is from the eye: a square of `n` logical pixels is `n * pixel * depth`
        // across in the world.
        final side = (at[7] - at[6]).length;
        return side / (_pixel * (_centreOf(at, 6, 6) - eye).length);
      }

      expect(headPixels(Vector3(0, 0, 10)), closeTo(drawing.headPixels, 1e-3));
      expect(headPixels(Vector3(0, 0, 400)), closeTo(drawing.headPixels, 1e-3));
      // Mutation: `size: headPixels` to `size: headPixels * 2`. The near camera
      // comes back at 26.0 against 13, and the arrowheads are twice the size the
      // design named — which is the sort of thing nobody notices until a
      // screenshot is put beside a hand-over.
      //
      // What this does *not* catch is a gizmo sized in metres: the arms come
      // from `gizmoHandles`, which does that arithmetic and has its own tests.
      // The ring below is where this file holds its own screen sizing.
      //
      // Nor does it catch the thirteen. Both sides of the comparison read
      // `drawing.headPixels`, so a head of forty goes through here green; what
      // this holds is that the two cameras agree. The number itself is held in
      // 'the sizes', which writes it out.
    });

    test('each arrow is its axis\'s own tint', () {
      final eye = Vector3(0, 0, 10);
      final overlay = _overlay(eye: eye);

      drawing.writeInto(
        overlay,
        pivot: pivot,
        handles: _handlesAt(pivot, eye),
        kind: TransformKind.move,
      );
      final ink = _coloursOf(overlay.handles);

      expect(ink.sublist(0, 12), everyElement(_opaque(kGizmoTintX)));
      expect(ink.sublist(12, 24), everyElement(_opaque(kGizmoTintY)));
      expect(ink.sublist(24, 36), everyElement(_opaque(kGizmoTintZ)));
      // Mutation: `_inkFor(handle.tint, …)` to `_inkFor(kGizmoTintX, …)`. The Y
      // arm comes back #FF6B8A where it should be #8AFF6B, and a gizmo whose
      // arms are one colour tells a person nothing about which way any of them
      // goes.
    });
  });

  group('the handle under the pointer', () {
    test('is drawn brighter, and it is the only one that is', () {
      final eye = Vector3(0, 0, 10);
      final cold = _overlay(eye: eye);
      final lit = _overlay(eye: eye);

      for (final (overlay, hot) in <(MeshOverlay, GizmoAxis?)>[
        (cold, null),
        (lit, GizmoAxis.x),
      ]) {
        drawing.writeInto(
          overlay,
          pivot: pivot,
          handles: _handlesAt(pivot, eye),
          kind: TransformKind.move,
          hot: hot,
        );
      }

      final before = _coloursOf(cold.handles);
      final after = _coloursOf(lit.handles);

      // #FF6B8A mixed 45 per cent of the way to white: the red is already full
      // and stays there, and the other two climb.
      expect((after[0] >> 8) & 0xFF, greaterThan((before[0] >> 8) & 0xFF));
      expect(after[0] & 0xFF, greaterThan(before[0] & 0xFF));
      // Every vertex of the X arrow, shaft and head alike.
      expect(after.sublist(0, 12), everyElement(after[0]));
      // Y and Z are untouched.
      expect(after.sublist(12, 36), before.sublist(12, 36));
      // The lit branch writes its own alpha, and it has to be the one the cold
      // branch writes: the batches are drawn with no blend state, so an alpha
      // under one is a fade that changes nothing on screen and lies to
      // anything else reading these vertices. Nothing above would notice —
      // every assertion so far masks a channel or compares one lit vertex to
      // another.
      expect(
        after.map((ink) => ink >> 24).toList(),
        everyElement(0xFF),
        reason: 'a lit handle is as opaque as a cold one',
      );
      // Mutation: `hotMix = kGizmoHotMix` to `0.0`. The first fails at 107
      // against 107: the pointer picks an arm up and nothing on screen says so,
      // so a person drags before they know which axis they have got hold of.
      //
      // Mutation: `handle.axis == hot` to `hot != null`. The fourth fails —
      // all three arms light at once, which says the gizmo is grabbed and not
      // which part of it.
      //
      // Mutation: the `1.0` alpha of the lit branch of `_inkFor` to `0.0`. The
      // last fails with the twelve vertices of the X arm at 0 against 255 — the
      // hovered handle is the one handle drawn transparent, in batches that
      // have no blend state to make that mean anything.
    });

    test('a hot axis lights that axis and not the one beside it', () {
      final eye = Vector3(0, 0, 10);
      final overlay = _overlay(eye: eye);

      drawing.writeInto(
        overlay,
        pivot: pivot,
        handles: _handlesAt(pivot, eye),
        kind: TransformKind.move,
        hot: GizmoAxis.z,
      );
      final ink = _coloursOf(overlay.handles);

      expect(ink.sublist(0, 12), everyElement(_opaque(kGizmoTintX)));
      expect(ink.sublist(12, 24), everyElement(_opaque(kGizmoTintY)));
      expect(ink.sublist(24, 36), isNot(contains(_opaque(kGizmoTintZ))));
      // Mutation: in `_arrows`, light `handles.first` whenever `hot` is set
      // rather than the handle whose axis matches it. The X arm comes back
      // brightened on a hover over Z, so the highlight points at one axis while
      // the drag that follows moves the model along another.
    });

    test('a mix past the ends of the range still lands on a colour', () {
      final eye = Vector3(0, 0, 10);

      // **Read as raw floats, and that is the point of the test.**
      // [_coloursOf] rounds and clamps on the way to a byte, so a channel that
      // came out at ten looks exactly like white there. What actually leaves
      // this file is the float, and it is what a backend's tone curve is handed.
      List<double> inkFloats(double hotMix) {
        final overlay = _overlay(eye: eye);
        GizmoDrawing(hotMix: hotMix).writeInto(
          overlay,
          pivot: pivot,
          handles: _handlesAt(pivot, eye),
          kind: TransformKind.move,
          hot: GizmoAxis.x,
        );
        final floats = _floatsOf(overlay.handles);
        return <double>[
          for (var v = 0; v < overlay.handles.vertexCount; v++)
            for (var c = 3; c < MeshOverlay.floatsPerVertex; c++)
              floats[v * MeshOverlay.floatsPerVertex + c],
        ];
      }

      // `hotMix` is a field a caller sets, so both ends are reachable from
      // outside this file — a touch build asking for a stronger highlight is
      // one typo away from either.
      expect(inkFloats(4.0), everyElement(inInclusiveRange(0.0, 1.0)));
      expect(inkFloats(-1.0), everyElement(inInclusiveRange(0.0, 1.0)));
      // Mutation: `final mix = hotMix.clamp(0.0, 1.0);` to `final mix =
      // hotMix;`. The green of the lit X arm comes back at 10.374067306518555
      // on the first and at -0.012444605119526386 on the second — a colour
      // three quarters of the way to a stop above white, handed to whatever
      // tone curve the backend has, and a colour the other side of black.
      // Neither is a thing to find out one platform at a time, and neither is
      // visible through [_coloursOf], which clamps to a byte on the way past.
    });
  });

  group('a turn', () {
    test('draws a closed ring per axis, in the plane that axis turns in', () {
      final eye = Vector3(0, 0, 10);
      final overlay = _overlay(eye: eye);

      drawing.writeInto(
        overlay,
        pivot: pivot,
        handles: _handlesAt(pivot, eye),
        kind: TransformKind.rotate,
      );

      // Forty-eight segments, two vertices each, three rings.
      expect(overlay.lines.vertexCount, 3 * 48 * 2);
      expect(overlay.handles.isEmpty, isTrue);

      final at = _positionsOf(overlay.lines);
      // The ring for an axis lies in the plane across it, so every vertex of it
      // has nothing along that axis at all.
      for (var v = 0; v < 96; v++) {
        expect(
          at[v].x,
          closeTo(0, 1e-5),
          reason: 'the X ring has left its plane',
        );
      }
      for (var v = 96; v < 192; v++) {
        expect(
          at[v].y,
          closeTo(0, 1e-5),
          reason: 'the Y ring has left its plane',
        );
      }
      for (var v = 192; v < 288; v++) {
        expect(
          at[v].z,
          closeTo(0, 1e-5),
          reason: 'the Z ring has left its plane',
        );
      }
      // Closed: the last segment of each ring comes back to where the first one
      // started.
      for (var ring = 0; ring < 3; ring++) {
        _expectNear(at[ring * 96 + 95], at[ring * 96]);
      }
      // Mutation: `GizmoAxis.x => (Vector3(0, 1, 0), Vector3(0, 0, 1))` to
      // `(Vector3(1, 0, 0), Vector3(0, 1, 0))`. The first loop fails at 8.2 —
      // the ring labelled X lies in the XY plane, so the handle a person takes
      // hold of to roll the model turns it about Z instead.
      //
      // Mutation: `i <= _turnSegments` to `i < _turnSegments`. The count is 282
      // and the ring has a gap in it a segment wide, at the one place the eye
      // goes first because it is where the ring starts.
    });

    test('the ring is the same size on screen at any distance', () {
      double ringRadius(Vector3 eye) {
        final overlay = _overlay(eye: eye);
        drawing.writeInto(
          overlay,
          pivot: pivot,
          handles: _handlesAt(pivot, eye),
          kind: TransformKind.rotate,
        );
        return _positionsOf(overlay.lines).first.length;
      }

      // The pivot is at the origin, so a camera ten units out and one forty
      // times further away see a ring of the same number of pixels only if the
      // world radius grew by forty.
      final near = ringRadius(Vector3(0, 0, 10));
      final far = ringRadius(Vector3(0, 0, 400));

      expect(near, closeTo(drawing.turnPixels * _pixel * 10, 1e-3));
      expect(far, closeTo(near * 40, 1e-2));
      // Mutation: `overlay.worldSize(turnPixels, pivot)` to `turnPixels`. The
      // near ring comes back at 82.0 where the camera makes it 8.2, and both
      // rings are 82 units across whatever the camera does: ten units out that
      // is a ring several times the width of the viewport, and at four hundred
      // it is a dot beside the model it is meant to enclose. This is the whole
      // reason the gizmo asks the overlay how big a pixel is.
    });

    test('the chords sag less than a pixel away from the circle', () {
      final eye = Vector3(0, 0, 10);
      final overlay = _overlay(eye: eye);

      drawing.writeInto(
        overlay,
        pivot: pivot,
        handles: _handlesAt(pivot, eye),
        kind: TransformKind.rotate,
      );

      // A ring of straight segments reads as round exactly when nobody can see
      // where a corner is, and what decides that is how far the middle of a
      // chord falls inside the circle it is standing in for — the gap between
      // the two, in the pixels the ring is drawn in. The spacing of the corners
      // says nothing on its own: these are eleven pixels apart.
      final at = _positionsOf(overlay.lines);
      final radius = at.first.length;
      final sag =
          (radius - ((at[0] + at[1]) * 0.5).length) /
          (_pixel * (pivot - eye).length);

      expect(sag, closeTo(0.176, 0.005));
      expect(
        (at[1] - at[0]).length / (_pixel * (pivot - eye).length),
        closeTo(10.73, 0.01),
      );
      expect(sag, lessThan(1.0), reason: 'a corner of the ring is visible');
      // Mutation: `_turnSegments = 48` to `24`. The sag comes back at
      // 0.7015177971073605 against 0.176 and the corners at 21.41 pixels apart
      // — four times the departure from the circle, on a line one pixel wide,
      // which is a ring a person can count the sides of. The vertex count above
      // goes red at the same time and says only that the number changed; this
      // says what the number is for.
      //
      // Mutation: `this.turnPixels = 82.0` to `820.0`. The chord fails at
      // 107.26112463455978, because a ring ten times the radius drawn with the
      // same forty-eight segments is a ring whose corners are ten times as far
      // apart.
    });
  });

  group('a scale', () {
    test('draws a box at the end of each arm and one in the middle', () {
      final eye = Vector3(0, 0, 10);
      final overlay = _overlay(eye: eye);
      final handles = _handlesAt(pivot, eye);

      drawing.writeInto(
        overlay,
        pivot: pivot,
        handles: handles,
        kind: TransformKind.scale,
      );

      // Three arms of band and box, and one box more.
      expect(overlay.handles.vertexCount, 3 * 12 + 6);
      expect(overlay.lines.isEmpty, isTrue);

      final at = _positionsOf(overlay.handles);
      for (var i = 0; i < handles.length; i++) {
        final handle = handles[i];
        // The arm runs the whole length the ray is traced against, and the box
        // sits on its end.
        _expectNear(_centreOf(at, i * 12, 6), (handle.base + handle.tip) * 0.5);
        _expectNear(_centreOf(at, i * 12 + 6, 6), handle.tip);
      }
      _expectNear(_centreOf(at, 36, 6), pivot);

      final ink = _coloursOf(overlay.handles);
      expect(ink.sublist(36, 42), everyElement(_opaque(kGizmoTintUniform)));
      // The middle box belongs to no axis, so it is none of the three tints.
      expect(_opaque(kGizmoTintUniform), isNot(_opaque(kGizmoTintX)));
      // And it is lighter than both greys the overlay draws underneath it,
      // which is the whole claim [kGizmoTintUniform] makes for itself: the one
      // handle with no colour of its own has to be findable on top of a
      // wireframe the same distance along the grey scale.
      final under = MeshOverlayColours();
      for (final grey in <Vector4>[under.wire, under.vertex]) {
        for (final (shift, channel) in <(int, double)>[
          (16, grey.x),
          (8, grey.y),
          (0, grey.z),
        ]) {
          expect(
            (kGizmoTintUniform >> shift) & 0xFF,
            greaterThan((channel * 255).round()),
            reason: 'the middle box has sunk into the overlay under it',
          );
        }
      }
      // Mutation: `kGizmoTintUniform = 0xC8CFD2` to `0x8C9399`, which is the
      // wireframe's own grey — the colour the doc for that constant used to
      // claim it already was. The red channel fails at 140 against 140, and the
      // middle box is then drawn in the exact colour of the mesh it is standing
      // on top of.
      //
      // Mutation: drop the `overlay.point(pivot, …)` call. The count is 36 and
      // there is no way to scale every axis at once with the pointer at all —
      // the commonest scale there is becomes keyboard-only.
      //
      // Mutation: `overlay.point(handle.tip, …)` to `overlay.point(handle.base,
      // …)`. The boxes bunch up round the pivot where the three of them overlap
      // each other and the middle one, and no aim picks out the axis wanted.
    });

    test('the box in the middle lights on its own', () {
      final eye = Vector3(0, 0, 10);
      final cold = _overlay(eye: eye);
      final lit = _overlay(eye: eye);

      for (final (overlay, uniform) in <(MeshOverlay, bool)>[
        (cold, false),
        (lit, true),
      ]) {
        drawing.writeInto(
          overlay,
          pivot: pivot,
          handles: _handlesAt(pivot, eye),
          kind: TransformKind.scale,
          uniformHot: uniform,
        );
      }

      final before = _coloursOf(cold.handles);
      final after = _coloursOf(lit.handles);

      expect((after[36] >> 16) & 0xFF, greaterThan((before[36] >> 16) & 0xFF));
      // The three arms are where they were: the middle box is not an axis and
      // hovering it is not hovering one.
      expect(after.sublist(0, 36), before.sublist(0, 36));
      // Mutation: `_inkFor(kGizmoTintUniform, uniformHot)` to
      // `_inkFor(kGizmoTintUniform, false)`. The first fails at 200 against
      // 200: the one handle that has no axis to fall back on gives no sign it
      // is under the pointer, so a uniform scale is a drag taken on faith.
    });
  });

  group('the sizes', () {
    /// The three shapes of a move and a scale gizmo, measured off the batch in
    /// logical pixels: the shaft of an arrow, its head, a scale box and the
    /// middle box.
    ({double shaft, double head, double box, double middle, double ring})
    sizesFrom(Vector3 eye) {
      final move = _overlay(eye: eye);
      final scale = _overlay(eye: eye);
      final turn = _overlay(eye: eye);
      for (final (overlay, kind) in <(MeshOverlay, TransformKind)>[
        (move, TransformKind.move),
        (scale, TransformKind.scale),
        (turn, TransformKind.rotate),
      ]) {
        drawing.writeInto(
          overlay,
          pivot: pivot,
          handles: _handlesAt(pivot, eye),
          kind: kind,
        );
      }
      final moveAt = _positionsOf(move.handles);
      final scaleAt = _positionsOf(scale.handles);
      return (
        shaft: _pixelsAcross(moveAt, 0, eye),
        head: _pixelsAcross(moveAt, 6, eye),
        box: _pixelsAcross(scaleAt, 6, eye),
        middle: _pixelsAcross(scaleAt, 36, eye),
        ring:
            _positionsOf(turn.lines).first.length /
            (_pixel * (pivot - eye).length),
      );
    }

    test('are the numbers the design named, in logical pixels', () {
      // **Written out rather than read back off the [GizmoDrawing].** A test
      // that compares the drawing to `drawing.shaftPixels` passes whatever that
      // field says, so it holds the pixels-rather-than-metres arithmetic and
      // nothing about the design: a shaft ten times its width goes through it
      // green. These are the numbers the gizmo was drawn to, and changing one
      // of them is a decision rather than a refactor.
      final near = sizesFrom(Vector3(0, 0, 10));
      expect(near.shaft, closeTo(3, 1e-3));
      expect(near.head, closeTo(13, 1e-3));
      expect(near.box, closeTo(11, 1e-3));
      expect(near.middle, closeTo(11, 1e-3));
      expect(near.ring, closeTo(82, 1e-3));
      // Mutation: `this.shaftPixels = 3.0` to `30.0`. The first fails at
      // 29.999999828083094 — a shaft wider than the head it is meant to point
      // with, over the model it is meant to leave visible.
      //
      // Mutation: `this.boxPixels = 11.0` to `30.0`. The third fails at
      // 29.999998776861467, and the three scale boxes are then wide enough to
      // meet each other round the middle one.
      //
      // Mutation: `this.turnPixels = 82.0` to `820.0`. The last fails at 820.0.
      // Every one of the three passed before this test was written, because the
      // assertions read the same field they were checking.
    });

    test('every drawn pixel is inside the box a ray is traced against', () {
      // The consequence the numbers above are chosen for. `gizmoHandles` gives
      // an arm [kGizmoGrabPixels] of slack either side of its axis and stops
      // the box at the tip, so a shape drawn wider than twice that slack has
      // paint hanging outside the only thing a press can hit — a person aims at
      // the gizmo, misses it, and orbits the camera instead. The ring is held
      // to [kGizmoPixels] for the neighbouring reason: a ring reaching past the
      // arrows makes switching from move to rotate look like the gizmo growing.
      final eye = Vector3(0, 0, 10);
      final near = sizesFrom(eye);
      for (final (what, size) in <(String, double)>[
        ('the shaft', near.shaft),
        ("the arrow's head", near.head),
        ('a scale box', near.box),
      ]) {
        expect(
          size / 2,
          lessThanOrEqualTo(kGizmoGrabPixels),
          reason: '$what hangs outside the grab box',
        );
      }
      // The middle box is the one shape no ray is traced against at all —
      // [GizmoHit.nearest] answers for the three arms and nothing else — so
      // what holds it is the clear space the arms leave round the pivot. A box
      // wider than that overlaps the arm boxes, and a press in the overlap is
      // then answered by whichever arm the trace reaches first while the paint
      // under the pointer says uniform.
      final armStart =
          (_handlesAt(pivot, eye).first.base - pivot).length /
          (_pixel * (pivot - eye).length);
      expect(near.middle / 2, lessThan(armStart));
      expect(near.ring, lessThan(kGizmoPixels));
      // Mutation: `this.shaftPixels = 3.0` to `30.0`. The shaft fails at
      // 14.999999914041547 against eleven of slack, so five of the fifteen
      // pixels either side of the axis are paint a press goes straight through.
      //
      // Mutation: `this.boxPixels = 11.0` to `30.0`. The same at
      // 14.999999388430734 for a scale box, which is worse: the box is the
      // handle, so most of what a person aims at is outside it. The middle box
      // goes with it, at 15.0 against the 14.40000057220459 pixels the arms
      // leave clear round the pivot.
      //
      // Mutation: `this.turnPixels = 82.0` to `820.0`. The ring fails at 820.0
      // against 96, and a rotate gizmo is then eight times the arrows the same
      // pivot draws for a move.
    });
  });

  test('the handles are nudged towards the eye, the way the overlay nudges', () {
    final eye = Vector3(0, 5, 0);
    final overlay = _overlay(eye: eye, biasPixels: 12);

    drawing.writeInto(
      overlay,
      pivot: pivot,
      handles: _handlesAt(pivot, eye),
      kind: TransformKind.move,
    );

    // The camera is straight above, so everything the gizmo drew should have
    // lifted off the plane the X and Z arms lie in.
    final at = _positionsOf(overlay.handles);
    for (var v = 0; v < 12; v++) {
      expect(at[v].y, greaterThan(0), reason: 'the X arrow has not lifted');
    }
    for (var v = 24; v < 36; v++) {
      expect(at[v].y, greaterThan(0), reason: 'the Z arrow has not lifted');
    }
    // Mutation: write the shaft's six vertices straight into `overlay.handles`
    // — `handle.base` and `handle.headBase` alternating — rather than through
    // `overlay.ribbon`. The first expectation fails at 0.0 and the run stops
    // there. What the mutation reaches is the shaft alone: the head still goes
    // through `overlay.point` and is still lifted, so the loop over the second
    // six vertices is never a test of this at all. That is enough. A shaft
    // sitting exactly on the plane it is drawn over flickers in and out against
    // the face of any model whose surface passes through the pivot — which, for
    // a gizmo that stands on the thing being edited, is most of them.
  });
}
