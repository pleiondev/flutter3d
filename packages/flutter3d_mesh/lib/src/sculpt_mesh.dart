/// A vertex-and-triangle mesh laid out for sculpting: chunked, copy-on-write,
/// with the adjacency and spatial index a brush needs already built.
///
/// **Why not `EditMesh`.** Half-edge topology answers "what is next to what"
/// exactly, which is what editing a boundary needs and a brush does not — a
/// stroke asks "which vertices are near this point" and "move each of them a
/// little," and every write an `EditMesh` records goes through a journal built
/// for undo, not for a few thousand small writes a frame. `pro-sc-01`'s
/// benchmark measured what that costs: a flat, non-chunked vertex layout, over
/// a mesh with a comparable vertex count, forces a GPU upload spanning the
/// whole touched scanline range even when a brush's footprint is small,
/// because "dirty" was tracked as one contiguous range rather than per region.
///
/// **One chunk type, not two.** `mesh-10` looked at chunked, copy-on-write
/// persistent vectors for undo and rejected them by measurement — a scattered
/// edit touches nearly every chunk, so a step costs 92-100% of a full copy,
/// and `journal.dart`'s `JournalledFloats`/`JournalledInts` replaced them with
/// a diff-based journal instead. That means there is no existing chunked CoW
/// structure in this package to reuse: `mesh-10`'s array is journalled, not
/// chunked. `SculptMesh` is the first one, built for the access pattern a
/// brush actually has — a stroke touches a compact neighbourhood of vertices,
/// not a scatter, so the chunk-per-1024-vertices split this file makes stays
/// small in practice (see the acceptance test in `sculpt_mesh_test.dart`).
///
/// **Copy-on-write, chunk by chunk.** Vertices are grouped into fixed chunks
/// of [chunkSize]. A chunk untouched by an edit keeps the exact typed-array
/// object it had — so a snapshot taken before a stroke ([snapshotChunks]) and
/// compared after it shares every chunk the stroke did not reach, and the
/// touched ones are new objects the old snapshot never sees. There is no
/// structural sharing below the chunk: touching one vertex clones the whole
/// 1024-vertex chunk, which is the trade this data structure makes deliberately
/// — a chunk is small enough that the clone is cheap and coarse enough that
/// counting touched chunks is a meaningful, testable number.
///
/// **Triangles, flat.** `triangles` is a flat `Uint32List`, three indices per
/// triangle — the same shape `MeshLayoutPlan.indices` and `MeshData.indices`
/// already use, so nothing downstream needs to learn a second index format.
///
/// **CSR adjacency, not a map.** `bind_weights.dart` (`anim-22`) keys a
/// `Map<int, List<int>>` for a one-off per-bone lookup that is never on a hot
/// path. A brush's neighbour expansion runs every stroke over however many
/// vertices the radius covers, so adjacency here is a compressed-sparse-row
/// pair — `adjacencyOffsets` and `adjacencyNeighbors` — built once in
/// [fromEditMesh] or the raw constructor and read with two array indexings
/// per vertex, no hashing.
///
/// **A uniform grid, not a tree.** The plan calls for "сетка по вершинам" —
/// a grid, not a BVH — because [verticesWithinRadius] is allowed to be
/// brute-force *within* a cell; the grid's only job is keeping that brute
/// force local to a handful of cells around the query point rather than every
/// vertex in the mesh.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'edit_mesh.dart';
import 'triangulate.dart';

/// One chunk's worth of vertex data: positions and UVs for up to
/// [SculptMesh.chunkSize] vertices.
///
/// Immutable once handed out. [SculptMesh] never writes into a
/// `_VertexChunk`'s arrays in place — an edit makes a new one and replaces the
/// slot in [SculptMesh]'s chunk list, which is the whole of the copy-on-write
/// mechanism: whoever is still holding the old `_VertexChunk` (a snapshot, a
/// GPU-upload buffer mid-flight) keeps seeing the values it had.
final class _VertexChunk {
  _VertexChunk(this.positions, this.uvs, this.version);

