/// Cloth on the CPU — P9, phase 10 — and its colouring, which a GPU
/// steps it by.
library;

import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:vector_math/vector_math.dart';

import 'core/core.dart' as c;
import 'native_world.dart';

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
///
/// **Its gravity and its wind are its world's.** Given a [world], a sheet
/// falls as that world does and its air moves with that world's wind (at
/// the world's origin — `NativeWorld.windAt`); given neither, it falls by
/// [standardGravityVector] in still air. Read when the settings are made,
/// and the settings are handed to every step — so a game that changes its
/// world's gravity or wind mid-run makes them again and the cloth follows
/// from that step on. The wind moves the cloth only with a [drag].
final class ClothSettings {
  ClothSettings({
    NativeWorld? world,
    Vector3? gravity,
    Vector3? wind,
    this.drag = 0.0,
    this.damping = 0.5,
    this.floorY = -1e9,
    this.thickness = 0.01,
    this.friction = 0.3,
    this.substeps = 16,
  }) : gravity = gravity ?? world?.gravity ?? standardGravityVector,
       wind = wind ?? world?.windAt(Vector3.zero()) ?? Vector3.zero();

  /// A copy with the given fields replaced. A `clear…` flag resets that
  /// nullable field to null, which passing null cannot say.
  // ignore: avoid-incomplete-copy-with, the world only seeds the defaults and is not kept
  ClothSettings copyWith({
    Vector3? gravity,
    Vector3? wind,
    double? drag,
    double? damping,
    double? floorY,
    double? thickness,
    double? friction,
    int? substeps,
    bool clearGravity = false,
    bool clearWind = false,
  }) => ClothSettings(
    gravity: clearGravity ? null : (gravity ?? this.gravity),
    wind: clearWind ? null : (wind ?? this.wind),
    drag: drag ?? this.drag,
    damping: damping ?? this.damping,
    floorY: floorY ?? this.floorY,
    thickness: thickness ?? this.thickness,
    friction: friction ?? this.friction,
    substeps: substeps ?? this.substeps,
  );

  final Vector3 gravity;

  /// The air's velocity, and how fast a point drifts to it, per second.
  final Vector3 wind;

  /// How fast a point drifts to the [wind], per second, as
  /// v' = w + (v − w) / (1 + drag dt).
  final double drag;

  /// Per second, as v / (1 + c dt).
  final double damping;

  /// The floor's height, in metres.
  final double floorY;

  /// How far from a ball or the floor a point is held, in metres.
  final double thickness;

  /// The part of a touching point's slide taken away each substep: a
  /// fraction, 0..1.
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
///
/// A class rather than a record, so it can carry more in a minor without
/// breaking a backend that mixes the system in.
final class ClothFrame {
  const ClothFrame({required this.step, required this.points});

  /// The step, counted from one.
  final int step;

  /// Four floats a point: position xyz in metres, inverse mass in 1/kg.
  final Float32List points;

  /// Equal to another with the same fields, as the record it was compared.
  @override
  bool operator ==(Object other) =>
      other is ClothFrame && other.step == step && other.points == points;

  @override
  int get hashCode => Object.hash(step, points);

  @override
  String toString() => 'ClothFrame(step: $step, points: $points)';
}

/// A ball a cloth falls on.
///
/// A class rather than a record, so it can carry more in a minor without
/// breaking a backend that mixes the system in.
final class ClothBall {
  const ClothBall({required this.center, required this.radius});

  /// Where it is, in metres.
  final Vector3 center;

  /// How big, in metres.
  final double radius;

  /// Equal to another with the same fields, as the record it was compared.
  @override
  bool operator ==(Object other) =>
      other is ClothBall && other.center == center && other.radius == radius;

  @override
  int get hashCode => Object.hash(center, radius);

  @override
  String toString() => 'ClothBall(center: $center, radius: $radius)';
}

/// A cloth: on the CPU ([NativeCloth]), or on a GPU through the hardware
/// layer (`ClothWorkload` in `flutter3d_effects`, from [clothKernels]), the
/// same passes. Visual, not the game's state.
///
/// **Mixed in, not implemented**, outside this library: a `base` type, so a
/// member added in a 1.x release arrives with a body and nothing that mixes
/// it in has to change.
abstract base mixin class ClothSystem {
  int get pointCount;

  /// The balls the cloth falls on, replacing the last: at most 16.
  void setBalls(List<ClothBall> balls);

  /// Puts the move's point at its place, still: how a pinned point is
  /// carried.
  void movePoint(ClothPointMove move);

  /// One step of the cloth, as [ClothSystemStep] says.
  void step(ClothSystemStep step);

  /// The latest step's points not read yet; null when there is none
  /// (absent, not an error). Stepped on a GPU, a frame or two late.
  ClothFrame? read({bool wait = true});

  void dispose();
}

/// What [ClothSystem.movePoint] is handed: point [index] goes to [at].
///
/// **One object, so a minor can hand a cloth more** — a velocity to carry
/// the point with — without breaking one written against 1.0.
/// **Reusable**: a point dragged every frame keeps one and sets it before
/// the call; the cloth reads it during the call and does not keep it.
final class ClothPointMove {
  ClothPointMove({required this.index, required this.at});

