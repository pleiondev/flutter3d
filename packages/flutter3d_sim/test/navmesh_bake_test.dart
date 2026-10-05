/// The navigation mesh bake, held against the grid it sits beside.
///
///     dart test test/navmesh_bake_test.dart
///
/// Three claims run through every scene here. Every polygon is convex and
/// turns the same way, because the path search that comes next walks across
/// a polygon in a straight line and a reflex corner would put that line
/// through a wall. Adjacency is symmetric, because a search that can go from
/// one polygon to the next and not back finds routes that only work one way.
/// And the mesh covers exactly the cells `NavGrid` says a body of the same
/// radius fits in, because the two are two answers to one question about one
/// level and a disagreement between them is a bug in one or the other.
///
/// Then the digests: each scene's mesh written down as one number, so that CI
/// on every operating system bakes the same mesh or says it did not.
library;

import 'dart:typed_data';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Brush _box(double x0, double y0, double z0, double x1, double y1, double z1) =>
    Brush(
      centre: Vector3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
      size: Vector3(x1 - x0, y1 - y0, z1 - z0),
    );

/// Ten metres square, its top at nought.
List<Brush> _floor() => <Brush>[_box(-5, -1, -5, 5, 0, 5)];

/// Two rooms either side of a wall half a metre thick, joined by a doorway
/// two metres wide under a lintel.
List<Brush> _rooms() => <Brush>[
  _box(-6, -1, -3, 6, 0, 3),
  _box(0, 0, -3, 0.5, 3, -1),
  _box(0, 0, 1, 0.5, 3, 3),
  _box(0, 2.5, -1, 0.5, 3, 1),
];

/// A floor and two steps up from it, each taller than an agent climbs.
List<Brush> _tallSteps() => <Brush>[
  _box(-2, -1, -4, 2, 0, 0),
  _box(-2, -1, 0, 2, 0.6, 2),
  _box(-2, -1, 2, 2, 1.2, 4),
];

/// The same, each step short enough to walk up.
List<Brush> _shortSteps() => <Brush>[
  _box(-2, -1, -4, 2, 0, 0),
  _box(-2, -1, 0, 2, 0.3, 2),
  _box(-2, -1, 2, 2, 0.6, 4),
];

/// A floor, a ramp climbing a metre and a half over six, and the platform at
/// its top.
List<Brush> _ramp() => <Brush>[
  _box(-2, -1, -4, 2, 0, 0),
  Brush(
    centre: Vector3(0, 0.75, 3),
    size: Vector3(4, 1.5, 6),
    ramp: WedgeUphill.positiveZ,
  ),
  _box(-2, -1, 6, 2, 1.5, 10),
];

/// The floor with a pillar a metre square standing in the middle of it.
List<Brush> _pillar() => <Brush>[..._floor(), _box(0, 0, 0, 1, 3, 1)];

/// Twenty degrees of slope and the default step: ground steeper than the one
/// and gentler than the other exists, which is the point of [_hillside].
const NavMeshConfig _hills = NavMeshConfig(maxSlope: 0.35);

/// Terrain: flat for eight metres, then a hillside rising one in five, then
/// a bank rising three in five, then flat again at the top.
///
/// **The bank is steep and not tall.** Thirty-one degrees, past the twenty
/// [_hills] allows, but each half-metre cell of it rises 0.3 — under the
/// step. So the slope test is the only thing between the hillside and the
/// top; a cliff would be refused by the step as well, and a test of it would
/// pass with the slope test deleted.
Heightfield _hillside() {
  const columns = 21;
  const rows = 9;
  double height(int x) => switch (x) {
    < 8 => 0.0,
    < 14 => (x - 8) * 0.2,
    < 17 => 1.2 + (x - 14) * 0.6,
    _ => 3.0,
  };
  return Heightfield(
    columns: columns,
    rows: rows,
    cellSize: 1.0,
    heights: Float32List.fromList(<double>[
      for (var z = 0; z < rows; z++)
        for (var x = 0; x < columns; x++) height(x),
    ]),
  );
}

/// Twice the signed area of corner [k] of [polygon], turning from the corner
/// before it to the one after, in lattice units.
int _turn(NavMesh mesh, int polygon, int k) {
  final n = mesh.polygonVertexCount(polygon);
  final a = mesh.polygonVertex(polygon, (k + n - 1) % n);
  final b = mesh.polygonVertex(polygon, k);
  final c = mesh.polygonVertex(polygon, (k + 1) % n);
  return (mesh.latticeX(b) - mesh.latticeX(a)) *
          (mesh.latticeZ(c) - mesh.latticeZ(a)) -
      (mesh.latticeZ(b) - mesh.latticeZ(a)) *
          (mesh.latticeX(c) - mesh.latticeX(a));
}

