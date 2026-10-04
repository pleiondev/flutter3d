/// Cloth on the CPU and on the GPU — P9, phase 10.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:vector_math/vector_math.dart';

import 'bindings.dart' as c;
import 'gpu_bindings.dart' as g;
import 'native_particles.dart';

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
final class _Packed {
  _Packed(ClothMesh mesh)
    : points = malloc<Float>(mesh.points.length * 4),
      edges = malloc<Uint32>(mesh.edges.isEmpty ? 2 : mesh.edges.length * 2),
      compliance = malloc<Float>(mesh.edges.isEmpty ? 1 : mesh.edges.length) {
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

  final Pointer<Float> points;
  final Pointer<Uint32> edges;
  final Pointer<Float> compliance;

  void free() {
    malloc
      ..free(points)
      ..free(edges)
      ..free(compliance);
  }
}

Pointer<c.F3dCloth> _create(ClothMesh mesh) {
  final packed = _Packed(mesh);
  try {
    final cloth = c.f3d_cloth_create(
      packed.points,
      mesh.points.length,
      packed.edges,
      packed.compliance,
      mesh.edges.length,
    );
    if (cloth == nullptr) {
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

Pointer<Float> _packBalls(List<({Vector3 centre, double radius})> balls) {
  if (balls.length > c.clothMaxBalls) {
    throw ArgumentError.value(balls.length, 'balls', 'more than 16');
  }
  final data = malloc<Float>(balls.isEmpty ? 4 : balls.length * 4);
  for (var i = 0; i < balls.length; i++) {
    data[i * 4] = balls[i].centre.x;
    data[i * 4 + 1] = balls[i].centre.y;
    data[i * 4 + 2] = balls[i].centre.z;
    data[i * 4 + 3] = balls[i].radius;
  }
  return data;
}

/// Cloth stepped by the core on the CPU: the reference for the GPU's, and
/// the fallback where there is none.
final class NativeCloth implements ClothSystem, Finalizable {
  NativeCloth(ClothMesh mesh) : _c = _create(mesh) {
    _finalizer.attach(this, _c.cast(), detach: this);
  }

  static final NativeFinalizer _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<c.F3dCloth>)>>(
      c.f3d_cloth_destroy,
    ).cast(),
  );

  Pointer<c.F3dCloth> _c;
  int _steps = 0;
  int _read = 0;

  Pointer<c.F3dCloth> get _live {
    if (_c == nullptr) throw StateError('this cloth was disposed');
    return _c;
  }

  @override
  int get pointCount => c.f3d_cloth_point_count(_live);

  /// How many colours its constraints took.
  int get colourCount => c.f3d_cloth_colour_count(_live);

  @override
  void setBalls(List<({Vector3 centre, double radius})> balls) {
    final data = _packBalls(balls);
    try {
      c.f3d_cloth_set_balls(_live, data, balls.length);
    } finally {
      malloc.free(data);
    }
  }

  @override
  void movePoint(int index, Vector3 at) {
    c.f3d_cloth_move_point(_live, index, at.x, at.y, at.z);
  }

  @override
  void step(ClothSettings settings, double dt) {
    final s = calloc<c.F3dClothSettings>();
    try {
      final r = s.ref
        ..drag = settings.drag
        ..damping = settings.damping
        ..floor_y = settings.floorY
        ..thickness = settings.thickness
        ..friction = settings.friction
        ..substeps = settings.substeps;
      for (var k = 0; k < 3; k++) {
        r.gravity[k] = settings.gravity[k];
        r.wind[k] = settings.wind[k];
      }
      c.f3d_cloth_step(_live, s, dt);
      _steps++;
    } finally {
      calloc.free(s);
    }
  }

  @override
  ClothFrame? read({bool wait = true}) {
    final n = pointCount;
    if (_steps == _read) return null;
    final out = malloc<Float>(n * c.clothFloats);
    try {
      c.f3d_cloth_read(_live, out, n);
      _read = _steps;
      return (
        step: _steps,
        points: Float32List.fromList(out.asTypedList(n * c.clothFloats)),
      );
    } finally {
      malloc.free(out);
    }
  }

  @override
  void dispose() {
    if (_c == nullptr) return;
    _finalizer.detach(this);
    c.f3d_cloth_destroy(_c);
    _c = nullptr;
  }
}

/// [mesh] as a cloth on a GPU.
extension NativeGpuCloth on NativeGpu {
  GpuCloth cloth(ClothMesh mesh) => GpuCloth.on(this, mesh);
}

/// Cloth stepped on the GPU, a dispatch a colour, read a frame late. The
/// constraints are coloured by the core, so it solves what [NativeCloth]
/// solves in the same order of colours: the same to the GPU's rounding,
/// until folds and wrinkles take the two their own ways.
final class GpuCloth implements ClothSystem {
  GpuCloth.on(NativeGpu gpu, ClothMesh mesh)
    : _gpu = gpu,
      _points = mesh.points.length,
      _c = _upload(gpu, mesh);

  static Pointer<g.F3dGpuCloth> _upload(NativeGpu gpu, ClothMesh mesh) {
    final core = _create(mesh);
    final packed = _Packed(mesh);
    final edges = c.f3d_cloth_edge_count(core);
    final colours = c.f3d_cloth_colour_count(core);
    final pairs = malloc<Uint32>(edges == 0 ? 2 : edges * 2);
    final rest = malloc<Float>(edges == 0 ? 1 : edges);
    final compliance = malloc<Float>(edges == 0 ? 1 : edges);
    final start = malloc<Uint32>(colours + 1);
    try {
      c.f3d_cloth_edges(core, pairs, rest, compliance, start);
      final cloth = g.f3d_gpu_cloth_create(
        nativeGpuPointer(gpu),
        packed.points,
        mesh.points.length,
        pairs,
        rest,
        compliance,
        edges,
        start,
        colours,
      );
      if (cloth == nullptr) {
        throw ArgumentError.value(mesh, 'mesh', 'too large, or no memory');
      }
      return cloth;
    } finally {
      c.f3d_cloth_destroy(core);
      packed.free();
      malloc
        ..free(pairs)
        ..free(rest)
        ..free(compliance)
        ..free(start);
    }
  }

  final NativeGpu _gpu;
  final int _points;
  Pointer<g.F3dGpuCloth> _c;

  Pointer<g.F3dGpuCloth> get _live {
    if (_c == nullptr) throw StateError('this cloth was disposed');
    nativeGpuPointer(_gpu);
    return _c;
  }

  @override
  int get pointCount => _points;

  @override
  void setBalls(List<({Vector3 centre, double radius})> balls) {
    final data = _packBalls(balls);
    try {
      g.f3d_gpu_cloth_set_balls(_live, data, balls.length);
    } finally {
      malloc.free(data);
    }
  }

  @override
  void movePoint(int index, Vector3 at) {
    g.f3d_gpu_cloth_move_point(_live, index, at.x, at.y, at.z);
  }

  @override
  void step(ClothSettings settings, double dt) {
    final s = calloc<g.F3dGpuClothSettings>();
    try {
      final r = s.ref
        ..drag = settings.drag
        ..damping = settings.damping
        ..floor_y = settings.floorY
        ..thickness = settings.thickness
        ..friction = settings.friction
        ..substeps = settings.substeps;
      for (var k = 0; k < 3; k++) {
        r.gravity[k] = settings.gravity[k];
        r.wind[k] = settings.wind[k];
      }
      g.f3d_gpu_cloth_step(_live, s, dt);
    } finally {
      calloc.free(s);
    }
  }

  @override
  ClothFrame? read({bool wait = true}) {
    final out = malloc<Float>(_points * 4);
    try {
      final step = g.f3d_gpu_cloth_read(_live, out, _points, wait ? 1 : 0);
      if (step == 0) return null;
      return (
        step: step,
        points: Float32List.fromList(out.asTypedList(_points * 4)),
      );
    } finally {
      malloc.free(out);
    }
  }

  @override
  void dispose() {
    if (_c == nullptr) return;
    g.f3d_gpu_cloth_destroy(_c);
    _c = nullptr;
  }
}
