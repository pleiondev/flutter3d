/// A `flutter3d_physics` [ClothMesh] stepped by the core: the cloth a run
/// on [NativePhysics] gets from `backend.cloth(mesh)`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'core/core.dart' as c;
import 'native_physics.dart';

/// [mesh] stepped by `f3d_cloth_solve`, which does what `stepCloth` does.
///
/// The core holds its own copy of the sheet's constraints, triangles and
/// rest shape, made once here; every [step] hands it the mesh's positions,
/// velocities and inverse masses, the obstacles where they stand now and
/// the settings, and writes the positions and velocities back. A pinned
/// particle is not written back at all, so it stays at the double the mesh
/// holds rather than the single-precision copy the core stepped.
final class NativeClothSimulation extends ClothSimulation {
  NativeClothSimulation(this.mesh)
    : _held = (cloth: _make(mesh), state: c.F32s.alloc(_stateLength(mesh))) {
    _finalizer.attach(this, _held, detach: this);
  }

  static final Finalizer<_Held> _finalizer = Finalizer<_Held>(_free);

  static void _free(_Held held) {
    c.f3d_cloth_destroy(held.cloth);
    held.state.free();
  }

  @override
  final ClothMesh mesh;

  final _Held _held;
  bool _disposed = false;

  /// The compliances the core was last given, structural, bending and
  /// shear; null before the first step.
  (double, double, double)? _compliance;

  _Held get _live => _disposed
      ? throw StateError('this cloth simulation was disposed')
      : _held;

  static int _stateLength(ClothMesh mesh) =>
      math.max(1, mesh.particleCount * c.clothStateFloats);

  /// The constraints in the order the core is given them: structural,
  /// bending, shear.
  static List<(Int32List, Float64List)> _groups(ClothMesh mesh) =>
      <(Int32List, Float64List)>[
        (mesh.structuralPairs, mesh.structuralRestLength),
        (mesh.bendPairs, mesh.bendRestLength),
        (mesh.shearPairs, mesh.shearRestLength),
      ];

  static int _make(ClothMesh mesh) {
    final n = mesh.particleCount;
    final groups = _groups(mesh);
    final edgeCount = groups.fold(0, (sum, g) => sum + g.$2.length);
    final points = c.F32s.alloc(math.max(1, n * c.clothFloats));
    final edges = c.U32s.alloc(math.max(2, edgeCount * 2));
    final lengths = c.F32s.alloc(math.max(1, edgeCount));
    // Every compliance nought until the first step says what they are.
    final compliance = c.F32s.alloc(math.max(1, edgeCount))
      ..setAll(Float32List(math.max(1, edgeCount)));
    final corners = c.U32s.alloc(math.max(1, mesh.triangles.length));
    final rest = c.F32s.alloc(math.max(1, n * 3));
    try {
      points.setAll(<double>[
        for (var i = 0; i < n; i++) ...<double>[
          mesh.positions[3 * i],
          mesh.positions[3 * i + 1],
          mesh.positions[3 * i + 2],
          mesh.invMass[i],
        ],
      ]);
      final pairs = <int>[
        for (final g in groups) ...g.$1.take(2 * g.$2.length),
      ];
      for (var k = 0; k < pairs.length; k++) {
        edges[k] = pairs[k];
      }
      lengths.setAll(<double>[for (final g in groups) ...g.$2]);
      for (var k = 0; k < mesh.triangles.length; k++) {
        corners[k] = mesh.triangles[k];
      }
      rest.setAll(mesh.restPositions);
      final cloth = c.f3d_cloth_create(points, n, edges, compliance, edgeCount);
      if (cloth == 0) {
        throw ArgumentError.value(
          mesh,
          'mesh',
          'no particles, a constraint out of range or from a particle to '
              'itself, more constraints at one particle than the core '
              'colours, or no memory',
        );
      }
      if (c.f3d_cloth_set_triangles(
            cloth,
            corners,
            mesh.triangles.length ~/ 3,
          ) ==
          0) {
        c.f3d_cloth_destroy(cloth);
        throw ArgumentError.value(mesh, 'mesh', 'a triangle out of range');
      }
      // The mesh's own rest lengths, not the distances it was made at: a
      // mesh already stepped, or built in a folded pose, is not at rest.
      c.f3d_cloth_set_lengths(cloth, lengths);
      c.f3d_cloth_set_rest(cloth, rest);
      return cloth;
    } finally {
      points.free();
      edges.free();
      lengths.free();
      compliance.free();
      corners.free();
      rest.free();
    }
  }

  @override
  void step(
    ClothSettings settings,
    double dt, {
    List<ClothObstacle> obstacles = const <ClothObstacle>[],
  }) {
    final held = _live;
    if (dt <= 0 || settings.substeps <= 0) return;
    _complianceFrom(held.cloth, settings);
    final n = mesh.particleCount;
    final p = mesh.positions, v = mesh.velocities, w = mesh.invMass;
    held.state.setAll(<double>[
      for (var i = 0; i < n; i++) ...<double>[
        p[3 * i],
        p[3 * i + 1],
        p[3 * i + 2],
        v[3 * i],
        v[3 * i + 1],
        v[3 * i + 2],
        w[i],
      ],
    ]);
    c.f3d_cloth_write_state(held.cloth, held.state);
    _obstaclesFrom(held.cloth, obstacles);
    final s = _writeSettings(settings, mesh);
    try {
      c.f3d_cloth_solve(held.cloth, s, dt);
    } finally {
      c.coreFree(s);
    }
    c.f3d_cloth_read_state(held.cloth, held.state);
    final out = held.state.copy(n * c.clothStateFloats);
    for (var i = 0; i < n; i++) {
      if (w[i] == 0) continue;
      final at = i * c.clothStateFloats;
      p.setRange(3 * i, 3 * i + 3, out, at);
      v.setRange(3 * i, 3 * i + 3, out, at + 3);
    }
  }

