/// The whole path an edit takes, once a frame, timed.
///
/// **What `p0-06` and `p0-11` are actually asking.** Every measurement before
/// this one takes a piece: how long a mesh takes to convert, what a history
/// step costs, how fast a ray finds a triangle. None of them answers the
/// question a person dragging a vertex is asking, which is whether the picture
/// keeps up — and that path is edit, convert, upload, draw, every frame, with a
/// garbage collector running in the middle of it.
///
/// So this does exactly that: moves one per cent of the vertices, rebuilds the
/// drawable mesh, uploads it, and lets the frame be drawn. The numbers come out
/// of `OrbitRun`, which is already timing the frames — what is added here is the
/// per-stage breakdown, because "27 ms" is not actionable and "3 ms of edit, 18
/// of convert, 6 of upload" is.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';

/// What one frame of the pipeline cost, in milliseconds.
typedef ChurnCost = ({double edit, double convert, double upload});

/// Moves vertices, rebuilds and re-uploads the mesh a node draws.
final class ChurnRun {
  ChurnRun({required this.device, required this.node, required MeshData from})
    : _positions = Float32List.fromList(from.vertices),
      _source = from,
      _offset = from.layout.floatOffsetOf(VertexLayout.position.name),
      _stride = from.layout.floatsPerVertex;

  final GraphicsDevice device;

  /// The node whose geometry is replaced each step.
  final MeshNode node;

  final MeshData _source;
  final Float32List _positions;
  final int _offset;
  final int _stride;

  /// Seeded, so two runs on two machines move the same vertices.
  final math.Random _random = math.Random(20260909);

  final List<ChurnCost> _costs = <ChurnCost>[];

  /// Moves one per cent of the vertices, rebuilds, uploads, and records what
  /// each stage cost.
  void step() {
    final vertices = _positions.length ~/ _stride;
    final touched = math.max(1, vertices ~/ 100);

    final edit = Stopwatch()..start();
    for (var i = 0; i < touched; i++) {
      // Scattered rather than clustered: the case `p0-05` showed is the
      // expensive one, so the pipeline is measured against it too.
      final vertex = _random.nextInt(vertices);
      _positions[vertex * _stride + _offset + 1] +=
          _random.nextDouble() * 0.02 - 0.01;
    }
    edit.stop();

    final convert = Stopwatch()..start();
    final rebuilt = MeshData(
      layout: _source.layout,
      vertices: Float32List.fromList(_positions),
      indices: _source.indices,
    );
    convert.stop();

    final upload = Stopwatch()..start();
    // `keepSourceData: false`: the CPU copy is rebuilt every frame here, and
    // retaining six hundred of them would measure memory pressure instead.
    // Nothing releases the buffer this replaces: `DeviceMesh` has no dispose
    // and a `GeometryBuffer` is the backend's to free. So six hundred frames
    // allocate six hundred vertex buffers — which is exactly what a modeller
    // re-uploading a mesh per frame does, and if the allocator is what makes
    // that slow, the finding is the point rather than a flaw in the stand.
    node.mesh = DeviceMesh.upload(device, rebuilt, keepSourceData: false);
    upload.stop();

    _costs.add((
      edit: edit.elapsedMicroseconds / 1000.0,
      convert: convert.elapsedMicroseconds / 1000.0,
      upload: upload.elapsedMicroseconds / 1000.0,
    ));
  }

  /// The average of each stage, with the first ten frames left out for the
  /// reason `OrbitRun` leaves them out: they carry the first allocation of
  /// everything.
  String describe() {
    final costs = _costs.length > 10 ? _costs.sublist(10) : _costs;
    if (costs.isEmpty) return 'churn: nothing ran';
    double mean(double Function(ChurnCost) of) =>
        costs.map(of).reduce((double a, double b) => a + b) / costs.length;
    double worst(double Function(ChurnCost) of) =>
        costs.map(of).reduce(math.max);
    return 'churn: ${costs.length} frames, one per cent of the vertices moved\n'
        '  edit    mean ${mean((ChurnCost c) => c.edit).toStringAsFixed(2)} ms'
        '  worst ${worst((ChurnCost c) => c.edit).toStringAsFixed(2)} ms\n'
        '  convert mean ${mean((ChurnCost c) => c.convert).toStringAsFixed(2)} ms'
        '  worst ${worst((ChurnCost c) => c.convert).toStringAsFixed(2)} ms\n'
        '  upload  mean ${mean((ChurnCost c) => c.upload).toStringAsFixed(2)} ms'
        '  worst ${worst((ChurnCost c) => c.upload).toStringAsFixed(2)} ms';
  }
}
