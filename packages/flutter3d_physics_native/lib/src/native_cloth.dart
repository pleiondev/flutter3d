/// Cloth on the CPU and on the GPU — P9, phase 10.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'core/core.dart' as c;

/// The points of a cloth and the constraints between them, each held at
/// the distance it starts at.
final class ClothMesh {
  ClothMesh({
    required this.points,
    required this.inverseMasses,
    required this.edges,
    required this.compliances,
  }) {
    if (inverseMasses.length != points.length) {
      throw ArgumentError.value(inverseMasses.length, 'inverseMasses');
    }
    if (compliances.length != edges.length) {
      throw ArgumentError.value(compliances.length, 'compliances');
    }
  }

  /// A sheet of [columns] × [rows] points, [width] along x and [depth]
  /// along z from [origin], of [mass] kilograms in all; held by its
  /// structural edges at [stretch] compliance, and its diagonals and
  /// edges skipping a point at [bend]. The points in [pinned], by row and
  /// column as `row * columns + column`, stay where they are.
  factory ClothMesh.grid({
    required int columns,
    required int rows,
    double width = 1.0,
    double depth = 1.0,
    Vector3? origin,
    double mass = 0.2,
    double stretch = 1e-7,
    double bend = 1e-6,
    Set<int> pinned = const <int>{},
  }) {
    final from = origin ?? Vector3.zero();
    final count = columns * rows;
    final points = <Vector3>[
      for (var j = 0; j < rows; j++)
        for (var i = 0; i < columns; i++)
          from +
              Vector3(width * i / (columns - 1), 0.0, depth * j / (rows - 1)),
    ];
    final inverse = <double>[
      for (var k = 0; k < count; k++) pinned.contains(k) ? 0.0 : count / mass,
    ];
    final edges = <(int, int)>[];
    final compliances = <double>[];
    const links = <(int, int, bool)>[
      (1, 0, true),
      (0, 1, true),
      (1, 1, false),
      (1, -1, false),
      (2, 0, false),
      (0, 2, false),
    ];
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < columns; i++) {
        for (final (di, dj, structural) in links) {
          final ii = i + di;
          final jj = j + dj;
          if (ii < 0 || ii >= columns || jj < 0 || jj >= rows) continue;
          edges.add((j * columns + i, jj * columns + ii));
          compliances.add(structural ? stretch : bend);
        }
      }
    }
    return ClothMesh(
      points: points,
      inverseMasses: inverse,
      edges: edges,
      compliances: compliances,
    );
  }

  final List<Vector3> points;

  /// Nought for a point pinned where it is.
  final List<double> inverseMasses;
  final List<(int, int)> edges;

  /// Per edge, m/N; nought holds it rigid.
  final List<double> compliances;
}

/// How cloth moves. Sixteen substeps hold a sheet to under 2% stretch.
final class ClothSettings {
  ClothSettings({
    Vector3? gravity,
    Vector3? wind,
    this.drag = 0.0,
    this.damping = 0.5,
    this.floorY = -1e9,
    this.thickness = 0.01,
    this.friction = 0.3,
    this.substeps = 16,
  }) : gravity = gravity ?? Vector3(0.0, -9.81, 0.0),
       wind = wind ?? Vector3.zero();

  final Vector3 gravity;

  /// The air's velocity, and how fast a point drifts to it, per second.
  final Vector3 wind;
  final double drag;

  /// Per second, as v / (1 + c dt).
  final double damping;
  final double floorY;

  /// How far from a ball or the floor a point is held.
  final double thickness;

  /// The part of a touching point's slide taken away each substep.
  final double friction;
  final int substeps;
}

/// [ClothMesh] as the package's library exports it: `flutter3d_physics`
/// has a `ClothMesh` of its own, the one `PhysicsBackend.cloth` steps on
/// either backend, and a game imports both libraries.
typedef CoreClothMesh = ClothMesh;

/// [ClothSettings] as the package's library exports it; see [CoreClothMesh].
typedef CoreClothSettings = ClothSettings;

/// What a read gives: the step the points are from, counted from one, and
/// four floats a point — position xyz, inverse mass.
typedef ClothFrame = ({int step, Float32List points});

/// A cloth: on the CPU ([NativeCloth]) or the GPU ([GpuCloth]), the same
/// passes. Visual, not the game's state.
abstract interface class ClothSystem {
  int get pointCount;

  /// The balls the cloth falls on, replacing the last: at most 16.
  void setBalls(List<({Vector3 centre, double radius})> balls);

  /// Puts point [index] at [at], still: how a pinned point is carried.
  void movePoint(int index, Vector3 at);

  void step(ClothSettings settings, double dt);

  /// The latest step's points not read yet, or null when there is none. On
  /// the GPU, without [wait], a frame late.
  ClothFrame? read({bool wait = true});

  void dispose();
}

