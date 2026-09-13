/// `view-26n`: whether a drag lands on somebody else's geometry, and where.
///
///     flutter test test/geometry_snap_test.dart
///
/// **The same cube, the same camera, and the same hand-worked projection
/// `element_picking_test.dart` already trusts** — reused rather than rebuilt,
/// because a second oracle that happened to agree with the first would prove
/// nothing a shared one does not already prove better. What is new here is
/// the question: not "what does a click at this pixel select" but "is there
/// something of somebody *else*'s within reach of the point a drag currently
/// wants to put a vertex at, and what is its exact position".
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/geometry_snap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'element_picking_test.dart' show pickerFor, viewLookingAtTheCube;

void main() {
  group('findSnapTarget', () {
    test('a vertex within reach snaps to its exact position', () {
      // A cube identical to the one the click tests use, offset half a metre
      // along X — so its corner that was at local (1, 1, 1) sits at world
      // (1.5, 1, 1), a number `near` below is not exactly at.
      final other = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final objectToWorld = Matrix4.translation(Vector3(0.5, 0.0, 0.0));
      final source = SnapSource(
        id: 1,
        picker: pickerFor(other),
        objectToWorld: objectToWorld,
      );

      // A hundredth of a metre off the target — at this distance from the
      // camera about two logical pixels, well inside an eight-pixel radius,
      // and nowhere near being the same number as the target by accident.
      final near = Vector3(1.51, 1.01, 1.0);

      final target = findSnapTarget(
        view: viewLookingAtTheCube(),
        near: near,
        sources: <SnapSource>[source],
        radiusPixels: 8.0,
      );

      // Not `closeTo`: `view-26n`'s own acceptance is a byte-for-byte match,
      // and a mutation that snapped to `near` itself, or to a corner offset by
      // this file's own tolerance, would still pass a fuzzy comparison here.
      expect(target, isNotNull);
      expect(target!.level, SnapLevel.vertex);
      expect(target.sourceId, 1);
      expect(target.position, Vector3(1.5, 1.0, 1.0));
    });

    test(
      'nothing within reach answers null rather than the nearest anything',
      () {
        final other = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
        final source = SnapSource(id: 1, picker: pickerFor(other));

        // Half a metre off the nearest corner — about ninety logical pixels at
        // this distance, and nothing at an eight-pixel radius should touch it.
        final near = Vector3(1.5, 1.5, 1.0);

        final target = findSnapTarget(
          view: viewLookingAtTheCube(),
          near: near,
          sources: <SnapSource>[source],
          radiusPixels: 8.0,
        );

        // Mutation: fall back to the nearest vertex regardless of the radius.
        // Every drag would then jump to whatever the mesh's own centre is
        // nearest to, snap held down or not.
        expect(target, isNull);
      },
    );

    test('an edge is offered when a vertex is not', () {
      final other = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final source = SnapSource(id: 1, picker: pickerFor(other));

      // The middle of the top-front edge: a full metre from either of its own
      // corners — far outside the radius — but sitting exactly on the edge
      // itself.
      final onEdge = Vector3(0.0, 1.0, 1.0);

      final target = findSnapTarget(
        view: viewLookingAtTheCube(),
        near: onEdge,
        sources: <SnapSource>[source],
        radiusPixels: 8.0,
      );

      expect(target, isNotNull);
      expect(target!.level, SnapLevel.edge);
      expect(target.position.x, closeTo(0.0, 1e-6));
      expect(target.position.y, closeTo(1.0, 1e-6));
      expect(target.position.z, closeTo(1.0, 1e-6));
    });

    test('a vertex wins over an edge at the same reach', () {
      final other = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final source = SnapSource(id: 1, picker: pickerFor(other));

      // A hair *past* the corner at (1, 1, 1), diagonally outside the cube —
      // not a hair inside it. Inside, the two edges that meet at a right-angle
      // corner are always nearer than the corner itself (Pythagoras), so the
      // only place a vertex and an edge genuinely tie is past the point where
      // both edges' own nearest-point-on-segment clamps to that same corner.
      final near = Vector3(1.01, 1.01, 1.0);

      final target = findSnapTarget(
        view: viewLookingAtTheCube(),
        near: near,
        sources: <SnapSource>[source],
        radiusPixels: 8.0,
      );

      expect(target, isNotNull);
      expect(target!.level, SnapLevel.vertex);
      expect(target.position, Vector3(1.0, 1.0, 1.0));
    });

    test('a level left out of the search is never offered', () {
      final other = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final source = SnapSource(id: 1, picker: pickerFor(other));
      final onEdge = Vector3(0.0, 1.0, 1.0);

      final target = findSnapTarget(
        view: viewLookingAtTheCube(),
        near: onEdge,
        sources: <SnapSource>[source],
        radiusPixels: 8.0,
        levels: const <SnapLevel>{SnapLevel.vertex},
      );

      // Mutation: search every level regardless of what was asked for. The
      // edge sitting right under `onEdge` would then answer even though
      // vertex mode asked for a vertex and nothing else.
      expect(target, isNull);
    });

    test('no sources at all is a plain null, not a search of nothing', () {
      final target = findSnapTarget(
        view: viewLookingAtTheCube(),
        near: Vector3(1.0, 1.0, 1.0),
        sources: const <SnapSource>[],
        radiusPixels: 8.0,
      );

      expect(target, isNull);
    });

    test('view-26n\'s own acceptance: a face is offered when neither a vertex '
        'nor an edge is within reach', () {
      final other = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final source = SnapSource(id: 1, picker: pickerFor(other));

      // Well inside the front face (edges at x = ±1, y = ±1): more than a
      // third of a metre from any corner or edge, nowhere near an
      // eight-pixel radius.
      final near = Vector3(0.3, 0.2, 1.0);

      final target = findSnapTarget(
        view: viewLookingAtTheCube(),
        near: near,
        sources: <SnapSource>[source],
        radiusPixels: 8.0,
      );

      expect(target, isNotNull);
      expect(target!.level, SnapLevel.face);
      expect(target.sourceId, 1);
      // The camera looks straight down -Z at a point already sitting on the
      // z = 1 plane, so the ray hits the face exactly where it started.
      expect(target.position.x, closeTo(0.3, 1e-6));
      expect(target.position.y, closeTo(0.2, 1e-6));
      expect(target.position.z, closeTo(1.0, 1e-6));
    });

    test('a level left out of the search leaves a face unoffered too', () {
      final other = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final source = SnapSource(id: 1, picker: pickerFor(other));
      final onFace = Vector3(0.3, 0.2, 1.0);

      final target = findSnapTarget(
        view: viewLookingAtTheCube(),
        near: onFace,
        sources: <SnapSource>[source],
        radiusPixels: 8.0,
        levels: const <SnapLevel>{SnapLevel.vertex, SnapLevel.edge},
      );

      // Mutation: offer a face regardless of what `levels` asked for. Nothing
      // else is within reach of `onFace`, so this only stays null if the face
      // search itself is skipped.
      expect(target, isNull);
    });

    test('an edge wins over a face at the same reach', () {
      final other = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final source = SnapSource(id: 1, picker: pickerFor(other));

      // Sitting exactly on the seam between the front face and the top face
      // — the same point `edgeNear`'s own scan finds as the edge, and the
      // same point a straight-down--Z ray hits as a face, at the same
      // distance from itself: zero. `SnapLevel`'s own priority order settles
      // the tie.
      final onEdge = Vector3(0.0, 1.0, 1.0);

      final target = findSnapTarget(
        view: viewLookingAtTheCube(),
        near: onEdge,
        sources: <SnapSource>[source],
        radiusPixels: 8.0,
      );

      expect(target, isNotNull);
      expect(target!.level, SnapLevel.edge);
    });

    test(
      'the radius is measured in the object it is asked of, not the world',
      () {
        // A source scaled up by ten: the same click-radius arithmetic
        // `element_picking_test.dart` already pins for a squashed object,
        // exercised the other way round — scaled up, a metre in the object's
        // own space is ten world metres, so the vertex ten world metres out
        // still has to answer for a search whose radius was measured in world
        // pixels at `near`'s own depth.
        final other = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
        final objectToWorld = Matrix4.identity()
          ..scaleByVector3(Vector3.all(5.0));
        final source = SnapSource(
          id: 1,
          picker: pickerFor(other),
          objectToWorld: objectToWorld,
        );

        // The corner at local (1, 1, 1) sits at world (5, 5, 5) — behind the
        // camera at (0, 0, 5), so instead the nearer corner is used: local
        // (1, 1, -1) at world (5, 5, -5), a long way in front of it.
        final near = Vector3(5.01, 5.01, -5.0);

        final target = findSnapTarget(
          view: viewLookingAtTheCube(),
          near: near,
          sources: <SnapSource>[source],
          radiusPixels: 8.0,
        );

        expect(target, isNotNull);
        expect(target!.position, Vector3(5.0, 5.0, -5.0));
      },
    );
  });
}
