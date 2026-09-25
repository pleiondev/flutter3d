import 'dart:math' as math;
import 'dart:typed_data';

/// The smallest normal single-precision float, which is what MikkTSpace means
/// by "not zero": its arithmetic is in `float`, and this keeps the same
/// verdicts on the same degenerate triangles.
const double _floatMin = 1.17549435e-38;

bool _notZero(double x) => x.abs() > _floatMin;

/// Tangent frames per triangle corner, computed the way MikkTSpace computes
/// them, for a triangle list given as [indices] into interleaved [vertices].
///
/// **Why MikkTSpace and not a simpler average.** A normal map baked by
/// Blender, Substance, xNormal or Marmoset encodes its texels relative to
/// the frame this algorithm produces, and glTF asks a loader that is given
/// no TANGENT to produce the same one. A frame that is only close bakes a
/// faint gradient into every low-poly surface, and one that averages across
/// a mirrored UV seam cancels there and creases. The steps below are the
/// reference implementation's, in its order:
///
/// 1. Corners are welded by value — position, normal and texture coordinate
///    all equal — not by the index list the mesh came with, so two copies of
///    one vertex get one frame and one vertex shared across a seam can get
///    two.
/// 2. Each triangle's tangent and bitangent directions are normalised on
///    their own, and the triangle remembers whether its texture mapping keeps
///    or reverses orientation.
/// 3. Around each vertex, the triangles joined by shared edges and agreeing
///    in orientation form a group. A triangle with no usable mapping joins
///    whichever group reaches it first and takes that group's orientation.
/// 4. Each group's frame is the triangles' directions projected into the
///    vertex's tangent plane, normalised, and weighted by the angle each
///    triangle has at the vertex.
/// 5. A triangle with two corners in the same place has no area to speak
///    of, and its corners borrow the frame of another corner at the same vertex.
///
/// Quads are not handled — the engine's meshes are triangle lists — and the
/// fallback for a corner no group reaches is the reference's own, +X.
///
/// Returns four floats per entry of [indices]: the unit tangent and glTF's
/// bitangent sign. **The sign is glTF's, which is MikkTSpace's negated**:
/// the reference defines orientation with V growing upwards, and glTF's
/// texture V grows downwards, which is why every glTF tool that runs it
/// negates the w it returns.
Float64List mikkTSpaceCorners({
  required Float32List vertices,
  required int stride,
  required int positionOffset,
  required int normalOffset,
  required int texcoordOffset,
  required Uint32List indices,
}) {
  final triangleCount = indices.length ~/ 3;
  final vertexCount = vertices.length ~/ stride;
  final out = Float64List(triangleCount * 12);
  if (triangleCount == 0) return out;

  final welded = _weld(
    vertices: vertices,
    stride: stride,
    vertexCount: vertexCount,
    positionOffset: positionOffset,
    normalOffset: normalOffset,
    texcoordOffset: texcoordOffset,
  );
  // The triangle list read through the weld: `corner[t * 3 + i]` is a
  // welded vertex, and from here on vertices are only ever those.
  final corner = Int32List(triangleCount * 3);
  for (var c = 0; c < triangleCount * 3; c++) {
    corner[c] = welded[indices[c]];
  }
  double px(int v, int k) => vertices[v * stride + positionOffset + k];
  bool samePlace(int a, int b) =>
      px(a, 0) == px(b, 0) && px(a, 1) == px(b, 1) && px(a, 2) == px(b, 2);

  // Degenerate by position, not by index: two corners in one place leave the
  // triangle no area whatever their normals and UVs say, and the reference
  // takes such a triangle out of the neighbourhoods entirely rather than let
  // it join the faces on either side of it into one group.
  final good = Uint8List(triangleCount);
  for (var t = 0; t < triangleCount; t++) {
    final a = corner[t * 3], b = corner[t * 3 + 1], c = corner[t * 3 + 2];
    good[t] = samePlace(a, b) || samePlace(b, c) || samePlace(a, c) ? 0 : 1;
  }
  double tx(int v, int k) => vertices[v * stride + texcoordOffset + k];

  // Unit normals, one per welded vertex that a corner names. The reference
  // assumes them unit; normalising here costs nothing and spares a file whose
  // normals are not a frame projected onto the wrong plane.
  final normals = Float64List(vertexCount * 3);
  for (var v = 0; v < vertexCount; v++) {
    final base = v * stride + normalOffset;
    final x = vertices[base], y = vertices[base + 1], z = vertices[base + 2];
    final length = math.sqrt(x * x + y * y + z * z);
    final scale = length > 0.0 ? 1.0 / length : 0.0;
    normals[v * 3] = x * scale;
    normals[v * 3 + 1] = y * scale;
    normals[v * 3 + 2] = z * scale;
  }

  // Step 2: each triangle on its own.
  final os = Float64List(triangleCount * 3);
  final ot = Float64List(triangleCount * 3);
  final preserving = Uint8List(triangleCount);
  final withAny = Uint8List(triangleCount);
  for (var t = 0; t < triangleCount; t++) {
    // Assumed unusable until its mapping says otherwise.
    withAny[t] = 1;
    if (good[t] == 0) continue;
    final v1 = corner[t * 3], v2 = corner[t * 3 + 1], v3 = corner[t * 3 + 2];
    final t21x = tx(v2, 0) - tx(v1, 0), t21y = tx(v2, 1) - tx(v1, 1);
    final t31x = tx(v3, 0) - tx(v1, 0), t31y = tx(v3, 1) - tx(v1, 1);
    final d1x = px(v2, 0) - px(v1, 0);
    final d1y = px(v2, 1) - px(v1, 1);
    final d1z = px(v2, 2) - px(v1, 2);
    final d2x = px(v3, 0) - px(v1, 0);
    final d2y = px(v3, 1) - px(v1, 1);
    final d2z = px(v3, 2) - px(v1, 2);
    final signedArea = t21x * t31y - t21y * t31x;
    final osx = t31y * d1x - t21y * d2x;
    final osy = t31y * d1y - t21y * d2y;
    final osz = t31y * d1z - t21y * d2z;
    final otx = -t31x * d1x + t21x * d2x;
    final oty = -t31x * d1y + t21x * d2y;
    final otz = -t31x * d1z + t21x * d2z;
    preserving[t] = signedArea > 0.0 ? 1 : 0;
    if (!_notZero(signedArea)) continue;
    final area = signedArea.abs();
    final lengthS = math.sqrt(osx * osx + osy * osy + osz * osz);
    final lengthT = math.sqrt(otx * otx + oty * oty + otz * otz);
    // Scaled by the orientation, so the stored direction is the true dP/du
    // rather than the numerator of it.
    final s = preserving[t] == 1 ? 1.0 : -1.0;
    if (_notZero(lengthS)) {
      os[t * 3] = osx * s / lengthS;
      os[t * 3 + 1] = osy * s / lengthS;
      os[t * 3 + 2] = osz * s / lengthS;
    }
    if (_notZero(lengthT)) {
      ot[t * 3] = otx * s / lengthT;
      ot[t * 3 + 1] = oty * s / lengthT;
      ot[t * 3 + 2] = otz * s / lengthT;
    }
    if (_notZero(lengthS / area) && _notZero(lengthT / area)) withAny[t] = 0;
  }

  final neighbours = _neighbours(corner, good, vertexCount);

  // Step 3: groups, one per vertex and connected run of like-oriented
  // triangles around it. A group's triangles sit together in `members`,
  // which is how the reference lays them out too.
  final groupOf = Int32List(triangleCount * 3)
    ..fillRange(0, triangleCount * 3, -1);
  final members = Int32List(triangleCount * 3);
  final groupStart = <int>[];
  final groupCount = <int>[];
  final groupVertex = <int>[];
  final groupPreserving = <bool>[];
  var memberCount = 0;
  final stack = <int>[];

  int cornerAt(int t, int vertex) => corner[t * 3] == vertex
      ? 0
      : corner[t * 3 + 1] == vertex
      ? 1
      : 2;

  for (var t = 0; t < triangleCount; t++) {
    if (good[t] == 0 || withAny[t] == 1) continue;
    for (var i = 0; i < 3; i++) {
      if (groupOf[t * 3 + i] != -1) continue;
      final g = groupStart.length;
      final vertex = corner[t * 3 + i];
      final orientation = preserving[t] == 1;
      groupStart.add(memberCount);
      groupCount.add(0);
      groupVertex.add(vertex);
      groupPreserving.add(orientation);
      groupOf[t * 3 + i] = g;
      members[memberCount++] = t;
      groupCount[g]++;
      // The reference recurses into the left neighbour and then the right;
      // a stack popped in that order visits the triangles in the same order,
      // which matters exactly once — the orientation an unusable triangle
      // takes is the first group's to reach it.
      stack
        ..add(neighbours[t * 3 + (i + 2) % 3])
        ..add(neighbours[t * 3 + i]);
      while (stack.isNotEmpty) {
        final f = stack.removeLast();
        if (f < 0) continue;
        final at = cornerAt(f, vertex);
        if (groupOf[f * 3 + at] != -1) continue;
        if (withAny[f] == 1 &&
            groupOf[f * 3] == -1 &&
            groupOf[f * 3 + 1] == -1 &&
            groupOf[f * 3 + 2] == -1) {
          preserving[f] = orientation ? 1 : 0;
        }
        if ((preserving[f] == 1) != orientation) continue;
        groupOf[f * 3 + at] = g;
        members[memberCount++] = f;
        groupCount[g]++;
        stack
          ..add(neighbours[f * 3 + (at + 2) % 3])
          ..add(neighbours[f * 3 + at]);
      }
    }
  }

  // The reference's default for a corner no group reached: +X, and the
  // orientation flag clear — which is glTF's +1 once negated.
  for (var c = 0; c < triangleCount * 3; c++) {
    out[c * 4] = 1.0;
    out[c * 4 + 3] = 1.0;
  }

  // Step 4: the frame of each group, split further only where two of its
  // triangles point exactly opposite ways, which is what the reference's
  // default threshold of 180 degrees leaves of its sub-groups.
  for (var g = 0; g < groupStart.length; g++) {
    final start = groupStart[g];
    final count = groupCount[g];
    final vertex = groupVertex[g];
    final nx = normals[vertex * 3];
    final ny = normals[vertex * 3 + 1];
    final nz = normals[vertex * 3 + 2];
    final projectedS = Float64List(count * 3);
    final projectedT = Float64List(count * 3);
    for (var m = 0; m < count; m++) {
      final t = members[start + m];
      _projectInto(os, t, nx, ny, nz, projectedS, m);
      _projectInto(ot, t, nx, ny, nz, projectedT, m);
    }

    final subGroups = <List<int>>[];
    final subFrames = <Float64List>[];
    for (var m = 0; m < count; m++) {
      final f = members[start + m];
      final joined = <int>[
        for (var j = 0; j < count; j++)
          if (withAny[f] == 1 ||
              withAny[members[start + j]] == 1 ||
              j == m ||
              (_dot(projectedS, m, j) > -1.0 && _dot(projectedT, m, j) > -1.0))
            members[start + j],
      ]..sort();
      var found = -1;
      for (var s = 0; s < subGroups.length && found < 0; s++) {
        if (_sameList(subGroups[s], joined)) found = s;
      }
      if (found < 0) {
        found = subGroups.length;
        subGroups.add(joined);
        subFrames.add(
          _evaluate(
            joined,
            vertex,
            corner: corner,
            withAny: withAny,
            os: os,
            nx: nx,
            ny: ny,
            nz: nz,
            position: px,
          ),
        );
      }
      final frame = subFrames[found];
      final c = f * 3 + cornerAt(f, vertex);
      out[c * 4] = frame[0];
      out[c * 4 + 1] = frame[1];
      out[c * 4 + 2] = frame[2];
      out[c * 4 + 3] = groupPreserving[g] ? -1.0 : 1.0;
    }
  }

  // Step 5: a degenerate triangle's corners borrow from the first good
  // corner at the same welded vertex, as the reference's epilogue does.
  final firstGood = Int32List(vertexCount)..fillRange(0, vertexCount, -1);
  for (var t = 0; t < triangleCount; t++) {
    if (good[t] == 0) continue;
    for (var i = 0; i < 3; i++) {
      final v = corner[t * 3 + i];
      if (firstGood[v] == -1) firstGood[v] = t * 3 + i;
    }
  }
  for (var t = 0; t < triangleCount; t++) {
    if (good[t] == 1) continue;
    for (var i = 0; i < 3; i++) {
      final source = firstGood[corner[t * 3 + i]];
      if (source < 0) continue;
      for (var k = 0; k < 4; k++) {
        out[(t * 3 + i) * 4 + k] = out[source * 4 + k];
      }
    }
  }
  return out;
}

