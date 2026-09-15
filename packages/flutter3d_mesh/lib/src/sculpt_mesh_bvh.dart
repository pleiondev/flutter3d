/// `pro-sc-04`'s own row: a `TriangleBvh` over [SculptMesh], refit rather
/// than rebuilt after a stroke.
///
/// **A thin wrapper, not a second tree implementation.** [TriangleBvh]
/// already does the raycast and the refit — `mesh-20`'s own row built it to
/// take positions and indices directly, "the form an editable mesh hands
/// over", which is exactly [SculptMesh.triangles] and a flattened copy of
/// its own chunked positions. What this file adds is that flattening, and
/// keeping [TriangleBvh.positions] — a `final` array [TriangleBvh.refit]
/// reads in place — in step with whichever chunks a stroke actually
/// touched, so a caller never has to know that a `SculptMesh`'s own
/// positions live in per-1024-vertex chunks at all.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

import 'sculpt_mesh.dart';

/// A [TriangleBvh] kept over one [SculptMesh], refit after every stroke
/// instead of rebuilt.
final class SculptMeshBvh {
  SculptMeshBvh._(this._mesh, this._positions, this._bvh);

  /// Builds a tree over [mesh]'s current geometry.
  factory SculptMeshBvh.build(SculptMesh mesh) {
    final positions = _flatten(mesh);
    return SculptMeshBvh._(
      mesh,
      positions,
      TriangleBvh.fromArrays(positions, mesh.triangles),
    );
  }

  final SculptMesh _mesh;

  /// The same array [_bvh] itself holds — writing into it in place, then
  /// calling [TriangleBvh.refit], is the only way to move the tree's own
  /// bounds without rebuilding it; see this file's own doc comment.
  final Float32List _positions;

  final TriangleBvh _bvh;

  /// [mesh]'s own vertex positions, one chunk at a time — [SculptMesh] has
  /// no single flat array of its own, by design (`pro-sc-02`'s own
  /// chunked, copy-on-write layout), so this is the one place that reads
  /// every chunk to build one.
  static Float32List _flatten(SculptMesh mesh) {
    final out = Float32List(mesh.vertexCount * 3);
    for (var chunk = 0; chunk < mesh.chunkCount; chunk++) {
      final source = mesh.chunkPositions(chunk);
      out.setRange(
        chunk * SculptMesh.chunkSize * 3,
        chunk * SculptMesh.chunkSize * 3 + source.length,
        source,
      );
    }
    return out;
  }

  /// Copies [_mesh]'s current positions back into the tree's own array and
  /// recomputes every node's bounds from them — [TriangleBvh.refit]'s own
  /// "walks the nodes once" rather than the sort a full rebuild does.
  ///
  /// Safe to call whether the last stroke touched one chunk or every one of
  /// them: this always re-reads every chunk currently in [_mesh], the same
  /// way [SculptMeshBvh.build] does the first time, so a caller does not
  /// have to name which chunks changed for the result to be correct — only
  /// [TriangleBvh.refit] itself is what makes this a refit and not a
  /// rebuild.
  void refit() {
    for (var chunk = 0; chunk < _mesh.chunkCount; chunk++) {
      final source = _mesh.chunkPositions(chunk);
      _positions.setRange(
        chunk * SculptMesh.chunkSize * 3,
        chunk * SculptMesh.chunkSize * 3 + source.length,
        source,
      );
    }
    _bvh.refit();
  }

  /// The nearest triangle [ray] hits, or null — the same shape
  /// [TriangleBvh.raycast] itself answers with.
  ({int triangle, double distance, Vector3 point})? raycast(
    Ray ray, {
    double maxDistance = double.infinity,
  }) => _bvh.raycast(ray, maxDistance: maxDistance);
}
