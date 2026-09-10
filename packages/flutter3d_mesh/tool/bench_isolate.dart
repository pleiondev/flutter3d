// ignore_for_file: avoid_print — a command-line benchmark whose whole output is
// stdout.

/// Where a long mesh operation should run, measured three ways.
///
///     dart compile exe tool/bench_isolate.dart -o /tmp/bench && /tmp/bench
///
/// **The question `p0-07` asks.** Turning a mesh into what a GPU draws takes
/// tens of milliseconds at the sizes a modeller opens, which is several frames.
/// There are three places to put that work, and only one of them exists on
/// every platform:
///
///   * **On the calling isolate, in one go.** Simple, and the viewport freezes
///     for the whole of it.
///   * **On a background isolate.** No freeze — and the mesh has to cross,
///     which costs a copy unless it is sent as `TransferableTypedData`. The web
///     has no isolates at all, so this path needs a fallback there anyway.
///   * **In chunks, yielding between them.** Works everywhere, keeps the frame
///     alive, and costs whatever the yielding costs.
///
/// The plan's thresholds: an isolate is worth it if the overhead is at or under
/// 20 % or 50 ms; chunking is the first-day answer if its worst chunk is at or
/// under 50 ms and the total is within 25 % of the straight-through run.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

/// A lattice of `side * side` quads, which is the mesh every figure below is
/// taken over.
EditMesh grid(int side) {
  final points = <Vector3>[
    for (var y = 0; y <= side; y++)
      for (var x = 0; x <= side; x++)
        Vector3(x.toDouble() / side - 0.5, 0, y.toDouble() / side - 0.5),
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
  return EditMesh.fromFaces(points, faces);
}

/// Builds the mesh and converts it, returning the bytes a caller would keep.
///
/// A top-level function taking plain values, because that is what `Isolate.run`
/// can carry: a closure over an `EditMesh` would be the same work plus a copy
/// of the mesh in both directions.
(Float32List, Uint32List) buildAndConvert(int side) {
  final mesh = grid(side).toMeshData();
  return (mesh.vertices, Uint32List.fromList(mesh.indices));
}

/// The same work, handed back through `TransferableTypedData` — which moves the
/// buffer instead of copying it.
TransferableTypedData buildAndTransfer(int side) {
  final (vertices, indices) = buildAndConvert(side);
  return TransferableTypedData.fromList(<TypedData>[vertices, indices]);
}

/// Work that changes nothing, so what the round trip below measures is the
/// crossing rather than an operation.
EditMesh countTheFaces(EditMesh mesh) => mesh;

Future<double> milliseconds(int runs, Future<void> Function() body) async {
  await body();
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    await body();
  }
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds / runs / 1000.0;
}

/// Runs [work] over [steps] pieces, yielding to the event loop between them,
/// and reports the total and the worst piece.
Future<({double totalMs, double worstMs})> inChunks(
  int steps,
  void Function(int step) work,
) async {
  var worst = 0.0;
  final total = Stopwatch()..start();
  for (var step = 0; step < steps; step++) {
    final piece = Stopwatch()..start();
    work(step);
    piece.stop();
    final ms = piece.elapsedMicroseconds / 1000.0;
    if (ms > worst) worst = ms;
    // A real yield: `Future.delayed(Duration.zero)` goes through the event
    // loop, which is what lets a frame be drawn between the pieces.
    await Future<void>.delayed(Duration.zero);
  }
  total.stop();
  return (totalMs: total.elapsedMicroseconds / 1000.0, worstMs: worst);
}

void main() async {
  // 316² quads is 99 856 faces — just under 200 000 triangles, which is the
  // size every threshold in the plan is written against.
  const side = 316;
  final faces = side * side;
  print('a $side x $side lattice: $faces quads, ${faces * 2} triangles');
  print('');

  final onCaller = await milliseconds(3, () async {
    buildAndConvert(side);
  });
  print('on the calling isolate      ${onCaller.toStringAsFixed(1)} ms');

  final byIsolate = await milliseconds(3, () async {
    await Isolate.run(() => buildAndConvert(side));
  });
  print(
    'through Isolate.run         ${byIsolate.toStringAsFixed(1)} ms'
    '   (+${(byIsolate - onCaller).toStringAsFixed(1)} ms, '
    '${((byIsolate / onCaller - 1) * 100).toStringAsFixed(0)} %)',
  );

  final byTransfer = await milliseconds(3, () async {
    final sent = await Isolate.run(() => buildAndTransfer(side));
    sent.materialize();
  });
  print(
    'with TransferableTypedData  ${byTransfer.toStringAsFixed(1)} ms'
    '   (+${(byTransfer - onCaller).toStringAsFixed(1)} ms, '
    '${((byTransfer / onCaller - 1) * 100).toStringAsFixed(0)} %)',
  );

  // What `mesh-30` asks: the cost of an *existing* mesh crossing and coming
  // back, which is the shape an operation run elsewhere has. The two halves
  // are worth apart — writing and reading the bytes is arithmetic, and the
  // handover itself is what `TransferableTypedData` makes nearly free.
  final standing = grid(side);
  final written = await milliseconds(3, () async {
    standing.toBytes();
  });
  print('');
  print('EditMesh.toBytes            ${written.toStringAsFixed(1)} ms');

  final bytes = standing.toBytes();
  final read = await milliseconds(3, () async {
    EditMesh.fromBytes(bytes);
  });
  print('EditMesh.fromBytes         ${read.toStringAsFixed(1)} ms');

  final roundTrip = await milliseconds(3, () async {
    await editInIsolate(standing, countTheFaces);
  });
  print(
    'a mesh there and back      ${roundTrip.toStringAsFixed(1)} ms'
    '   (${(roundTrip - written * 2 - read * 2).toStringAsFixed(1)} ms of it '
    'the handover)',
  );
  print('');

  // Chunked: the mesh is built once, and the conversion is done a band of rows
  // at a time — which is the shape an operation takes when it is made
  // interruptible, one region of the mesh per piece.
  final mesh = grid(side);
  for (final steps in <int>[8, 32]) {
    final report = await inChunks(steps, (int step) {
      // A band of the lattice per step. `toMeshData` has no partial form yet —
      // that is `mesh-14`'s `fillVertices` — so the piece measured here is the
      // per-face work an operation does, scaled to a band.
      final from = step * mesh.faceCount ~/ steps;
      final to = (step + 1) * mesh.faceCount ~/ steps;
      for (var face = from; face < to; face++) {
        mesh.normalOf(face);
        mesh.areaOf(face);
      }
    });
    print(
      'in $steps chunks, yielding      '
      '${report.totalMs.toStringAsFixed(1)} ms'
      '   worst chunk ${report.worstMs.toStringAsFixed(1)} ms',
    );
  }
}
