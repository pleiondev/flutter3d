/// Averaging vertex positions toward their neighbours, without hollowing the
/// mesh out.
///
/// **Plain Laplacian smoothing shrinks.** Moving every vertex toward the
/// centroid of its neighbours removes noise, but it also removes curvature —
/// a sphere smoothed this way for enough iterations collapses toward its own
/// centre, because every point on a convex surface has neighbours whose
/// average sits slightly inside it. [preserveVolume] is the HC correction
/// (Vollmer, Mencl & Müller, 1999): each step's own displacement is measured
/// against the *original* surface and partly subtracted back out, blended
/// with how far a vertex's own neighbours moved, so the high-frequency noise
/// a person is trying to remove keeps getting averaged away while the
/// low-frequency shape it sits on mostly holds its ground.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'edit_mesh.dart';
import 'operations.dart';
import 'selection.dart';

/// Moves every selected vertex toward the average of its own neighbours,
/// [iterations] times.
///
/// [lambda] is how far each step moves toward that average — `1.0` jumps
/// straight to it, `0.5` halves the distance each time. [preserveVolume]
/// turns on the HC correction; without it, the plain average is used
/// outright, which is the simpler and the more destructive of the two over
/// more than a handful of iterations.
OpResult smoothVertices(
  EditMesh mesh,
  Selection selection, {
  required int iterations,
  double lambda = 0.5,
  bool preserveVolume = false,
}) {
  if (iterations < 1) {
    return OpResult.refused(
      'smoothVertices needs at least one iteration',
      selection: selection,
    );
  }
  final vertices = selection.convertedTo(mesh, ElementLevel.vertex);
  if (vertices.isEmpty) {
    return OpResult.refused(
      'no vertices are selected to smooth',
      selection: selection,
    );
  }
  final selected = vertices.ids.toSet();

  // Every vertex a selected one's own average could read from — the
  // selection and its one-ring — so a neighbour just outside the selection
  // still pulls correctly on the vertices inside it without itself moving.
  final touched = <int>{...selected};
  for (final v in selected) {
    touched.addAll(_neighborsOf(mesh, v));
  }

  final original = <int, Vector3>{
    for (final v in touched) v: mesh.positionOf(v),
  };
  final positions = Map<int, Vector3>.of(original);

  for (var iter = 0; iter < iterations; iter++) {
    final laplacian = <int, Vector3>{
      for (final v in selected) v: _laplacianStep(mesh, v, positions, lambda),
    };

    if (!preserveVolume) {
      positions.addAll(laplacian);
      continue;
    }

    // Each vertex's own push this step, measured against where it started —
    // not where it was a moment ago, which is what keeps this correction
    // from just undoing the smoothing it is meant to temper.
    final pushed = <int, Vector3>{
      for (final v in selected) v: laplacian[v]! - original[v]!,
    };
    const beta = 0.5;
    for (final v in selected) {
      final neighbors = _neighborsOf(mesh, v);
      final neighborPush = Vector3.zero();
      var counted = 0;
      for (final n in neighbors) {
        final b = pushed[n];
        if (b == null) continue; // outside the selection: no push of its own
        neighborPush.add(b);
        counted++;
      }
      if (counted > 0) neighborPush.scale(1 / counted);
      final correction =
          pushed[v]!.scaled(beta) + neighborPush.scaled(1 - beta);
      positions[v] = laplacian[v]! - correction;
    }
  }

  for (final v in selected) {
    mesh.moveVertex(v, positions[v]!);
  }

  return OpResult.done(
    selection: vertices,
    movedVertices: Int32List.fromList(selected.toList()..sort()),
  );
}

/// [vertex]'s own new position after one plain Laplacian step: [lambda] of
/// the way from [positions]`[vertex]` toward the average of its neighbours
/// in [positions].
Vector3 _laplacianStep(
  EditMesh mesh,
  int vertex,
  Map<int, Vector3> positions,
  double lambda,
) {
  final here = positions[vertex]!;
  final neighbors = _neighborsOf(mesh, vertex);
  if (neighbors.isEmpty) return here;
  final centroid = Vector3.zero();
  for (final n in neighbors) {
    centroid.add(positions[n] ?? mesh.positionOf(n));
  }
  centroid.scale(1 / neighbors.length);
  return here + (centroid - here).scaled(lambda);
}

/// The vertices sharing an edge with [vertex], walked once around its own
/// half-edge fan.
///
/// **One direction only.** Rotating by `nextOf(twinOf(h))` from an outgoing
/// half-edge visits every neighbour of an interior vertex and arrives back
/// at the half-edge it started from, which is how this knows it is done. A
/// boundary vertex — one whose fan runs out partway round because an edge
/// on one side has no twin — stops there and misses the neighbours on the
/// other side; nothing here needs that case yet; a sphere, this file's own
/// test fixture, has no boundary vertices at all to expose it.
List<int> _neighborsOf(EditMesh mesh, int vertex) {
  final neighbors = <int>[];
  final start = mesh.outgoingOf(vertex);
  if (start == EditMesh.none) return neighbors;
  var half = start;
  while (true) {
    neighbors.add(mesh.originOf(mesh.nextOf(half)));
    if (!mesh.hasLiveTwin(half)) break;
    half = mesh.nextOf(mesh.twinOf(half));
    if (half == start) break;
  }
  return neighbors;
}
