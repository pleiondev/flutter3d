// ignore_for_file: avoid_print — a command-line benchmark whose whole output
// is stdout.

/// `anim-31a-n`'s own first number: a weight-paint stroke touching 1% of a
/// 200k-vertex mesh, against a full copy of the same mesh — the ratio
/// `doc-08`'s own acceptance already asks for a generic edit ("шаг после
/// сдвига 1% из 200k <10% полной копии"), measured here for [paintWeights]
/// specifically rather than assumed to inherit it.
///
///     dart compile exe tool/bench/paint_weights_stroke_bench.dart -o /tmp/pwbench && /tmp/pwbench
///
/// Standalone Dart, the same reason every other bench in this repository's
/// plain packages is: `flutter3d_model_core` is in `flatDartPackages`, and
/// `paint_weights.dart` itself reaches nothing that needs the Flutter SDK.
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:vector_math/vector_math.dart';

/// A grid of `(side + 1)²` vertices, flat on Y, rigidly bound to joint 0 of
/// a one-joint skeleton at the origin — bind pose and posed pose coincide,
/// which keeps this a measurement of what [paintWeights] itself costs
/// rather than of a skeleton's own pose arithmetic.
EditMesh weightedGrid(int side) {
  final points = <Vector3>[
    for (var y = 0; y <= side; y++)
      for (var x = 0; x <= side; x++)
        Vector3(x / side - 0.5, 0, y / side - 0.5),
  ];
  final faces = <List<int>>[
    for (var y = 0; y < side; y++)
      for (var x = 0; x < side; x++)
        <int>[
          y * (side + 1) + x,
          y * (side + 1) + x + 1,
          (y + 1) * (side + 1) + x + 1,
          (y + 1) * (side + 1) + x,
        ],
  ];
  final mesh = EditMesh.fromFaces(points, faces);
  mesh.beginStep();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    mesh.setSkin(v, VertexAttributes(joints: Vector4(0, 0, 0, 0), weights: Vector4(1, 0, 0, 0)));
  }
  mesh.endStep();
  return mesh;
}

void bench(String name, int iterations, void Function() body, {int? items}) {
  body();
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  stopwatch.stop();
  final perIteration = stopwatch.elapsedMicroseconds / iterations;
  final label = perIteration >= 1000
      ? '${(perIteration / 1000).toStringAsFixed(2)} ms'
      : '${perIteration.toStringAsFixed(1)} us';
  var line = '${name.padRight(44)} $label';
  if (items != null && items > 0) {
    line += '   (${(perIteration * 1000 / items).toStringAsFixed(2)} ns/vertex)';
  }
  print(line);
}

void main() {
  print('--- weight-paint stroke vs. a full copy, anim-31a-n\'s own first number ---');

  // 447² = 199 809, near enough the row's own "200k". A single sample of
  // radius 0.05 on a grid spanning [-0.5, 0.5] covers a disc of area
  // π×0.05² over the unit square's own area 1 — roughly 0.8% of vertices,
  // near enough the row's own "1 %".
  const side = 447;
  final mesh = weightedGrid(side);
  final vertexCount = mesh.vertexCount;
  print('');
  print('$side x $side grid: $vertexCount vertices');

  final project = ModelProject(
    objects: <ModelObject>[
      ModelObject(id: 1, name: 'root', geometry: const SocketGeometry(), transform: Matrix4.identity()),
      ModelObject(id: 10, name: 'sheet', geometry: EditedGeometry(mesh), transform: Matrix4.identity(), skeletonIndex: 0),
    ],
    skeletons: <ProjectSkeleton>[
      ProjectSkeleton(joints: <int>[1], inverseBindMatrices: <Matrix4>[Matrix4.identity()]),
    ],
  );
  final skeleton = project.skeletons.single;

  final samples = <BrushSample>[BrushSample(center: Vector3.zero(), radius: 0.05)];
  var touched = 0;
  for (var v = 0; v < vertexCount; v++) {
    if (mesh.positionOf(v).length <= 0.05) touched++;
  }
  print('one sample of radius 0.05 touches $touched vertices '
      '(${(100 * touched / vertexCount).toStringAsFixed(2)} % of $vertexCount)');
  print('');

  bench(
    'paintWeights (one stroke, ~1 % of the mesh)',
    5,
    () => paintWeights(
      project: project,
      mesh: mesh,
      skeleton: skeleton,
      joint: 1,
      samples: samples,
      strength: 0.5,
    ),
    items: vertexCount,
  );

  late Uint8List copy;
  bench(
    'EditMesh.toBytes (a full copy, for the ratio)',
    5,
    () => copy = mesh.toBytes(),
    items: vertexCount,
  );
  print('(copy is ${copy.length} bytes, unused beyond forcing the write)');

  print('');
  print(
    'A number with no machine and no date is a number nobody can hold to '
    '(ARCHITECTURE.md §14\'s own rule for the engine\'s benches). Machine '
    'and date go beside this in doc/model-editor-plan.md alongside it.',
  );
}