  /// Three floats per vertex slot in the chunk.
  final Float32List positions;

  /// Two floats per vertex slot in the chunk.
  final Float32List uvs;

  /// Bumped every time this chunk is replaced by an edited copy. Not read for
  /// correctness anywhere in this file — [SculptMesh] compares object
  /// identity to know what changed — but it is what a caller checking "is my
  /// cached copy of chunk N stale" compares against, cheaper than diffing the
  /// arrays.
  final int version;

  _VertexChunk copy() =>
      _VertexChunk(Float32List.fromList(positions), Float32List.fromList(uvs), version + 1);
}

/// What a brush stroke touched: which vertices moved and which chunks had to
/// be copied to record it.
final class BrushResult {
  const BrushResult({required this.touchedVertices, required this.touchedChunks});

  /// Every vertex the stroke's radius reached, in the order the spatial grid
  /// visited them.
  final List<int> touchedVertices;

  /// Every chunk index that had to be copied because at least one of its
  /// vertices moved. Sorted and de-duplicated.
  final List<int> touchedChunks;
}

/// A chunked, copy-on-write vertex-and-triangle mesh for sculpting.
///
/// See the library doc comment for the shape and the reasoning. The public
/// surface: build one from an [EditMesh] with [SculptMesh.fromEditMesh],
/// sculpt with [applyBrush], and convert back with [toEditMesh] when the
/// document leaves sculpt mode.
final class SculptMesh {
  SculptMesh._(this._chunks, this._vertexCount, this.triangles) {
    _buildAdjacency();
    _buildGrid();
  }

  /// Vertices per chunk. Fixed by the plan (`pro-sc-02`), not configurable —
  /// a brush's chunk-touch fraction is only a meaningful, comparable number
  /// across strokes and meshes if the chunk size does not move under it.
  static const int chunkSize = 1024;

  final List<_VertexChunk> _chunks;
  final int _vertexCount;

  /// The mesh's index buffer: three vertex indices per triangle, flat — the
  /// same shape `MeshData.indices` and `MeshLayoutPlan.indices` use.
  final Uint32List triangles;

  Int32List _adjacencyOffsets = Int32List(0);
  Int32List _adjacencyNeighbors = Int32List(0);

  // The uniform grid: a cell key to the vertices bucketed in it. A `Map`
  // rather than an array because vertex positions are not bounded to a known
  // integer range, unlike the CSR adjacency above — there is nothing to build
  // a dense CSR *over* until the cells are known, and rebuilding is O(vertex
  // count) either way. `verticesWithinRadius` is what has to avoid hashing
  // per candidate, and it does: it hashes once per cell, not once per vertex.
  final Map<int, List<int>> _grid = <int, List<int>>{};
  double _cellSize = 1;
  double _minX = 0, _minY = 0, _minZ = 0;

  final Set<int> _dirtyChunks = <int>{};

  /// How many vertices the mesh has. The last chunk may be partially filled.
  int get vertexCount => _vertexCount;

  /// How many chunks the vertices are split into: `ceil(vertexCount / chunkSize)`.
  int get chunkCount => _chunks.length;

  /// Three indices per triangle.
  int get triangleCount => triangles.length ~/ 3;

  /// Offsets into [adjacencyNeighbors]: vertex `v`'s neighbours are
  /// `adjacencyNeighbors[adjacencyOffsets[v] .. adjacencyOffsets[v + 1])`.
  /// Length `vertexCount + 1`.
  Int32List get adjacencyOffsets => _adjacencyOffsets;

  /// The flat neighbour array the offsets slice into.
  Int32List get adjacencyNeighbors => _adjacencyNeighbors;

  /// Which chunk holds vertex [vertex].
  static int chunkOf(int vertex) => vertex ~/ chunkSize;

  /// The vertex's position within its own chunk.
  static int _localOf(int vertex) => vertex % chunkSize;