/// The claims every mesh in this file has to meet, whatever it was baked
/// from.
void _expectWellFormed(NavMesh mesh) {
  for (var p = 0; p < mesh.polygonCount; p++) {
    final n = mesh.polygonVertexCount(p);
    expect(n, inInclusiveRange(3, mesh.maxVerticesPerPolygon));
    expect(mesh.areaOf(p), isNot(NavArea.none));
    // Mutation: dropping the reversal of outlines that turn right leaves
    // whole polygons wound the other way, and every corner of them fails.
    for (var k = 0; k < n; k++) {
      expect(
        _turn(mesh, p, k),
        greaterThanOrEqualTo(0),
        reason: 'polygon $p has a reflex corner at $k',
      );
    }
    final area = Iterable<int>.generate(n).fold(0, (sum, k) {
      final a = mesh.polygonVertex(p, k);
      final b = mesh.polygonVertex(p, (k + 1) % n);
      return sum +
          mesh.latticeX(a) * mesh.latticeZ(b) -
          mesh.latticeX(b) * mesh.latticeZ(a);
    });
    expect(area, greaterThan(0), reason: 'polygon $p covers nothing');

    // Mutation: recording a match on one side only — `out[slot] = …` without
    // `out[other] = p` — leaves every second polygon blind to the first.
    for (var k = 0; k < n; k++) {
      final q = mesh.neighbourAt(p, k);
      if (q < 0) continue;
      final a = mesh.polygonVertex(p, k);
      final b = mesh.polygonVertex(p, (k + 1) % n);
      final m = mesh.polygonVertexCount(q);
      final back = Iterable<int>.generate(m).where(
        (j) =>
            mesh.neighbourAt(q, j) == p &&
            mesh.polygonVertex(q, j) == b &&
            mesh.polygonVertex(q, (j + 1) % m) == a,
      );
      expect(back, hasLength(1), reason: '$p sees $q across $k, not back');
    }
  }
}

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

/// The lowest and highest corner of [polygon], in metres.
(double, double) _heights(NavMesh mesh, int polygon) {
  final v = Vector3.zero();
  return Iterable<int>.generate(mesh.polygonVertexCount(polygon)).fold(
    (double.infinity, double.negativeInfinity),
    (range, k) {
      mesh.vertexAt(mesh.polygonVertex(polygon, k), v);
      return (range.$1 < v.y ? range.$1 : v.y, range.$2 > v.y ? range.$2 : v.y);
    },
  );
}

/// The polygon a body stands on at the centre of grid cell [cell], or −1.
int _standingOn(NavMesh mesh, NavGrid grid, int cell) {
  final centre = grid.centreOfCell(cell);
  return mesh.polygonsAt(centre.x, centre.z).firstWhere((p) {
    final (low, high) = _heights(mesh, p);
    return low - grid.stepHeight <= centre.y &&
        centre.y <= high + grid.stepHeight;
  }, orElse: () => -1);
}

/// Cell by cell: the mesh covers a cell's centre exactly when the grid says a
/// body of [radius] fits there.
void _expectCoverageMatches(NavMesh mesh, NavGrid grid, double radius) {
  expect(mesh.originX, grid.originX, reason: 'not the same lattice');
  expect(mesh.originZ, grid.originZ, reason: 'not the same lattice');
  final need = grid.clearanceForRadius(radius);
  final wrong = <String>[
    for (var cell = 0; cell < grid.cellCount; cell++)
      if ((grid.isWalkable(cell) && grid.clearanceAt(cell) >= need) !=
          (_standingOn(mesh, grid, cell) >= 0))
        '(${grid.cellX(cell)}, ${grid.cellZ(cell)})',
  ];
  expect(wrong, isEmpty, reason: 'the mesh and the grid disagree at $wrong');
}

