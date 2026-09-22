import 'dart:math' as math;
import 'dart:typed_data';

import 'mesh_data.dart';

/// A FIFO post-transform vertex cache's own size on real GPUs, give or take —
/// the number [optimizeVertexCache] scores triangle choices against when the
/// caller does not name one.
const int kDefaultVertexCacheSize = 32;

const double _cacheDecayPower = 1.5;
const double _lastTriangleScore = 0.75;
const double _valenceBoostScale = 2.0;
const double _valenceBoostPower = 0.5;

/// A vertex's desirability as the next one drawn, in Tom Forsyth's "Linear-
/// Speed Vertex Cache Optimisation" (2006) scoring: higher for a vertex a
/// [cacheSize]-entry FIFO cache still holds, and higher again for one with few
/// triangles left to use it, so a fan gets finished before it ages out.
double _vertexScore(int cachePosition, int activeTriangleCount, int cacheSize) {
  if (activeTriangleCount <= 0) return -1.0;
  var score = 0.0;
  if (cachePosition >= 0) {
    score = cachePosition < 3
        ? _lastTriangleScore
        : math
              .pow(
                1.0 - (cachePosition - 3) / (cacheSize - 3),
                _cacheDecayPower,
              )
              .toDouble();
  }
  return score +
      _valenceBoostScale *
          math.pow(activeTriangleCount, -_valenceBoostPower).toDouble();
}

/// [indices] reordered so triangles sharing recently-drawn vertices are drawn
/// near each other, by Forsyth's greedy scoring: each step emits the
/// unemitted triangle whose three vertices score highest, then ages every
/// vertex still in the simulated cache and rescores the triangles that touch
/// it.
///
/// **A reference-quality implementation, not the original's linked-list one.**
/// Forsyth's own writeup keeps the next-best triangle in a priority structure
/// updated only where a step changed something; this rescans every unemitted
/// triangle each step instead, `O(triangleCount²)`. That is a few hundred
/// milliseconds on the thousands of triangles a real test model has and would
/// not scale to a film-quality mesh — a real, honest limitation rather than
/// one hidden by not naming it, and not what [optimizeVertexCache]'s own row
/// needs to be worth having.
Uint32List optimizeTriangleOrder(
  Uint32List indices,
  int vertexCount, {
  int cacheSize = kDefaultVertexCacheSize,
}) {
  final triangleCount = indices.length ~/ 3;
  if (triangleCount == 0) return indices;

  final activeTriangleCount = Int32List(vertexCount);
  for (final v in indices) {
    activeTriangleCount[v]++;
  }

  final vertexScore = Float64List(vertexCount);
  for (var v = 0; v < vertexCount; v++) {
    vertexScore[v] = _vertexScore(-1, activeTriangleCount[v], cacheSize);
  }

  final triangleScore = Float64List(triangleCount);
  final triangleEmitted = Uint8List(triangleCount);
  double scoreOf(int t) =>
      vertexScore[indices[t * 3]] +
      vertexScore[indices[t * 3 + 1]] +
      vertexScore[indices[t * 3 + 2]];
  for (var t = 0; t < triangleCount; t++) {
    triangleScore[t] = scoreOf(t);
  }

  // Vertex -> the triangles touching it, as a CSR table: every time a
  // vertex's score changes, its triangles are the only ones that need
  // rescoring, rather than the whole mesh.
  final adjacencyStart = Int32List(vertexCount + 1);
  for (final v in indices) {
    adjacencyStart[v + 1]++;
  }
  for (var v = 0; v < vertexCount; v++) {
    adjacencyStart[v + 1] += adjacencyStart[v];
  }
  final adjacency = Int32List(indices.length);
  final cursor = Int32List(vertexCount);
  for (var v = 0; v < vertexCount; v++) {
    cursor[v] = adjacencyStart[v];
  }
  for (var t = 0; t < triangleCount; t++) {
    for (var c = 0; c < 3; c++) {
      final v = indices[t * 3 + c];
      adjacency[cursor[v]] = t;
      cursor[v]++;
    }
  }

  final cache = <int>[]; // most recently used first, capped at [cacheSize]
  final output = Uint32List(indices.length);
  var outputCursor = 0;

  for (var step = 0; step < triangleCount; step++) {
    var best = -1;
    var bestScore = -double.infinity;
    for (var t = 0; t < triangleCount; t++) {
      if (triangleEmitted[t] != 0) continue;
      final s = triangleScore[t];
      if (s > bestScore) {
        bestScore = s;
        best = t;
      }
    }

    triangleEmitted[best] = 1;
    final corners = [
      indices[best * 3],
      indices[best * 3 + 1],
      indices[best * 3 + 2],
    ];
    for (final v in corners) {
      output[outputCursor] = v;
      outputCursor++;
    }
    for (final v in corners) {
      activeTriangleCount[v]--;
    }

    for (final v in corners) {
      cache.remove(v);
    }
    for (final v in corners.reversed) {
      cache.insert(0, v);
    }
    // Every vertex this step's insert pushed out of the cache window needs
    // its score reset to "not cached" too — left alone, it would keep the
    // score its old cache position earned forever, and the greedy choice
    // below would keep preferring a vertex that fell out of the cache steps
    // ago over one genuinely still in it.
    final evicted = cache.length > cacheSize
        ? cache.sublist(cacheSize)
        : const <int>[];
    if (evicted.isNotEmpty) {
      cache.removeRange(cacheSize, cache.length);
    }

    final touched = <int>{...corners, ...cache, ...evicted};
    for (final v in touched) {
      final position = cache.indexOf(v);
      vertexScore[v] = _vertexScore(
        position,
        activeTriangleCount[v],
        cacheSize,
      );
    }
    for (final v in touched) {
      for (var i = adjacencyStart[v]; i < adjacencyStart[v + 1]; i++) {
        final t = adjacency[i];
        if (triangleEmitted[t] == 0) triangleScore[t] = scoreOf(t);
      }
    }
  }

  return output;
}