  /// The position of [vertex], written into [out] when one is given.
  Vector3 positionOf(int vertex, [Vector3? out]) {
    final chunk = _chunks[chunkOf(vertex)];
    final at = _localOf(vertex) * 3;
    return (out ?? Vector3.zero())
      ..setValues(chunk.positions[at], chunk.positions[at + 1], chunk.positions[at + 2]);
  }

  /// The texture coordinate of [vertex], written into [out] when one is given.
  Vector2 uvOf(int vertex, [Vector2? out]) {
    final chunk = _chunks[chunkOf(vertex)];
    final at = _localOf(vertex) * 2;
    return (out ?? Vector2.zero())..setValues(chunk.uvs[at], chunk.uvs[at + 1]);
  }

  /// The neighbours of [vertex] from the CSR adjacency, as a fresh list.
  ///
  /// A convenience for callers and tests; a hot loop should index
  /// [adjacencyOffsets] and [adjacencyNeighbors] directly rather than
  /// allocate one of these per vertex.
  List<int> neighborsOf(int vertex) => _adjacencyNeighbors.sublist(
    _adjacencyOffsets[vertex],
    _adjacencyOffsets[vertex + 1],
  );

  /// The raw position array backing chunk [chunkIndex] — the exact object,
  /// not a copy. What a GPU-upload path reads directly, and what a test
  /// compares by identity to see whether a stroke touched this chunk.
  Float32List chunkPositions(int chunkIndex) => _chunks[chunkIndex].positions;

  /// The raw UV array backing chunk [chunkIndex] — [chunkPositions]' own
  /// pair, kept for a caller that reads a sculpted chunk's UVs straight off
  /// the GPU-upload path rather than only its positions.
  Float32List chunkUvs(int chunkIndex) => _chunks[chunkIndex].uvs;

  /// How many times chunk [chunkIndex] has been replaced by an edited copy.
  int chunkVersion(int chunkIndex) => _chunks[chunkIndex].version;

  /// Chunks touched since the mesh was built or [clearDirtyChunks] last ran.
  Set<int> get dirtyChunks => Set<int>.unmodifiable(_dirtyChunks);

  /// Forgets which chunks are dirty, without touching the data. What a
  /// renderer calls once it has uploaded every dirty chunk's rows.
  void clearDirtyChunks() => _dirtyChunks.clear();

  /// A read-only snapshot of the current chunk array — a shallow copy of the
  /// list, so the `_VertexChunk` objects it names are shared with the mesh
  /// until an edit replaces one of them under the mesh's feet. Compare a
  /// snapshot taken before a stroke against [chunkPositions] after it with
  /// `identical` to see exactly which chunks a stroke copied.
  List<Float32List> snapshotChunkPositions() => <Float32List>[
    for (final chunk in _chunks) chunk.positions,
  ];

  // --------------------------------------------------------------- adjacency

  void _buildAdjacency() {
    final neighborSets = List<Set<int>>.generate(_vertexCount, (_) => <int>{});
    void link(int a, int b) {
      neighborSets[a].add(b);
      neighborSets[b].add(a);
    }

    for (var t = 0; t < triangles.length; t += 3) {
      final a = triangles[t];
      final b = triangles[t + 1];
      final c = triangles[t + 2];
      link(a, b);
      link(b, c);
      link(c, a);
    }

    final offsets = Int32List(_vertexCount + 1);
    for (var v = 0; v < _vertexCount; v++) {
      offsets[v + 1] = offsets[v] + neighborSets[v].length;
    }
    final neighbors = Int32List(offsets[_vertexCount]);
    for (var v = 0; v < _vertexCount; v++) {
      var at = offsets[v];
      for (final n in neighborSets[v]) {
        neighbors[at++] = n;
      }
    }
    _adjacencyOffsets = offsets;
    _adjacencyNeighbors = neighbors;
  }

  // -------------------------------------------------------------------- grid