  /// The point.
  int index;

  /// Where it goes.
  Vector3 at;
}

/// What [ClothSystem.step] is handed: the settings and the step's length in
/// seconds.
///
/// One object, reusable, for the reasons [ClothPointMove] gives.
final class ClothSystemStep {
  ClothSystemStep({required this.settings, required this.dt});

  /// How the cloth behaves.
  ClothSettings settings;

  /// The step, in seconds.
  double dt;
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

/// The core's colouring of a [ClothMesh]'s edges: what [NativeCloth]
/// solves, colour by colour, and what a cloth stepped elsewhere solves in
/// the same order — `clothKernels`, one dispatch a colour.
///
/// **Inside a colour no two edges share a point**, so each colour is one
/// pass whose edges are solved at once, and nothing is summed in an order
/// a GPU would choose.
final class ClothColoring {
  /// The colouring the core makes of [mesh].
  factory ClothColoring.of(ClothMesh mesh) {
    final core = createCoreCloth(mesh);
    final edges = c.f3d_cloth_edge_count(core);
    final colours = c.f3d_cloth_colour_count(core);
    final pairs = c.U32s.alloc(edges == 0 ? 2 : edges * 2);
    final rest = c.F32s.alloc(edges == 0 ? 1 : edges);
    final compliance = c.F32s.alloc(edges == 0 ? 1 : edges);
    final start = c.U32s.alloc(colours + 1);
    try {
      c.f3d_cloth_edges(core, pairs, rest, compliance, start);
      return ClothColoring._(
        pairs: Uint32List.fromList(<int>[
          for (var k = 0; k < edges * 2; k++) pairs[k],
        ]),
        rest: rest.copy(edges),
        compliance: compliance.copy(edges),
        colorStart: Uint32List.fromList(<int>[
          for (var k = 0; k <= colours; k++) start[k],
        ]),
      );
    } finally {
      c.f3d_cloth_destroy(core);
      pairs.free();
      rest.free();
      compliance.free();
      start.free();
    }
  }

  ClothColoring._({
    required this.pairs,
    required this.rest,
    required this.compliance,
    required this.colorStart,
  });

  /// The two points of each edge, colour by colour.
  final Uint32List pairs;

  /// Each edge's rest length, in metres.
  final Float32List rest;

  /// Each edge's compliance, nought or more.
  final Float32List compliance;

  /// Where each colour's edges start, and after the last, the edge count.
  final Uint32List colorStart;

  /// How many edges.
  int get edgeCount => rest.length;

  /// How many colours.
  int get colorCount => colorStart.length - 1;
}

c.F32s packClothBalls(List<ClothBall> balls) {
  if (balls.length > c.clothMaxBalls) {
    throw ArgumentError.value(balls.length, 'balls', 'more than 16');
  }
  final data = c.F32s.alloc(balls.isEmpty ? 4 : balls.length * 4);
  for (var i = 0; i < balls.length; i++) {
    data[i * 4] = balls[i].center.x;
    data[i * 4 + 1] = balls[i].center.y;
    data[i * 4 + 2] = balls[i].center.z;
    data[i * 4 + 3] = balls[i].radius;
  }
  return data;
}

/// [settings] as the core's `F3dClothSettings` in a block of the core's memory the
/// caller frees.
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
  int get colorCount => c.f3d_cloth_colour_count(_live);

  @override
  void setBalls(List<ClothBall> balls) {
    final data = packClothBalls(balls);
    try {
      c.f3d_cloth_set_balls(_live, data, balls.length);
    } finally {
      data.free();
    }
  }

  @override
  void movePoint(ClothPointMove move) {
    final index = move.index;
    final at = move.at;
    c.f3d_cloth_move_point(_live, index, at.x, at.y, at.z);
  }

  @override
  void step(ClothSystemStep request) {
    final settings = request.settings;
    final dt = request.dt;
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
      return ClothFrame(step: _steps, points: out.copy(n * c.clothFloats));
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