/// [vectors]' triangle [t], projected into the plane of `n`, normalised, and
/// written at slot [m] of [into].
void _projectInto(
  Float64List vectors,
  int t,
  double nx,
  double ny,
  double nz,
  List<double> into,
  int m,
) {
  final x = vectors[t * 3], y = vectors[t * 3 + 1], z = vectors[t * 3 + 2];
  final along = nx * x + ny * y + nz * z;
  final px = x - along * nx, py = y - along * ny, pz = z - along * nz;
  final length = math.sqrt(px * px + py * py + pz * pz);
  final usable = _notZero(px) || _notZero(py) || _notZero(pz);
  final scale = usable && length > 0.0 ? 1.0 / length : 1.0;
  into[m * 3] = px * scale;
  into[m * 3 + 1] = py * scale;
  into[m * 3 + 2] = pz * scale;
}

double _dot(List<double> v, int a, int b) =>
    v[a * 3] * v[b * 3] +
    v[a * 3 + 1] * v[b * 3 + 1] +
    v[a * 3 + 2] * v[b * 3 + 2];

bool _sameList(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The frame at [vertex] of the triangles in [faces]: each one's tangent
/// direction projected into the vertex's plane, normalised, and weighted by
/// the angle the triangle makes there — so a vertex's frame does not depend
/// on how finely the faces around it happen to be cut.
Float64List _evaluate(
  List<int> faces,
  int vertex, {
  required Int32List corner,
  required Uint8List withAny,
  required Float64List os,
  required double nx,
  required double ny,
  required double nz,
  required double Function(int vertex, int axis) position,
}) {
  var sx = 0.0, sy = 0.0, sz = 0.0;
  final projected = List<double>.filled(3, 0.0);
  for (final f in faces) {
    if (withAny[f] == 1) continue;
    final i = corner[f * 3] == vertex
        ? 0
        : corner[f * 3 + 1] == vertex
        ? 1
        : 2;
    _projectInto(os, f, nx, ny, nz, projected, 0);
    final previous = corner[f * 3 + (i + 2) % 3];
    final next = corner[f * 3 + (i + 1) % 3];
    final e1 = _projectedEdge(position, vertex, previous, nx, ny, nz);
    final e2 = _projectedEdge(position, vertex, next, nx, ny, nz);
    final cos = (e1.$1 * e2.$1 + e1.$2 * e2.$2 + e1.$3 * e2.$3).clamp(
      -1.0,
      1.0,
    );
    final angle = math.acos(cos);
    sx += angle * projected[0];
    sy += angle * projected[1];
    sz += angle * projected[2];
  }
  final length = math.sqrt(sx * sx + sy * sy + sz * sz);
  final usable = _notZero(sx) || _notZero(sy) || _notZero(sz);
  final scale = usable && length > 0.0 ? 1.0 / length : 1.0;
  return Float64List.fromList(<double>[sx * scale, sy * scale, sz * scale]);
}

/// The edge from [from] to [to], projected into the plane of `n` and
/// normalised when it is not zero.
(double, double, double) _projectedEdge(
  double Function(int vertex, int axis) position,
  int from,
  int to,
  double nx,
  double ny,
  double nz,
) {
  final x = position(to, 0) - position(from, 0);
  final y = position(to, 1) - position(from, 1);
  final z = position(to, 2) - position(from, 2);
  final along = nx * x + ny * y + nz * z;
  final px = x - along * nx, py = y - along * ny, pz = z - along * nz;
  final length = math.sqrt(px * px + py * py + pz * pz);
  final usable = _notZero(px) || _notZero(py) || _notZero(pz);
  final scale = usable && length > 0.0 ? 1.0 / length : 1.0;
  return (px * scale, py * scale, pz * scale);
}

/// For each vertex, the first vertex with the same position, normal and
/// texture coordinate — MikkTSpace's own weld, which compares values and
/// ignores whatever index list the mesh arrived with.
Int32List _weld({
  required Float32List vertices,
  required int stride,
  required int vertexCount,
  required int positionOffset,
  required int normalOffset,
  required int texcoordOffset,
}) {
  final welded = Int32List(vertexCount);
  final offsets = <int>[
    positionOffset,
    positionOffset + 1,
    positionOffset + 2,
    normalOffset,
    normalOffset + 1,
    normalOffset + 2,
    texcoordOffset,
    texcoordOffset + 1,
  ];
  bool same(int a, int b) {
    for (final k in offsets) {
      if (vertices[a * stride + k] != vertices[b * stride + k]) return false;
    }
    return true;
  }

  // Chained buckets keyed on a hash of the eight values. `+ 0.0` folds
  // negative zero into zero, which the comparison above already equates.
  final heads = <int, int>{};
  final next = Int32List(vertexCount)..fillRange(0, vertexCount, -1);
  for (var v = 0; v < vertexCount; v++) {
    final hash = Object.hashAll(<double>[
      for (final k in offsets) vertices[v * stride + k] + 0.0,
    ]);
    var candidate = heads[hash] ?? -1;
    var match = -1;
    while (candidate >= 0 && match < 0) {
      if (same(candidate, v)) match = candidate;
      candidate = next[candidate];
    }
    if (match >= 0) {
      welded[v] = match;
    } else {
      welded[v] = v;
      next[v] = heads[hash] ?? -1;
      heads[hash] = v;
    }
  }
  return welded;
}

/// The triangle across each edge of each good triangle, or -1: edge `i` of
/// triangle `t` runs from its corner `i` to corner `i + 1`, and its neighbour
/// is a triangle running the same two welded vertices the other way.
///
/// Where more than one could, the earliest unpaired one is taken, which is
/// the reference's pairing after it sorts the edges by vertex and then by
/// triangle. Bucketed by the smaller vertex rather than sorted, so it stays
/// linear in the mesh.
Int32List _neighbours(Int32List corner, Uint8List good, int vertexCount) {
  final triangleCount = good.length;
  final neighbours = Int32List(triangleCount * 3)
    ..fillRange(0, triangleCount * 3, -1);
  final bucketStart = Int32List(vertexCount + 1);
  for (var t = 0; t < triangleCount; t++) {
    if (good[t] == 0) continue;
    for (var i = 0; i < 3; i++) {
      bucketStart[math.min(corner[t * 3 + i], corner[t * 3 + (i + 1) % 3]) +
          1]++;
    }
  }
  for (var v = 0; v < vertexCount; v++) {
    bucketStart[v + 1] += bucketStart[v];
  }
  final fill = Int32List.fromList(bucketStart);
  final edges = Int32List(bucketStart[vertexCount]);
  for (var t = 0; t < triangleCount; t++) {
    if (good[t] == 0) continue;
    for (var i = 0; i < 3; i++) {
      final low = math.min(corner[t * 3 + i], corner[t * 3 + (i + 1) % 3]);
      edges[fill[low]++] = t * 3 + i;
    }
  }
  for (var v = 0; v < vertexCount; v++) {
    for (var a = bucketStart[v]; a < bucketStart[v + 1]; a++) {
      final edgeA = edges[a];
      if (neighbours[edgeA] != -1) continue;
      final fromA = corner[edgeA];
      final toA = corner[(edgeA ~/ 3) * 3 + (edgeA % 3 + 1) % 3];
      for (var b = a + 1; b < bucketStart[v + 1]; b++) {
        final edgeB = edges[b];
        if (neighbours[edgeB] != -1) continue;
        final fromB = corner[edgeB];
        final toB = corner[(edgeB ~/ 3) * 3 + (edgeB % 3 + 1) % 3];
        if (fromB == toA && toB == fromA) {
          neighbours[edgeA] = edgeB ~/ 3;
          neighbours[edgeB] = edgeA ~/ 3;
          break;
        }
      }
    }
  }
  return neighbours;
}