  int _cellKey(int cx, int cy, int cz) {
    // Offset so small negative cell coordinates do not collide with small
    // positive ones once packed; the mesh a document holds is not going to
    // span more than a few million cells across any axis.
    const int bias = 1 << 20;
    return ((cx + bias) & 0x1fffff) |
        (((cy + bias) & 0x1fffff) << 21) |
        (((cz + bias) & 0x1fffff) << 42);
  }

  int _cellOf(double x, double y, double z) => _cellKey(
    ((x - _minX) / _cellSize).floor(),
    ((y - _minY) / _cellSize).floor(),
    ((z - _minZ) / _cellSize).floor(),
  );

  /// Rebuilds the spatial grid from the mesh's current vertex positions.
  ///
  /// Built once by the constructor; call this again after edits have moved
  /// vertices enough that stale buckets would miss them — [applyBrush] does
  /// not call it automatically, because a caller doing many strokes in a row
  /// usually wants to choose when that `O(vertexCount)` pass happens rather
  /// than pay it once per stroke.
  void rebuildSpatialGrid() {
    _grid.clear();
    if (_vertexCount == 0) {
      _cellSize = 1;
      return;
    }

    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
    final p = Vector3.zero();
    for (var v = 0; v < _vertexCount; v++) {
      positionOf(v, p);
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.z < minZ) minZ = p.z;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
      if (p.z > maxZ) maxZ = p.z;
    }
    _minX = minX;
    _minY = minY;
    _minZ = minZ;

    final diagonal = Vector3(maxX - minX, maxY - minY, maxZ - minZ).length;
    // Aim for a handful of vertices per cell on average: a cell sized so the
    // whole bounding box holds roughly one cell per vertex, floored so a flat
    // or tiny mesh does not collapse to a zero-sized cell.
    final perAxis = _vertexCount > 0 ? _cbrt(_vertexCount.toDouble()) : 1.0;
    _cellSize = diagonal > 0 && perAxis > 0 ? diagonal / perAxis : 1.0;
    if (_cellSize <= 0 || _cellSize.isNaN || _cellSize.isInfinite) {
      _cellSize = 1;
    }