/// The mesh's arrays in the core's layout, freed by [free].
final class ClothPacked {
  ClothPacked(ClothMesh mesh)
    : points = c.F32s.alloc(mesh.points.length * 4),
      edges = c.U32s.alloc(mesh.edges.isEmpty ? 2 : mesh.edges.length * 2),
      compliance = c.F32s.alloc(mesh.edges.isEmpty ? 1 : mesh.edges.length) {
    for (var i = 0; i < mesh.points.length; i++) {
      points[i * 4] = mesh.points[i].x;
      points[i * 4 + 1] = mesh.points[i].y;
      points[i * 4 + 2] = mesh.points[i].z;
      points[i * 4 + 3] = mesh.inverseMasses[i];
    }
    for (var e = 0; e < mesh.edges.length; e++) {
      edges[e * 2] = mesh.edges[e].$1;
      edges[e * 2 + 1] = mesh.edges[e].$2;
      compliance[e] = mesh.compliances[e];
    }
  }

  final c.F32s points;
  final c.U32s edges;
  final c.F32s compliance;

  void free() {
    points.free();
    edges.free();
    compliance.free();
  }
}

int createCoreCloth(ClothMesh mesh) {
  final packed = ClothPacked(mesh);
  try {
    final cloth = c.f3d_cloth_create(
      packed.points,
      mesh.points.length,
      packed.edges,
      packed.compliance,
      mesh.edges.length,
    );
    if (cloth == 0) {
      throw ArgumentError.value(
        mesh,
        'mesh',
        'no points, an edge out of range or from a point to itself, or no '
            'memory',
      );
    }
    return cloth;
  } finally {
    packed.free();
  }
}

c.F32s packClothBalls(List<({Vector3 centre, double radius})> balls) {
  if (balls.length > c.clothMaxBalls) {
    throw ArgumentError.value(balls.length, 'balls', 'more than 16');
  }
  final data = c.F32s.alloc(balls.isEmpty ? 4 : balls.length * 4);
  for (var i = 0; i < balls.length; i++) {
    data[i * 4] = balls[i].centre.x;
    data[i * 4 + 1] = balls[i].centre.y;
    data[i * 4 + 2] = balls[i].centre.z;
    data[i * 4 + 3] = balls[i].radius;
  }
  return data;
}

/// [settings] as the core's `F3dClothSettings` — and the GPU's, laid out
/// the same — in a block of the core's memory the caller frees.
int writeClothSettings(ClothSettings settings) {
  final s = c.coreAlloc(c.F3dClothSettingsLayout.size);
  for (var k = 0; k < 3; k++) {
    c.writeF32(
      s + c.F3dClothSettingsLayout.gravity + k * 4,
      settings.gravity[k],
    );
    c.writeF32(s + c.F3dClothSettingsLayout.wind + k * 4, settings.wind[k]);
  }
  c.writeF32(s + c.F3dClothSettingsLayout.drag, settings.drag);
  c.writeF32(s + c.F3dClothSettingsLayout.damping, settings.damping);
  c.writeF32(s + c.F3dClothSettingsLayout.floorY, settings.floorY);
  c.writeF32(s + c.F3dClothSettingsLayout.thickness, settings.thickness);
  c.writeF32(s + c.F3dClothSettingsLayout.friction, settings.friction);
  c.writeU32(s + c.F3dClothSettingsLayout.substeps, settings.substeps);
  return s;
}

/// Cloth stepped by the core on the CPU: the reference for the GPU's, and
/// the fallback where there is none.
final class NativeCloth implements ClothSystem {
  NativeCloth(ClothMesh mesh) : _c = createCoreCloth(mesh) {
    _finalizer.attach(this, _c, detach: this);
  }

  static final Finalizer<int> _finalizer = Finalizer<int>(c.f3d_cloth_destroy);

  int _c;
  int _steps = 0;
  int _read = 0;

  int get _live {
    if (_c == 0) throw StateError('this cloth was disposed');
    return _c;
  }

  @override
  int get pointCount => c.f3d_cloth_point_count(_live);

  /// How many colours its constraints took.
  int get colourCount => c.f3d_cloth_colour_count(_live);

  @override
  void setBalls(List<({Vector3 centre, double radius})> balls) {
    final data = packClothBalls(balls);
    try {
      c.f3d_cloth_set_balls(_live, data, balls.length);
    } finally {
      data.free();
    }
  }

  @override
  void movePoint(int index, Vector3 at) {
    c.f3d_cloth_move_point(_live, index, at.x, at.y, at.z);
  }

  @override
  void step(ClothSettings settings, double dt) {
    final s = writeClothSettings(settings);
    try {
      c.f3d_cloth_step(_live, s, dt);
      _steps++;
    } finally {
      c.coreFree(s);
    }
  }

  @override
  ClothFrame? read({bool wait = true}) {
    final n = pointCount;
    if (_steps == _read) return null;
    final out = c.F32s.alloc(n * c.clothFloats);
    try {
      c.f3d_cloth_read(_live, out, n);
      _read = _steps;
      return (step: _steps, points: out.copy(n * c.clothFloats));
    } finally {
      out.free();
    }
  }

  @override
  void dispose() {
    if (_c == 0) return;
    _finalizer.detach(this);
    c.f3d_cloth_destroy(_c);
    _c = 0;
  }
}
