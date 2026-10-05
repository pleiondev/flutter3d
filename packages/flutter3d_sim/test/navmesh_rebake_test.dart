/// A part of a tiled navigation mesh baked again, held against the whole
/// level baked again.
///
///     dart test test/navmesh_rebake_test.dart
///
/// One claim: after a change, the mesh with the changed part baked again is
/// the mesh of the changed level baked whole, digest for digest. A wall
/// broken through at several places — mid-tile, on a tile's edge, at a
/// tile's corner — and a pillar put up where there was floor; each change is
/// a different set of tiles whose outlines move against their neighbours'.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Brush _box(double x0, double y0, double z0, double x1, double y1, double z1) =>
    Brush(
      centre: Vector3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
      size: Vector3(x1 - x0, y1 - y0, z1 - z0),
    );

/// Four-metre tiles on the half-metre lattice.
const NavMeshConfig _tiled = NavMeshConfig(tileSize: 8, maxEdgeError: 0.45);

/// Twenty-four metres by sixteen, a wall across it at x from 0 to 0.5 with
/// no way through.
List<Brush> _walled() => <Brush>[
  _box(-12, -1, -8, 12, 0, 8),
  _box(0, 0, -8, 0.5, 3, 8),
];

/// The same with the wall broken through for two metres from [z].
List<Brush> _broken(double z) => <Brush>[
  _box(-12, -1, -8, 12, 0, 8),
  _box(0, 0, -8, 0.5, 3, z),
  _box(0, 0, z + 2, 0.5, 3, 8),
];

/// Polygons reachable from [start] across shared edges.
Set<int> _reachable(NavMesh mesh, int start) {
  final seen = <int>{start};
  final queue = <int>[start];
  for (var i = 0; i < queue.length; i++) {
    final p = queue[i];
    for (var k = 0; k < mesh.polygonVertexCount(p); k++) {
      final q = mesh.neighbourAt(p, k);
      if (q >= 0 && seen.add(q)) queue.add(q);
    }
  }
  return seen;
}

void main() {
  final walled = NavMesh.bake(_walled(), config: _tiled);

  test('a tiled mesh walks no further than an untiled one', () {
    // The tiles cut the floor into more polygons, and they still join up.
    final untiled = NavMesh.bake(_walled());
    expect(walled.polygonCount, greaterThan(untiled.polygonCount));
    final west = walled.polygonAt(Vector3(-6, 0, 0));
    final east = walled.polygonAt(Vector3(6, 0, 0));
    expect(_reachable(walled, west), isNot(contains(east)));
    expect(
      _reachable(walled, west),
      contains(walled.polygonAt(Vector3(-11, 0, 7))),
    );
  });

  // Mid-tile, at a tile's edge (z = 0 is the lattice's row 16), and at the
  // lattice's corner, where the window is cut short.
  for (final z in <double>[-5.0, -1.0, 0.0, 1.0, 5.5, -8.0]) {
    test('a wall broken through at z = $z bakes as the broken level does', () {
      final rebaked = walled.rebake(
        _broken(z),
        minX: 0,
        minZ: z,
        maxX: 0.5,
        maxZ: z + 2,
      );
      final whole = NavMesh.bake(
        _broken(z),
        config: _tiled,
        lattice: walled.lattice,
      );
      // Mutation: giving the ring outlined again no regions beyond it
      // leaves its outer outlines drawn against nothing.
      expect(rebaked.digest, whole.digest);
      final route = rebaked.route(Vector3(-6, 0, z + 1), Vector3(6, 0, z + 1));
      expect(route!.complete, isTrue);
    });
  }

  test('a pillar put up bakes as the level with it does', () {
    final pillared = <Brush>[..._walled(), _box(-4, 0, 3, -3, 3, 4)];
    final rebaked = walled.rebake(
      pillared,
      minX: -4,
      minZ: 3,
      maxX: -3,
      maxZ: 4,
    );
    expect(
      rebaked.digest,
      NavMesh.bake(pillared, config: _tiled, lattice: walled.lattice).digest,
    );
    expect(rebaked.polygonsAt(-3.5, 3.5), isEmpty);
  });

  test('a pillar in the middle of a tile bakes as the level with it', () {
    // It forks the tile's region: the floor beside it in its rows is a
    // region of its own, and so the regions along the tile's edges change
    // where the neighbours' outlines meet them. Mutation: outlining again
    // only the tiles the change is in, not the ring round them.
    final pillared = <Brush>[..._walled(), _box(-6.5, 0, -6, -5.5, 3, -5)];
    expect(
      walled
          .rebake(pillared, minX: -6.5, minZ: -6, maxX: -5.5, maxZ: -5)
          .digest,
      NavMesh.bake(pillared, config: _tiled, lattice: walled.lattice).digest,
    );
  });

  test('a body wide enough to erode across a tile edge is baked again', () {
    // Eroded by three cells, a pillar beside a tile's first column moves
    // where the floor ends two cells into the tile before it. Mutation:
    // widening the change by one cell rather than by the erosion misses
    // that tile.
    const wide = NavMeshConfig(
      tileSize: 8,
      maxEdgeError: 0.45,
      agentRadius: 0.9,
    );
    final mesh = NavMesh.bake(_walled(), config: wide);
    final pillared = <Brush>[..._walled(), _box(-3.5, 0, 1, -2.5, 3, 2)];
    expect(
      mesh.rebake(pillared, minX: -3.5, minZ: 1, maxX: -2.5, maxZ: 2).digest,
      NavMesh.bake(pillared, config: wide, lattice: mesh.lattice).digest,
    );
  });

  test('tiles narrower than the erosion are baked again whole', () {
    // One-metre tiles and a three-cell erosion: the edge of the window is
    // within the erosion of the ring outlined again. Mutation: rasterising
    // the window to the tiles' edge, with no erosion's width round it.
    const small = NavMeshConfig(
      tileSize: 2,
      maxEdgeError: 0.45,
      agentRadius: 0.9,
    );
    final mesh = NavMesh.bake(_walled(), config: small);
    expect(
      mesh.rebake(_broken(-1), minX: 0, minZ: -1, maxX: 0.5, maxZ: 1).digest,
      NavMesh.bake(_broken(-1), config: small, lattice: mesh.lattice).digest,
    );
  });

  test('two changes one after the other bake as both at once', () {
    final both = <Brush>[..._broken(-5), _box(-4, 0, 3, -3, 3, 4)];
    final rebaked = walled
        .rebake(_broken(-5), minX: 0, minZ: -5, maxX: 0.5, maxZ: -3)
        .rebake(both, minX: -4, minZ: 3, maxX: -3, maxZ: 4);
    expect(
      rebaked.digest,
      NavMesh.bake(both, config: _tiled, lattice: walled.lattice).digest,
    );
  });

  group('is refused', () {
    test('for a mesh baked without tiles', () {
      expect(
        () => NavMesh.bake(
          _walled(),
        ).rebake(_broken(0), minX: 0, minZ: 0, maxX: 0.5, maxZ: 2),
        throwsStateError,
      );
    });

    test('for a mesh baked with jumps', () {
      final jumped = NavMesh.bake(
        <Brush>[_box(-6, -1, -2, -0.75, 0, 2), _box(0.75, -1, -2, 6, 0, 2)],
        config: _tiled,
        jumps: const JumpReach(jumpSpeed: 6, gravity: 20, runSpeed: 6),
      );
      expect(jumped.links, isNotEmpty);
      expect(
        () =>
            jumped.rebake(const <Brush>[], minX: 0, minZ: 0, maxX: 1, maxZ: 1),
        throwsUnsupportedError,
      );
    });
  });
}
