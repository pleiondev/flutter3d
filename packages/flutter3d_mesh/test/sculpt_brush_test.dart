/// The eight sculpting brushes and X symmetry over `SculptMesh`.
///
///     dart test test/sculpt_brush_test.dart
///
/// Each brush gets one test built to fail if its distinguishing behaviour
/// were deleted or the brush aliased to another kind — not just "did
/// anything move". See `lib/src/sculpt_brush.dart` for what each kind is
/// meant to do and why `draw` and `inflate` differ.
library;

import 'dart:math';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A unit cube centred on the origin: eight corners, each an equal mix of
/// three axis-aligned faces, so each corner's own normal is exactly its own
/// normalized position — `draw`'s shared average and `inflate`'s per-vertex
/// normal differ measurably between any two corners that aren't a mirror
/// pair through the origin.
SculptMesh cube() =>
    SculptMesh.fromEditMesh(EditMesh.cuboid(size: Vector3(2, 2, 2)));

/// A flat triangle fan: a centre vertex surrounded by a ring of six, all at
/// `z = 0` unless overridden by [ringHeights] (ring index `0..5` to a `z`).
/// Planar by default, so its faces' normals are all exactly `(0, 0, 1)` and
/// `smooth`/`flatten` tests can reason about `z` directly instead of an
/// arbitrary tilted plane.
SculptMesh fan({Map<int, double> ringHeights = const <int, double>{}}) {
  const ringCount = 6;
  final builder = EditMeshBuilder();
  builder.addVertex(Vector3.zero());
  for (var k = 0; k < ringCount; k++) {
    final angle = k * (2 * pi / ringCount);
    builder.addVertex(Vector3(cos(angle), sin(angle), ringHeights[k] ?? 0.0));
  }
  for (var k = 0; k < ringCount; k++) {
    builder.addFace(<int>[0, 1 + k, 1 + (k + 1) % ringCount]);
  }
  return SculptMesh.fromEditMesh(builder.build());
}

/// The sculpt-mesh index of whichever vertex sits at [position] —
/// `fromEditMesh`'s own Morton reordering (`pro-sc-02`) means a fixture's
/// input vertex slot order is no longer its sculpt-mesh index, so a test
/// that needs one *specific* corner or ring vertex finds it by where it
/// actually is rather than assuming a fixed number.
int vertexNear(SculptMesh mesh, Vector3 position, {double epsilon = 1e-6}) {
  final p = Vector3.zero();
  for (var v = 0; v < mesh.vertexCount; v++) {
    mesh.positionOf(v, p);
    if (p.distanceToSquared(position) < epsilon) return v;
  }
  throw StateError('no vertex near $position in this mesh');
}

void expectVector3(Vector3 actual, Vector3 expected, {double epsilon = 1e-6}) {
  expect(actual.x, closeTo(expected.x, epsilon));
  expect(actual.y, closeTo(expected.y, epsilon));
  expect(actual.z, closeTo(expected.z, epsilon));
}