    for (var v = 0; v < _vertexCount; v++) {
      positionOf(v, p);
      final key = _cellOf(p.x, p.y, p.z);
      (_grid[key] ??= <int>[]).add(v);
    }
  }

  void _buildGrid() => rebuildSpatialGrid();

  static double _cbrt(double x) =>
      x <= 0 ? 0 : (x > 0 ? _powApprox(x, 1 / 3) : 0);

  static double _powApprox(double x, double exponent) {
    // dart:math's `pow` would do, but this file otherwise avoids the import
    // for one call; a tiny Newton step on `x^3 = value` is exact enough for a
    // cell-size heuristic that only has to be in the right ballpark.
    var guess = x;
    for (var i = 0; i < 24; i++) {
      guess = guess - (guess * guess * guess - x) / (3 * guess * guess);
    }
    return guess;
  }

  /// Every vertex within [radius] of [center], found by checking only the
  /// grid cells [radius] could reach and brute-forcing the distance check
  /// inside each one — the "radius search is brute-force" half of `pro-sc-02`'s
  /// acceptance, made cheap by the grid keeping the brute force local.
  List<int> verticesWithinRadius(Vector3 center, double radius) {
    final found = <int>[];
    if (_vertexCount == 0 || radius < 0) return found;
    final radius2 = radius * radius;
    final span = (radius / _cellSize).ceil() + 1;
    final cx = ((center.x - _minX) / _cellSize).floor();
    final cy = ((center.y - _minY) / _cellSize).floor();
    final cz = ((center.z - _minZ) / _cellSize).floor();
    final p = Vector3.zero();

    for (var dz = -span; dz <= span; dz++) {
      for (var dy = -span; dy <= span; dy++) {
        for (var dx = -span; dx <= span; dx++) {
          final bucket = _grid[_cellKey(cx + dx, cy + dy, cz + dz)];
          if (bucket == null) continue;
          for (final v in bucket) {
            positionOf(v, p);
            if ((p - center).length2 <= radius2) found.add(v);
          }
        }
      }
    }
    return found;
  }

  // ------------------------------------------------------------------ brush

  /// Applies a brush stroke centred at [center] with the given [radius].
  ///
  /// For every vertex the grid finds within [radius], [displace] is called
  /// with the vertex index, its current position and a falloff in `[0, 1]`
  /// (`1` at the centre, `0` at the edge of the radius, linear in between) and
  /// must return the new position. Only the chunks those vertices live in are
  /// copied — see the library doc comment — and the result says exactly which
  /// vertices and chunks were touched, which is what the `≤2%` acceptance test
  /// counts.
  BrushResult applyBrush({
    required Vector3 center,
    required double radius,
    required Vector3 Function(int vertex, Vector3 position, double falloff) displace,
  }) {
    final touchedVertices = verticesWithinRadius(center, radius);
    final touchedChunks = <int>{};
    final copied = <int, _VertexChunk>{};
    final p = Vector3.zero();

    for (final vertex in touchedVertices) {
      final chunkIndex = chunkOf(vertex);
      final chunk = copied[chunkIndex] ??= _chunks[chunkIndex].copy();
      final local = _localOf(vertex) * 3;
      p.setValues(chunk.positions[local], chunk.positions[local + 1], chunk.positions[local + 2]);
      final distance = radius <= 0 ? 0.0 : (p - center).length / radius;
      final falloff = (1 - distance).clamp(0.0, 1.0);
      final next = displace(vertex, p, falloff);
      chunk.positions[local] = next.x;
      chunk.positions[local + 1] = next.y;
      chunk.positions[local + 2] = next.z;
      touchedChunks.add(chunkIndex);
    }

    for (final entry in copied.entries) {
      _chunks[entry.key] = entry.value;
    }
    _dirtyChunks.addAll(touchedChunks);

    final sortedChunks = touchedChunks.toList()..sort();
    return BrushResult(touchedVertices: touchedVertices, touchedChunks: sortedChunks);
  }

  // ------------------------------------------------------------- conversion

  /// Builds a [SculptMesh] from [mesh]'s current, live geometry.
  ///
  /// **Triangulated on the way in.** `EditMesh` allows faces of any valency;
  /// sculpting works on triangles, so every face is cut with the same
  /// [FaceTriangulator] `MeshLayoutPlan` uses. Dead vertices and faces are
  /// skipped and the live ones renumbered densely from zero — a sculpt
  /// session's vertex numbering does not need to match the document's slot
  /// numbers, only [toEditMesh] converting back needs to be consistent with
  /// this mapping, and it is, because it only ever sees a `SculptMesh` this
  /// factory built.
  ///
  /// **Renumbered by Morton (Z-order) code, not by slot order.** `pro-sc-02`'s
  /// own ≤2%-chunks-per-1%-stroke guarantee is a claim about a chunk of
  /// *consecutive indices*, and a document's own vertex slot order carries no
  /// promise about spatial locality — an import, a mirror modifier or a
  /// scrambled undo history can hand this factory vertices in any order at
  /// all. Sorting live vertices by a Morton code over their quantized
  /// position (ten bits per axis — coarse enough to stay inside dart2js's
  /// 32-bit-safe bitwise range, fine enough that two vertices sharing a code
  /// are already closer than any chunk-sized region needs) means a brush's
  /// compact spatial footprint lands in a compact run of new indices, and
  /// therefore in a small number of [chunkSize]-sized chunks, regardless of
  /// what order the input arrived in. `sculpt_mesh_test.dart`'s own
  /// "scrambled" acceptance test is the adversarial case this exists for.
  ///
  /// **One UV per vertex.** `EditMesh` stores UVs per corner, so a seam can
  /// give the same vertex different coordinates in different faces.
  /// `SculptMesh` has no notion of a corner — a brush moves a vertex, not a
  /// face corner — so each vertex takes the UV of whichever corner is reached
  /// first while walking faces; a mesh with UV seams keeps whichever corner
  /// that happens to be, which is a real limitation on a mesh with islands,
  /// and not one a sculpting brush's own geometry ever has cause to hit: a
  /// stroke moves positions, never corner UVs, so there is nothing here for a
  /// seam value to disagree with itself over.
  factory SculptMesh.fromEditMesh(EditMesh mesh) {
    final vertexMap = Int32List(mesh.vertexSlotCount)
      ..fillRange(0, mesh.vertexSlotCount, EditMesh.none);
    final liveVertices = <int>[
      for (var v = 0; v < mesh.vertexSlotCount; v++)
        if (mesh.isVertexAlive(v)) v,
    ];
    var vertexCount = 0;
    for (final v in _sortedByMortonCode(mesh, liveVertices)) {
      vertexMap[v] = vertexCount++;
    }

    final positions = Float32List(vertexCount * 3);
    final uvs = Float32List(vertexCount * 2);
    final uvWritten = List<bool>.filled(vertexCount, false);
    final trianglesOut = <int>[];
    final cutter = FaceTriangulator();
    final loopPositions = <Vector3>[];
    final loopVertices = <int>[];
    final loopHalfEdges = <int>[];
    final position = Vector3.zero();
    final uv = Vector2.zero();

    for (var f = 0; f < mesh.faceSlotCount; f++) {
      if (!mesh.isFaceAlive(f)) continue;
      loopPositions.clear();
      loopVertices.clear();
      loopHalfEdges.clear();
      mesh.forEachHalfEdge(f, (int half) {
        final origin = mesh.originOf(half);
        loopVertices.add(vertexMap[origin]);
        loopHalfEdges.add(half);
        loopPositions.add(mesh.positionOf(origin, position).clone());
      });

      for (var i = 0; i < loopVertices.length; i++) {
        final sculptVertex = loopVertices[i];
        if (uvWritten[sculptVertex]) continue;
        mesh.uvOf(loopHalfEdges[i], uv);
        uvs[sculptVertex * 2] = uv.x;
        uvs[sculptVertex * 2 + 1] = uv.y;
        uvWritten[sculptVertex] = true;
      }

      cutter.triangulate(loopPositions, (int a, int b, int c) {
        trianglesOut
          ..add(loopVertices[a])
          ..add(loopVertices[b])
          ..add(loopVertices[c]);
      });
    }

    for (var v = 0; v < mesh.vertexSlotCount; v++) {
      final sculptVertex = vertexMap[v];
      if (sculptVertex == EditMesh.none) continue;
      mesh.positionOf(v, position);
      positions[sculptVertex * 3] = position.x;
      positions[sculptVertex * 3 + 1] = position.y;
      positions[sculptVertex * 3 + 2] = position.z;
    }

    final chunkCount = vertexCount == 0 ? 0 : (vertexCount / chunkSize).ceil();
    final chunks = <_VertexChunk>[
      for (var c = 0; c < chunkCount; c++)
        _VertexChunk(
          Float32List.sublistView(
            positions,
            c * chunkSize * 3,
            _end(c, chunkCount, vertexCount, positions.length, 3),
          ),
          Float32List.sublistView(
            uvs,
            c * chunkSize * 2,
            _end(c, chunkCount, vertexCount, uvs.length, 2),
          ),
          0,
        ),
    ];

    return SculptMesh._(chunks, vertexCount, Uint32List.fromList(trianglesOut));
  }

  static int _end(int chunk, int chunkCount, int vertexCount, int arrayLength, int perVertex) =>
      chunk == chunkCount - 1 ? arrayLength : (chunk + 1) * chunkSize * perVertex;

  /// [vertices] (slot indices into [mesh]), ordered by the Morton code of
  /// each one's own quantized position — the sort [fromEditMesh]'s own doc
  /// comment names.
  static List<int> _sortedByMortonCode(EditMesh mesh, List<int> vertices) {
    if (vertices.isEmpty) return vertices;

    final position = Vector3.zero();
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
    for (final v in vertices) {
      mesh.positionOf(v, position);
      if (position.x < minX) minX = position.x;
      if (position.y < minY) minY = position.y;
      if (position.z < minZ) minZ = position.z;
      if (position.x > maxX) maxX = position.x;
      if (position.y > maxY) maxY = position.y;
      if (position.z > maxZ) maxZ = position.z;
    }
    final spanX = maxX - minX, spanY = maxY - minY, spanZ = maxZ - minZ;

    int quantize(double value, double min, double span) {
      if (span <= 0) return 0;
      final t = ((value - min) / span).clamp(0.0, 1.0);
      return (t * 1023).round();
    }

    final codes = Int32List(vertices.length);
    for (var i = 0; i < vertices.length; i++) {
      mesh.positionOf(vertices[i], position);
      codes[i] = _mortonCode3(
        quantize(position.x, minX, spanX),
        quantize(position.y, minY, spanY),
        quantize(position.z, minZ, spanZ),
      );
    }
    final order = List<int>.generate(vertices.length, (i) => i)
      ..sort((a, b) => codes[a].compareTo(codes[b]));
    return <int>[for (final i in order) vertices[i]];
  }

  /// Interleaves the ten bits of [x], [y] and [z] (each `0..1023`) into one
  /// thirty-bit Z-order code. Ten bits a side, not the twenty-one a full
  /// 64-bit interleave would allow, because dart2js's bitwise operators are
  /// only exact within the 32-bit signed range — this stays inside it with
  /// room to spare, at a resolution (1024 buckets per axis) far finer than
  /// any chunk-sized region needs to be told apart from its neighbours.
  static int _spreadBits10(int v) {
    v &= 0x3FF;
    v = (v | (v << 16)) & 0x30000FF;
    v = (v | (v << 8)) & 0x300F00F;
    v = (v | (v << 4)) & 0x30C30C3;
    v = (v | (v << 2)) & 0x9249249;
    return v;
  }

  static int _mortonCode3(int x, int y, int z) =>
      _spreadBits10(x) | (_spreadBits10(y) << 1) | (_spreadBits10(z) << 2);

  /// Builds an [EditMesh] with one triangular face per entry of [triangles],
  /// positions and UVs taken from this mesh vertex-for-vertex.
  ///
  /// **Purely triangulated, on purpose.** `SculptMesh` never held anything but
  /// triangles, so there are no original quads or n-gons to hand back — the
  /// document leaving sculpt mode gets exactly the triangles it was sculpted
  /// as, which is what every sculpting tool this one is modelled on does.
  /// What round-trips exactly is what `pro-sc-02`'s acceptance asks for:
  /// positions and UVs, not face valency.
  EditMesh toEditMesh() {
    final builder = EditMeshBuilder();
    final position = Vector3.zero();
    for (var v = 0; v < _vertexCount; v++) {
      positionOf(v, position);
      builder.addVertex(position.clone());
    }
    for (var t = 0; t < triangles.length; t += 3) {
      builder.addFace(<int>[triangles[t], triangles[t + 1], triangles[t + 2]]);
    }
    final mesh = builder.build();
    final uv = Vector2.zero();
    // A step to write the UVs through, like any other edit — and cleared
    // below, the same way an import clears it: this conversion is the
    // document's starting point in sculpt mode, not a step somebody undoes.
    mesh.beginStep();
    for (var f = 0; f < mesh.faceSlotCount; f++) {
      if (!mesh.isFaceAlive(f)) continue;
      mesh.forEachHalfEdge(f, (int half) {
        final vertex = mesh.originOf(half);
        uvOf(vertex, uv);
        mesh.setUv(half, uv.clone());
      });
    }
    mesh.endStep();
    mesh.clearJournal();
    return mesh;
  }
}
