import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A closed box from (0, 0, 0) to [size], wound outwards.
MeshVessel _box(Vector3 size, {bool rim = true}) {
  final x = size.x, y = size.y, z = size.z;
  final p = <Vector3>[
    Vector3(0, 0, 0),
    Vector3(x, 0, 0),
    Vector3(x, y, 0),
    Vector3(0, y, 0),
    Vector3(0, 0, z),
    Vector3(x, 0, z),
    Vector3(x, y, z),
    Vector3(0, y, z),
  ];
  const quads = <List<int>>[
    [0, 3, 2, 1], [4, 5, 6, 7], // back, front
    [0, 1, 5, 4], [3, 7, 6, 2], // bottom, top
    [0, 4, 7, 3], [1, 2, 6, 5], // left, right
  ];
  return MeshVessel(
    positions: p,
    indices: [
      for (final q in quads) ...[q[0], q[1], q[2], q[0], q[2], q[3]],
    ],
    rim: rim ? [p[3], p[2], p[6], p[7]] : const [],
  );
}

/// A cylinder of [radius] and [height] as a lathe profile.
RevolvedVessel _cylinder(double radius, double height) => RevolvedVessel([
  Vector2(0, 0),
  Vector2(radius, 0),
  Vector2(radius, height),
]);

/// The same cylinder as a closed mesh of [segments] sides.
MeshVessel _cylinderMesh(double radius, double height, int segments) {
  final p = <Vector3>[Vector3(0, 0, 0), Vector3(0, height, 0)];
  for (var i = 0; i < segments; i++) {
    final a = 2 * math.pi * i / segments;
    p
      ..add(Vector3(radius * math.cos(a), 0, radius * math.sin(a)))
      ..add(Vector3(radius * math.cos(a), height, radius * math.sin(a)));
  }
  final idx = <int>[];
  for (var i = 0; i < segments; i++) {
    final b0 = 2 + 2 * i, t0 = b0 + 1;
    final b1 = 2 + 2 * ((i + 1) % segments), t1 = b1 + 1;
    idx
      ..addAll([0, b0, b1]) // floor, facing down
      ..addAll([1, t1, t0]) // lid, facing up
      ..addAll([b0, t0, t1, b0, t1, b1]); // side, facing out
  }
  return MeshVessel(positions: p, indices: idx);
}

void main() {
  group('a box', () {
    final box = _box(Vector3(1, 2, 3));
    test('holds its whole volume below its top', () {
      expect(box.volumeBelow(Vector3(0, 1, 0), 10), closeTo(6.0, 1e-12));
      expect(box.capacity, closeTo(6.0, 1e-12));
    });
    test('holds half below its middle, whichever way it is cut', () {
      // Mutation: sum against the origin instead of a point on the plane,
      // and the cut's own face is missing from the volume.
      final diagonal = Vector3(1, 2, 3)..normalize();
      final middle = diagonal.dot(Vector3(0.5, 1, 1.5));
      // Positions are single precision (vector_math), so to a millionth.
      expect(box.volumeBelow(diagonal, middle), closeTo(3.0, 1e-6));
      expect(box.volumeBelow(Vector3(0, 1, 0), 0.5), closeTo(1.5, 1e-12));
    });
    test('finds the surface that leaves a volume under it', () {
      final up = Vector3(0.3, 1, 0.2)..normalize();
      final h = box.surfaceFor(up, 2.0);
      expect(box.volumeBelow(up, h), closeTo(2.0, 1e-6));
    });
  });

  test('a cylinder upright is π r² h, exactly', () {
    final c = _cylinder(0.5, 2);
    expect(c.volumeUpTo(1.2), closeTo(math.pi * 0.25 * 1.2, 1e-12));
    expect(c.levelFor(math.pi * 0.25), closeTo(1.0, 1e-9));
  });

  test('a tilted cylinder keeps its volume under a plane through its axis', () {
    // A plane through the axis at mid height, not reaching floor or rim,
    // leaves the same volume as the level surface did: wedge for wedge.
    final c = _cylinder(0.5, 4);
    final up = Vector3(0, math.cos(0.4), -math.sin(0.4));
    final v = c.volumeBelow(up, up.dot(Vector3(0, 2, 0)));
    expect(v, closeTo(math.pi * 0.25 * 2, math.pi * 0.25 * 2 * 2e-3));
  });

  test('a lathe and a mesh of the same cylinder agree', () {
    final lathe = _cylinder(0.3, 1);
    final mesh = _cylinderMesh(0.3, 1, 256);
    for (final tilt in [0.0, 0.5, 1.2]) {
      final up = Vector3(math.sin(tilt), math.cos(tilt), 0);
      final h = up.dot(Vector3(0, 0.45, 0));
      expect(
        mesh.volumeBelow(up, h),
        closeTo(lathe.volumeBelow(up, h), lathe.volumeUpTo(1) * 3e-3),
        reason: 'tilt $tilt',
      );
    }
  });

  test('liquid leaves over the lowest point of the rim', () {
    final c = _cylinder(0.5, 2);
    final up = Vector3(math.sin(0.3), math.cos(0.3), 0);
    final edge = c.lip(up)!;
    expect(edge.point.x, closeTo(-0.5, 1e-9));
    // Tipped, it holds less than upright.
    expect(c.holds(up), lessThan(c.capacity));
    expect(_box(Vector3(1, 1, 1), rim: false).lip(up), isNull);
  });
}
