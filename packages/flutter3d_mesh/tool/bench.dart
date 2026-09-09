// ignore_for_file: avoid_print — a command-line benchmark whose whole output is
// stdout; a logging framework would be the wrong tool.

/// What the editable mesh costs, measured through the pipeline a release build
/// uses.
///
///     dart compile exe tool/bench.dart -o /tmp/bench && /tmp/bench
///
/// **Compiled ahead of time, and that is the point of the package being plain
/// Dart.** `dart compile exe` cannot build anything that reaches `dart:ui`, so
/// a benchmark of the engine's geometry used to be possible only because the
/// geometry layer happened to avoid Flutter; here it is a property of the
/// package rather than a coincidence, held by `a flat Dart package resolves
/// without the Flutter SDK`.
///
/// The numbers this prints go in `doc/model-editor.md` §6 with the machine and
/// the date, because a figure without either is a figure nobody can contradict
/// — `ARCHITECTURE.md` §14 says the same about the engine's.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

/// A grid of quads `n` by `n`, which is the shape a subdivided plane has and
/// the cheapest way to a mesh of a stated size.
EditMesh grid(int n) {
  final points = <Vector3>[
    for (var y = 0; y <= n; y++)
      for (var x = 0; x <= n; x++)
        Vector3(x.toDouble() / n - 0.5, 0, y.toDouble() / n - 0.5),
  ];
  final faces = <List<int>>[
    for (var y = 0; y < n; y++)
      for (var x = 0; x < n; x++)
        <int>[
          y * (n + 1) + x,
          y * (n + 1) + x + 1,
          (y + 1) * (n + 1) + x + 1,
          (y + 1) * (n + 1) + x,
        ],
  ];
  return EditMesh.fromFaces(points, faces);
}

void bench(String name, int iterations, void Function() body, {int? items}) {
  body(); // once untimed, so lazy paths are not counted
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
    line += '   (${(perIteration * 1000 / items).toStringAsFixed(1)} ns/face)';
  }
  print(line);
}

void main() {
  print('--- the editable mesh -------------------------------------------');

  // 158 by 158 is 24 964 quads, near enough the 50k triangles the plan asks
  // for; 316 squared is 99 856, which triangulates to just under 200k.
  for (final side in <int>[158, 316]) {
    final faces = side * side;
    print('');
    print('$side x $side grid: $faces quads, ${faces * 2} triangles');

    bench('EditMesh.fromFaces', 5, () => grid(side), items: faces);

    final mesh = grid(side);
    bench('toMeshData', 5, mesh.toMeshData, items: faces);
    bench('signedVolume', 5, () => mesh.signedVolume, items: faces);
    bench('validate', 5, mesh.validate, items: faces);

    // The whole reason a plan is a thing a caller keeps: building it is the
    // conversion, and filling it again is what a drag costs per frame.
    final plan = MeshLayoutPlan();
    bench('MeshLayoutPlan.build', 5, () => plan.build(mesh), items: faces);
    final rows = plan.rows();
    bench(
      'fillVertices (all)',
      5,
      () => plan.fillVertices(mesh, rows),
      items: faces,
    );
    final dragged = <int>[for (var v = 0; v < 40; v++) v];
    bench(
      'fillVerticesOf (40 vertices)',
      50,
      () => plan.fillVerticesOf(mesh, rows, dragged),
    );
  }

  print('');
  print('--- one edit, repeated ------------------------------------------');
  // What the spike's rebuild-per-operation costs on a mesh small enough that a
  // person would notice: a thousand extrusions of a cube's face.
  bench('extrudeFace x1000 (from a cube)', 5, () {
    var mesh = EditMesh.cuboid();
    for (var i = 0; i < 1000; i++) {
      mesh = mesh.extrudeFace(mesh.faceCount - 1, 0.01);
    }
  });
}