  /// Gives the core [settings]' compliances, one per constraint in the
  /// order [_make] gave them, when they are not the ones it has.
  void _complianceFrom(int cloth, ClothSettings settings) {
    final wanted = (
      settings.distanceCompliance,
      settings.bendCompliance,
      settings.shearCompliance,
    );
    if (_compliance == wanted) return;
    final groups = _groups(mesh);
    final each = <double>[
      for (final (g, a) in <(int, double)>[
        (0, wanted.$1),
        (1, wanted.$2),
        (2, wanted.$3),
      ])
        for (var k = 0; k < groups[g].$2.length; k++) a,
    ];
    final block = c.F32s.alloc(math.max(1, each.length));
    try {
      if (each.isNotEmpty) block.setAll(each);
      c.f3d_cloth_set_compliance(cloth, block);
    } finally {
      block.free();
    }
    _compliance = wanted;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _free(_held);
  }
}

typedef _Held = ({int cloth, c.F32s state});

/// Gives [cloth] [obstacles] as the core's records, replacing the last.
void _obstaclesFrom(int cloth, List<ClothObstacle> obstacles) {
  final records = packClothObstacles(obstacles);
  final block = c.F32s.alloc(math.max(1, records.length));
  try {
    if (records.isNotEmpty) block.setAll(records);
    if (c.f3d_cloth_set_obstacles(cloth, block, records.length) == 0) {
      throw StateError(
        'the core refused the cloth obstacles, or ran out of '
        'memory for them',
      );
    }
  } finally {
    block.free();
  }
}

/// [obstacles] as the records `f3d_cloth_set_obstacles` reads: each shape
/// where it stands, in world space. A box and a wedge go as the planes the
/// reference pushes a particle out through; a heightfield as its samples,
/// with sample `(0, 0)` where `CollisionHeightfield.heightAt` puts it.
List<double> packClothObstacles(List<ClothObstacle> obstacles) => <double>[
  for (final ClothObstacle(:shape, :position) in obstacles)
    ...switch (shape) {
      CollisionSphere(:final radius) => <double>[
        c.ClothObstacleKind.ball.toDouble(),
        position.x,
        position.y,
        position.z,
        radius,
      ],
      CollisionCapsule(:final radius, :final halfHeight) => <double>[
        c.ClothObstacleKind.capsule.toDouble(),
        position.x,
        position.y,
        position.z,
        radius,
        halfHeight,
      ],
      CollisionBox() ||
      CollisionWedge() ||
      CustomShape() => _planes(shape, position),
      final CollisionHeightfield field => <double>[
        c.ClothObstacleKind.ground.toDouble(),
        position.x - field.width * 0.5,
        position.y - (field.highest + field.lowest) * 0.5,
        position.z - field.depth * 0.5,
        field.cellSize,
        field.columns.toDouble(),
        field.rows.toDouble(),
        field.thickness,
        for (var row = 0; row < field.rows; row++)
          for (var column = 0; column < field.columns; column++)
            field.sample(column, row),
      ],
    },
];

List<double> _planes(CollisionShape shape, Vector3 position) {
  final planes = Float64List(4 * shape.expandedPlaneCount);
  final count = shape.expandedPlanes(position, Vector3.zero(), planes);
  return <double>[
    c.ClothObstacleKind.convex.toDouble(),
    count.toDouble(),
    ...planes.take(4 * count),
  ];
}

/// [settings] for [mesh] as the core's `F3dClothSolveSettings`, in a block
/// of the core's memory the caller frees.
int _writeSettings(ClothSettings settings, ClothMesh mesh) {
  final s = c.coreAlloc(c.F3dClothSolveSettingsLayout.size);
  final wind = settings.wind;
  final gravity = <double>[0.0, -settings.gravity, 0.0];
  final air = <double>[wind.velocityX, wind.velocityY, wind.velocityZ];
  for (var k = 0; k < 3; k++) {
    c.writeF32(s + c.F3dClothSolveSettingsLayout.gravity + k * 4, gravity[k]);
    c.writeF32(s + c.F3dClothSolveSettingsLayout.wind + k * 4, air[k]);
  }
  final self = settings.selfCollision
      ? settings.selfCollisionThickness ?? mesh.meanRestEdge
      : 0.0;
  final reals = <(int, double)>[
    (c.F3dClothSolveSettingsLayout.windDrag, wind.drag),
    (c.F3dClothSolveSettingsLayout.damping, settings.damping),
    (c.F3dClothSolveSettingsLayout.thickness, settings.collisionThickness),
    (c.F3dClothSolveSettingsLayout.friction, settings.friction),
    (c.F3dClothSolveSettingsLayout.selfThickness, self > 0.0 ? self : 0.0),
    (
      c.F3dClothSolveSettingsLayout.selfFriction,
      settings.selfCollisionFriction,
    ),
  ];
  for (final (offset, value) in reals) {
    c.writeF32(s + offset, value);
  }
  c.writeU32(s + c.F3dClothSolveSettingsLayout.substeps, settings.substeps);
  c.writeU32(
    s + c.F3dClothSolveSettingsLayout.iterations,
    math.max(0, settings.iterations),
  );
  return s;
}