void main() {
  const config = NavMeshConfig();

  group('a flat floor', () {
    final mesh = NavMesh.bake(_floor());

    test('is one quadrilateral, a body\'s radius in from the edge', () {
      _expectWellFormed(mesh);
      // Mutation: eroding by `agentRadius / cellSize` rounded down, rather
      // than by `NavGrid`'s rule, keeps the outer ring and the corners land on
      // the brush's own edge at (0, 0) and (20, 20).
      expect(mesh.polygonCount, 1);
      expect(mesh.polygonVertexCount(0), 4);
      final corners = <(int, int)>{
        for (var k = 0; k < 4; k++)
          (
            mesh.latticeX(mesh.polygonVertex(0, k)),
            mesh.latticeZ(mesh.polygonVertex(0, k)),
          ),
      };
      expect(corners, <(int, int)>{(1, 1), (19, 1), (19, 19), (1, 19)});
      final v = Vector3.zero();
      mesh.vertexAt(mesh.polygonVertex(0, 0), v);
      expect(v.y, closeTo(0.0, 1e-9), reason: 'the floor is at nought');
    });

    test('covers what the grid covers', () {
      _expectCoverageMatches(mesh, NavGrid.bake(_floor()), config.agentRadius);
    });
  });

  group('two rooms and a doorway', () {
    test('are one walk for a body that fits the doorway', () {
      final mesh = NavMesh.bake(_rooms());
      _expectWellFormed(mesh);
      final west = _standingOnPoint(mesh, -4.0, 0.0);
      final east = _standingOnPoint(mesh, 4.0, 0.0);
      expect(west, isNonNegative);
      expect(east, isNonNegative);
      // Mutation: matching an edge against itself rather than its reverse —
      // `open.remove((a, b))` — finds no neighbour anywhere, and the rooms
      // fall apart along with everything else.
      expect(_reachable(mesh, west), contains(east));
      _expectCoverageMatches(mesh, NavGrid.bake(_rooms()), config.agentRadius);
    });

    test('and two for a body too wide for it', () {
      const wide = NavMeshConfig(agentRadius: 0.8);
      final mesh = NavMesh.bake(_rooms(), config: wide);
      _expectWellFormed(mesh);
      final west = _standingOnPoint(mesh, -4.0, 0.0);
      final east = _standingOnPoint(mesh, 4.0, 0.0);
      // Mutation: the erosion rule of the flat floor's test, the radius over
      // the cell rounded down, keeps a cell of the doorway for this body too.
      expect(_reachable(mesh, west), isNot(contains(east)));
      _expectCoverageMatches(mesh, NavGrid.bake(_rooms()), wide.agentRadius);
    });

    test('and the wall\'s own top is not a floor anybody fits on', () {
      final mesh = NavMesh.bake(_rooms());
      final v = Vector3.zero();
      for (var i = 0; i < mesh.vertexCount; i++) {
        mesh.vertexAt(i, v);
        expect(v.y, lessThan(0.5), reason: 'a vertex on the wall at $v');
      }
    });
  });

  group('steps', () {
    test('taller than a step are floors that do not touch', () {
      final mesh = NavMesh.bake(_tallSteps());
      _expectWellFormed(mesh);
      final bottom = _standingOnPoint(mesh, 0.0, -2.0);
      final top = _standingOnPoint(mesh, 0.0, 3.0);
      expect(bottom, isNonNegative);
      expect(top, isNonNegative);
      expect(_reachable(mesh, bottom), isNot(contains(top)));
      _expectCoverageMatches(
        mesh,
        NavGrid.bake(_tallSteps()),
        config.agentRadius,
      );
    });

    test('even for a body with no width, which nothing erodes', () {
      // **The radius hides a riser.** Eroded by a body's width, the floor
      // either side of a riser is gone before anything links across it, so
      // the claim above holds whether or not the link is right. Here there
      // is no erosion and the link is all that keeps the floors apart.
      const thin = NavMeshConfig(agentRadius: 0.0);
      final mesh = NavMesh.bake(_tallSteps(), config: thin);
      _expectWellFormed(mesh);
      final bottom = _standingOnPoint(mesh, 0.0, -2.0);
      final top = _standingOnPoint(mesh, 0.0, 3.0);
      expect(_reachable(mesh, bottom), isNot(contains(top)));
      // Mutation: comparing the rise without `.abs()` in `OpenField.build`
      // links every step down to the floor below it. The first row of each
      // step joins the region under it, and the mesh stops covering that
      // row where the grid does — rows 8 and 12, measured.
      _expectCoverageMatches(mesh, NavGrid.bake(_tallSteps()), 0.0);
    });

    test('short enough to climb are one walk', () {
      final mesh = NavMesh.bake(_shortSteps());
      _expectWellFormed(mesh);
      final bottom = _standingOnPoint(mesh, 0.0, -2.0);
      final top = _standingOnPoint(mesh, 0.0, 3.0);
      expect(_reachable(mesh, bottom), contains(top));
      _expectCoverageMatches(
        mesh,
        NavGrid.bake(_shortSteps()),
        config.agentRadius,
      );
    });
  });

  group('a ramp', () {
    test('is a walk from the floor to the platform it climbs to', () {
      final mesh = NavMesh.bake(_ramp());
      _expectWellFormed(mesh);
      final bottom = _standingOnPoint(mesh, 0.0, -2.0);
      final top = _standingOnPoint(mesh, 0.0, 8.0);
      expect(bottom, isNonNegative);
      expect(top, isNonNegative);
      // Mutation: rasterising a ramp at the top of its box, as the grid
      // does, makes its foot a riser a metre and a half tall.
      expect(_reachable(mesh, bottom), contains(top));
    });
  });

  group('a pillar in the middle of the floor', () {
    final mesh = NavMesh.bake(_pillar());

    test(
      'is a hole the polygons go round, and the floor is still one walk',
      () {
        _expectWellFormed(mesh);
        // Mutation: keeping the lower top when two spans in a column merge —
        // the floor's, rather than the pillar's standing on it — lays a floor
        // under the pillar that the agent walks through.
        expect(mesh.polygonsAt(0.5, 0.5), isEmpty);
        expect(_reachable(mesh, 0), hasLength(mesh.polygonCount));
        _expectCoverageMatches(
          mesh,
          NavGrid.bake(_pillar()),
          config.agentRadius,
        );
      },
    );
  });

  group('terrain', () {
    final field = _hillside();
    final mesh = NavMesh.bake(const <Brush>[], ground: field, config: _hills);

    test('walks up a hillside and stops at a bank too steep for it', () {
      _expectWellFormed(mesh);
      final low = _standingOnPoint(mesh, 3.0, 4.0);
      final slope = _standingOnPoint(mesh, 11.0, 4.0);
      final top = _standingOnPoint(mesh, 19.0, 4.0);
      expect(low, isNonNegative);
      expect(slope, isNonNegative);
      expect(top, isNonNegative);
      // Mutation: rasterising terrain without the slope test makes the bank
      // a floor, and at 0.3 a cell it is a walk up to the top.
      expect(mesh.polygonsAt(15.5, 4.0), isEmpty);
      expect(_reachable(mesh, low), contains(slope));
      expect(_reachable(mesh, low), isNot(contains(top)));
      final (_, high) = _heights(mesh, slope);
      expect(high, greaterThan(0.5), reason: 'the hillside baked flat');
    });

    test('covers what the grid covers', () {
      _expectCoverageMatches(
        mesh,
        NavGrid.bakeHeightfield(
          field,
          stepHeight: _hills.stepHeight,
          maxSlope: _hills.maxSlope,
        ),
        _hills.agentRadius,
      );
    });
  });

  group('an empty level', () {
    test('bakes an empty mesh rather than refusing', () {
      final mesh = NavMesh.bakeLevel(Level(name: 'empty'));
      expect(mesh.isEmpty, isTrue);
      expect(mesh.vertexCount, 0);
    });
  });

  group('the same mesh everywhere', () {
    test('listing the brushes in another order bakes the same mesh', () {
      // Mutation: merging spans in arrival order rather than sorted makes the
      // area of a shared top depend on which brush came first.
      expect(
        NavMesh.bake(_rooms().reversed).digest,
        NavMesh.bake(_rooms()).digest,
      );
      expect(
        NavMesh.bake(_pillar().reversed).digest,
        NavMesh.bake(_pillar()).digest,
      );
    });

    // Written down on macOS-arm64 under the VM, matched the same day under
    // Chrome, and compared on every other machine CI runs on. A change here
    // is a change to the mesh: say why in the commit that makes it, or find
    // out what moved.
    //
    // Mutation: any float the voxeliser rounds differently on another
    // platform — a libm `tan` for the ramp test, an `atan2` in the slope —
    // moves a span by a voxel and the digest with it, on that platform only.
    final golden = <(String, NavMesh Function(), String)>[
      ('empty', () => NavMesh.bakeLevel(Level(name: 'empty')), 'fe276f3c'),
      ('floor', () => NavMesh.bake(_floor()), '783ba6ce'),
      ('rooms', () => NavMesh.bake(_rooms()), 'f144af84'),
      ('tall steps', () => NavMesh.bake(_tallSteps()), 'f2789294'),
      ('pillar', () => NavMesh.bake(_pillar()), 'cc1d04ae'),
      (
        'hillside',
        () =>
            NavMesh.bake(const <Brush>[], ground: _hillside(), config: _hills),
        '749064c4',
      ),
    ];
    for (final (name, bake, digest) in golden) {
      test('the $name mesh is $digest', () {
        expect(bake().digestHex, digest);
      });
    }
  });
}

/// The polygon under world `(x, z)`, or −1.
int _standingOnPoint(NavMesh mesh, double x, double z) {
  final found = mesh.polygonsAt(x, z);
  return found.isEmpty ? -1 : found.first;
}