void main() {
  group('draw', () {
    test('moves every touched vertex along one shared average normal', () {
      // Corners 2 (1,1,-1) and 6 (1,1,1) are a mirror pair through z=0: their
      // own normals differ (their z components are opposite) but both are
      // exactly radius 1 from (1,1,0), so a no-op fails to move either, and
      // draw's per-vertex normal (inflate's behaviour) would move them by
      // different vectors instead of the same one.
      final mesh = cube();
      final c2 = vertexNear(mesh, Vector3(1, 1, -1));
      final c6 = vertexNear(mesh, Vector3(1, 1, 1));
      const brush = Brush(
        kind: BrushKind.draw,
        radius: 1.01,
        strength: 0.2,
        falloff: BrushFalloff.linear,
      );
      final before2 = mesh.positionOf(c2);
      final before6 = mesh.positionOf(c6);

      applyBrushStroke(mesh, brush, center: Vector3(1, 1, 0));

      final delta2 = mesh.positionOf(c2) - before2;
      final delta6 = mesh.positionOf(c6) - before6;
      expect(delta2.length, greaterThan(1e-4));
      expectVector3(delta2, delta6); // same displacement: one shared direction
      expect(delta2.x, greaterThan(0)); // pushed outward, not a no-op
    });
  });

  group('inflate', () {
    test(
      'moves each touched vertex along its own normal, not a shared one',
      () {
        final mesh = cube();
        final c2 = vertexNear(mesh, Vector3(1, 1, -1));
        final c6 = vertexNear(mesh, Vector3(1, 1, 1));
        const brush = Brush(
          kind: BrushKind.inflate,
          radius: 1.01,
          strength: 0.2,
          falloff: BrushFalloff.linear,
        );
        final before2 = mesh.positionOf(c2);
        final before6 = mesh.positionOf(c6);

        applyBrushStroke(mesh, brush, center: Vector3(1, 1, 0));

        final delta2 = mesh.positionOf(c2) - before2;
        final delta6 = mesh.positionOf(c6) - before6;
        expect(delta2.length, greaterThan(1e-4));
        // Corners 2 and 6 only differ in z; each moving along its OWN normal
        // means their z displacement has opposite sign — draw's shared normal
        // (measured above to have zero z component here) would give delta2.z
        // == delta6.z == 0, so this is exactly where the two kinds diverge.
        expect(delta6.z, greaterThan(0));
        expect(delta2.z, lessThan(0));
      },
    );
  });

  group('clay', () {
    test(
      'clamps buildup to a target height instead of pushing indefinitely',
      () {
        final mesh = cube();
        final c6 = vertexNear(mesh, Vector3(1, 1, 1));
        const brush = Brush(
          kind: BrushKind.clay,
          radius: 0.5,
          strength: 0.1,
          falloff: BrushFalloff.linear,
        );
        final initial = mesh.positionOf(c6);

        applyBrushStroke(mesh, brush, center: Vector3(1, 1, 1));
        final afterFirst = mesh.positionOf(c6);
        expect(
          afterFirst.distanceTo(initial),
          greaterThan(1e-4),
        ); // it did build up

        // A second, identical stroke: draw would push the vertex up again by
        // the same amount every time; clay's clamp means it is already at the
        // target plane and this stroke moves it by ~nothing.
        applyBrushStroke(mesh, brush, center: Vector3(1, 1, 1));
        final afterSecond = mesh.positionOf(c6);
        expect(afterSecond.distanceTo(afterFirst), lessThan(1e-6));
      },
    );
  });

  group('smooth', () {
    test(
      'is inert with identical neighbours, moves toward a perturbed average',
      () {
        const brush = Brush(
          kind: BrushKind.smooth,
          radius: 0.5,
          strength: 1.0,
          falloff: BrushFalloff.linear,
        );

        final flatMesh = fan();
        final flatCentre = vertexNear(flatMesh, Vector3.zero());
        final before = flatMesh.positionOf(flatCentre);
        applyBrushStroke(flatMesh, brush, center: Vector3.zero());
        expect(
          flatMesh.positionOf(flatCentre).distanceTo(before),
          lessThan(1e-9),
        );

        final perturbedMesh = fan(ringHeights: <int, double>{0: 1.0});
        final perturbedCentre = vertexNear(perturbedMesh, Vector3.zero());
        applyBrushStroke(perturbedMesh, brush, center: Vector3.zero());
        final centreAfter = perturbedMesh.positionOf(perturbedCentre);
        // Neighbour average is (5*0 + 1*1.0) / 6.
        expect(centreAfter.z, closeTo(1.0 / 6, 1e-6));
      },
    );
  });

  group('flatten', () {
    test(
      'pulls a raised vertex down and a lowered one up toward the plane',
      () {
        final mesh = fan(ringHeights: <int, double>{0: 2.0, 3: -2.0});
        // Ring index 0 sits at angle 0 (1, 0, height); ring index 3 at angle π
        // (-1, ~0, height) — `fan`'s own formula, found by position rather
        // than by the input slot index `fromEditMesh`'s reordering no longer
        // preserves.
        final raised = vertexNear(mesh, Vector3(cos(0), sin(0), 2.0));
        final lowered = vertexNear(mesh, Vector3(cos(pi), sin(pi), -2.0));
        // Radius wide enough to still reach the raised/lowered ring vertices,
        // which raising or lowering has pushed further than 1 from the origin.
        const brush = Brush(
          kind: BrushKind.flatten,
          radius: 2.5,
          strength: 1.0,
          falloff: BrushFalloff.linear,
        );
        final raisedBefore = mesh.positionOf(raised);
        final loweredBefore = mesh.positionOf(lowered);

        applyBrushStroke(mesh, brush, center: Vector3.zero());

        expect(mesh.positionOf(raised).z, lessThan(raisedBefore.z));
        expect(mesh.positionOf(lowered).z, greaterThan(loweredBefore.z));
      },
    );
  });

  group('grab', () {
    test('drags every touched vertex by the brush\'s own rigid delta', () {
      final mesh = cube();
      const brush = Brush(
        kind: BrushKind.grab,
        radius: 0.5,
        strength: 1.0,
        falloff: BrushFalloff.linear,
      );
      final start = mesh.positionOf(6);
      final drag = Vector3(0.2, -0.1, 0.05);

      applyBrushStroke(
        mesh,
        brush,
        center: start,
        previousCenter: start - drag,
      );

      expectVector3(mesh.positionOf(6), start + drag);
    });
  });

  group('pinch', () {
    test('pulls toward the brush centre within the tangent plane only', () {
      final mesh = cube();
      const brush = Brush(
        kind: BrushKind.pinch,
        radius: 1.0,
        strength: 1.0,
        falloff: BrushFalloff.linear,
      );
      final start = mesh.positionOf(6); // (1, 1, 1)
      final normal = vertexNormal(mesh, 6);
      final center = start + Vector3(0.5, 0, 0);

      applyBrushStroke(mesh, brush, center: center);

      final delta = mesh.positionOf(6) - start;
      expect(delta.length, greaterThan(1e-4));
      // The defining constraint: no component along the vertex's own
      // normal. A brush that just dragged the vertex toward the centre
      // (grab's behaviour, or a no-op tangent projection) would fail this.
      expect(delta.dot(normal).abs(), lessThan(1e-6));
    });
  });

  group('crease', () {
    test(
      'combines pinch\'s tangential pull with an inward fold along the normal',
      () {
        final mesh = cube();
        const brush = Brush(
          kind: BrushKind.crease,
          radius: 1.0,
          strength: 1.0,
          falloff: BrushFalloff.linear,
        );
        final start = mesh.positionOf(6);
        final normal = vertexNormal(mesh, 6);
        final center = start + Vector3(0.5, 0, 0);

        applyBrushStroke(mesh, brush, center: center);

        final delta = mesh.positionOf(6) - start;
        expect(delta.length, greaterThan(1e-4));
        // Unlike pinch, crease pushes inward along the normal too — this is
        // exactly the component pinch's test asserts is absent.
        expect(delta.dot(normal), lessThan(-1e-4));
      },
    );
  });

  group('symmetry', () {
    test('mirrors a stroke across x=0 to 1e-6', () {
      final mesh = cube();
      const brush = Brush(
        kind: BrushKind.grab,
        radius: 0.5,
        strength: 1.0,
        falloff: BrushFalloff.linear,
      );
      final start = mesh.positionOf(6); // (1, 1, 1)
      final drag = Vector3(0.2, -0.1, 0.05);

      applyBrushStroke(
        mesh,
        brush,
        center: start,
        previousCenter: start - drag,
        symmetryX: true,
      );

      final primaryFinal = mesh.positionOf(6);
      final mirroredFinal = mesh.positionOf(7); // (-1, 1, 1), x=0's mirror of 6
      expectVector3(
        mirroredFinal,
        Vector3(-primaryFinal.x, primaryFinal.y, primaryFinal.z),
        epsilon: 1e-6,
      );
    });
  });
}
