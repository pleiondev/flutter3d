import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_demo_reef/src/reef_life.dart';
import 'package:flutter3d_demo_reef/src/staging.dart';
import 'package:flutter3d_demo_reef/src/terrain.dart';
import 'package:flutter3d_demo_reef/src/wreck.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The hull as the game draws her, read from the file it ships.
Future<HullRoom> _hull() async {
  final document = await decodeModel(
    const ModelLoadRequest(source: FileAssetSource('assets/models/wreck.glb')),
  );
  return HullRoom(<(MeshData, Matrix4)>[
    for (final surface in document.surfaces) (surface.mesh, surface.transform),
  ]);
}

/// The smooth floor's upward normal at (x, z).
Vector3 _normal(double x, double z) {
  const d = floorCell;
  return Vector3(
    -(floorAt(x + d, z) - floorAt(x - d, z)) / (2 * d),
    1.0,
    -(floorAt(x, z + d) - floorAt(x, z - d)) / (2 * d),
  )..normalize();
}

void main() {
  test('nothing that grows on the reef stands inside the ship', () async {
    // The coral is drawn, not solid: nothing else stops a fan rooted a
    // hand's breadth off her side from standing through her planking into
    // the hold, where the eye sees it.
    //
    // Mutation: keep a colony by its root alone (`_clearOf` answering
    // true) — 2079 vertices of the reef's growth stand inside her.
    final hull = await _hull();
    final parts = growReef(hull, math.Random(7));
    var inside = 0, vertices = 0;
    for (final part in parts) {
      final v = part.vertices;
      final stride = part.layout.floatsPerVertex;
      for (var o = 0; o < v.length; o += stride) {
        vertices++;
        if (hull.holds(Vector3(v[o], v[o + 1], v[o + 2]))) inside++;
      }
    }
    expect(vertices, greaterThan(100000), reason: 'the reef grew');
    expect(inside, 0);
  });

  test('the wall is cut as deep as its ledges and gullies are made', () {
    // Down the middle of the wall, where it falls near two metres in one,
    // the relief cut along the floor's normal reaches more than a metre
    // and a half in, where a gully meets a ledge, and nowhere stands more
    // than half a metre out of the solid floor the diver touches.
    //
    // Mutations: cut the relief as a height rather than along the normal
    // (drop `/ max(normal.y, 0.4)`) — 1.06 m in at most; no gullies — 0.58
    // m; lumps on the wall not centred on it (drop `- 0.8 * wall`) — 1.20 m;
    // lumps half as high again (0.6 rather than 0.4) — they stand 0.61 m
    // out.
    var deepest = 0.0, highest = 0.0;
    for (var z = 1.0; z < reefSize - 1.0; z += 0.25) {
      final edge = wallTop + 2.0 * math.sin(z * 0.21);
      for (var x = edge - 6.0; x < edge + 12.0; x += 0.25) {
        final along = reliefAt(x, z) * _normal(x, z).y;
        final h = floorAt(x, z);
        if (h < -7.0 && h > -13.0) deepest = math.min(deepest, along);
        highest = math.max(highest, along);
      }
    }
    expect(deepest, lessThan(-1.5));
    expect(highest, lessThan(0.5));
  });

  group('the eye', () {
    // A wall three metres along the way from the diver to an eye five
    // metres off.
    double? wall(Vector3 from, Vector3 along, double reach) =>
        reach >= 3.0 ? 3.0 : null;
    final diver = Vector3(10.0, -6.0, 20.0);

    test('stays clear of what stands between it and the diver', () {
      // Mutation: put the eye on the wall (drop `- eyeClearance`) — 3.0.
      final eye = clearOfSolid(diver, diver + Vector3(5.0, 0.0, 0.0), wall);
      expect((eye - diver).length, closeTo(3.0 - eyeClearance, 1e-6));
    });

    test('is left where it is unless it is near what is in the way', () {
      // Mutation: cast no further than the eye (drop `+ eyeClearance`) —
      // an eye a hand's breadth short of the wall is left touching it.
      final near = clearOfSolid(diver, diver + Vector3(2.0, 0.0, 0.0), wall);
      expect((near - diver).length, closeTo(2.0, 1e-6));
      final close = clearOfSolid(diver, diver + Vector3(2.8, 0.0, 0.0), wall);
      expect((close - diver).length, closeTo(3.0 - eyeClearance, 1e-6));
    });
  });
}