/// [indices] renumbered so a vertex's new index is the order it is first
/// referenced in — the pre-transform ("vertex fetch") half of GPU cache
/// friendliness, meant to run on triangle-cache-ordered indices (
/// [optimizeTriangleOrder]'s output) the way `meshoptimizer`'s
/// `optVertexFetch` follows its own `optVertexCache`. A vertex a GPU fetches
/// right after the one before it in memory is a vertex its prefetcher already
/// has queued; a triangle order optimized for the post-transform cache alone
/// can still reference vertex data scattered across the buffer.
({Uint32List indices, Uint32List oldToNew}) optimizeVertexFetch(
  Uint32List indices,
  int vertexCount,
) {
  const unmapped = 0xFFFFFFFF;
  final oldToNew = Uint32List(vertexCount)..fillRange(0, vertexCount, unmapped);
  final newIndices = Uint32List(indices.length);
  var next = 0;
  for (var i = 0; i < indices.length; i++) {
    final old = indices[i];
    var mapped = oldToNew[old];
    if (mapped == unmapped) {
      mapped = next;
      next++;
      oldToNew[old] = mapped;
    }
    newIndices[i] = mapped;
  }
  // A vertex no triangle references — a shape generator's unused seam
  // duplicate, or an isolated point a decoder produced — never gets a slot
  // above. It keeps the mesh's own vertex count a caller may still be
  // sizing other per-vertex data against (a morph target among them), so it
  // is appended in its original order rather than dropped.
  for (var old = 0; old < oldToNew.length; old++) {
    if (oldToNew[old] == unmapped) {
      oldToNew[old] = next;
      next++;
    }
  }
  return (indices: newIndices, oldToNew: oldToNew);
}

/// [mesh] with its triangles and vertices reordered for GPU cache reuse:
/// [optimizeTriangleOrder] on the index buffer, then [optimizeVertexFetch] to
/// renumber vertices by first use in that new order — the same two-pass
/// scheme real engines and `meshoptimizer` split into, because the two caches
/// they target (post- and pre-transform) are optimized by different orders.
///
/// The same triangles, drawn in the same orientation, described by the same
/// vertex data — nothing here changes what the mesh looks like, only which
/// byte offset a vertex or an index lands at. [MeshData.morphTargets] are
/// carried through the same vertex permutation, so a blend shape still
/// targets the vertex it always did.
///
/// A mesh with no triangles is returned unchanged, since there is nothing to
/// reorder and Forsyth's scoring divides by a vertex's remaining triangle
/// count.
MeshData optimizeVertexCache(
  MeshData mesh, {
  int cacheSize = kDefaultVertexCacheSize,
}) {
  if (mesh.triangleCount == 0) return mesh;

  final cacheOrdered = optimizeTriangleOrder(
    mesh.indices,
    mesh.vertexCount,
    cacheSize: cacheSize,
  );
  final fetch = optimizeVertexFetch(cacheOrdered, mesh.vertexCount);
  final oldToNew = fetch.oldToNew;

  final stride = mesh.layout.floatsPerVertex;
  final vertices = Float32List(mesh.vertices.length);
  for (var oldV = 0; oldV < mesh.vertexCount; oldV++) {
    final newV = oldToNew[oldV];
    final from = oldV * stride;
    final to = newV * stride;
    for (var c = 0; c < stride; c++) {
      vertices[to + c] = mesh.vertices[from + c];
    }
  }

  return MeshData(
    layout: mesh.layout,
    vertices: vertices,
    indices: fetch.indices,
    morphTargets: [
      for (final target in mesh.morphTargets)
        _remapMorphTarget(target, oldToNew),
    ],
  );
}

MorphTarget _remapMorphTarget(MorphTarget target, Uint32List oldToNew) {
  Float32List? remapped(Float32List? source) {
    if (source == null) return null;
    final out = Float32List(source.length);
    for (var oldV = 0; oldV < oldToNew.length; oldV++) {
      final newV = oldToNew[oldV];
      out[newV * 3] = source[oldV * 3];
      out[newV * 3 + 1] = source[oldV * 3 + 1];
      out[newV * 3 + 2] = source[oldV * 3 + 2];
    }
    return out;
  }

  return MorphTarget(
    vertexCount: target.vertexCount,
    positions: remapped(target.positions)!,
    normals: remapped(target.normals),
    tangents: remapped(target.tangents),
    name: target.name,
  );
}

/// Cache misses per triangle simulating a FIFO cache of [cacheSize] entries
/// reading [indices] in order — the standard ACMR metric (Hoppe, "Optimization
/// of Mesh Locality for Transparent Vertex Caching", 1999) for how well a
/// triangle order reuses recently-transformed vertices.
///
/// A closed mesh where each vertex borders about six triangles gets close to
/// `0.5` once well ordered; `3.0` is the worst case, a cache miss on every
/// corner, which is what a triangle order with no locality at all gets.
double averageCacheMissRatio(
  Uint32List indices, {
  int cacheSize = kDefaultVertexCacheSize,
}) {
  final triangleCount = indices.length ~/ 3;
  if (triangleCount == 0) return 0.0;

  final cache = <int>[];
  var misses = 0;
  for (final v in indices) {
    if (cache.contains(v)) continue;
    misses++;
    cache.insert(0, v);
    if (cache.length > cacheSize) cache.removeLast();
  }
  return misses / triangleCount;
}
