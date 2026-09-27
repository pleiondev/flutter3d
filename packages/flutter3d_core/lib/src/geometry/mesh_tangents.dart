import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'mesh_data.dart';
import 'mikktspace.dart';
import 'vertex_layout.dart';

/// How [MeshTangents.withGeneratedTangents] derives a frame from the UVs.
enum TangentMethod {
  /// MikkTSpace, the frame glTF asks for and every common baker assumes.
  ///
  /// The default, because a normal map is only right against the frame it
  /// was baked in, and the maps a loader meets were baked in this one.
  mikkTSpace,

  /// Lengyel's method: each triangle's unnormalised dP/du summed at its
  /// vertices over the mesh's own index list.
  ///
  /// **The fast path, and only that.** One pass and no weld, so it is a few
  /// times quicker, and it never adds a vertex. What it gives up is exactly
  /// what MikkTSpace adds: faces weigh in by UV density rather than by the
  /// angle they make at the vertex, so a map baked elsewhere shows faint
  /// gradients on uneven meshes, and a vertex shared across a mirrored UV
  /// seam averages two opposite frames into nothing and gets a fixed axis.
  /// For a mesh whose maps were made for it, or one redrawn every frame.
  lengyel,
}

/// Tangent generation, split out of [MeshData] because it is a
/// self-contained algorithm that only ever touches [MeshData]'s public
/// surface — an extension keeps it that way rather than granting it access to
/// private state it does not need.
extension MeshTangents on MeshData {
  /// A copy with per-vertex tangents derived from the UV parametrization.
  ///
  /// The `w` component is glTF's bitangent sign, which is what encodes a
  /// mirrored UV island — get it backwards and a normal-mapped surface lights
  /// from the wrong side, which is exactly what `NormalTangentTest` is built
  /// to show. See [TangentMethod] for the two ways the direction is found.
  ///
  /// **A vertex may be split.** MikkTSpace can give one vertex two frames —
  /// where a mirrored UV island meets its original along a shared edge, the
  /// two sides have opposite handedness — and one vertex holds one tangent.
  /// With [splitSeams] such a vertex is copied, once per extra frame, onto
  /// the end of the vertex list and the triangles on the other side point at
  /// the copy, so the mesh can come back longer than it went in; the vertices
  /// it had keep their places. [generateTangents] says which vertex each
  /// copy was made from, for a caller holding data per vertex. Without
  /// [splitSeams] the vertex count is kept and such a vertex takes the frame
  /// most of its corners have; that is for callers whose rows must line up
  /// with something else, like an editor's layout plan.
  ///
  /// Requires normals and texture coordinates. Without UVs there is no tangent
  /// frame to derive, so the neutral tangent is written instead and the caller
  /// gets geometry that at least does not produce NaN.
  MeshData withGeneratedTangents({
    VertexLayout? target,
    TangentMethod method = TangentMethod.mikkTSpace,
    bool splitSeams = true,
  }) => generateTangents(
    target: target,
    method: method,
    splitSeams: splitSeams,
  ).mesh;

  /// [withGeneratedTangents], and for each vertex it appended, the vertex it
  /// copied: `copiedFrom[i]` is the source of vertex `vertexCount + i` of the
  /// input. Empty when nothing was split, which is every mesh without a
  /// mirrored seam and every run of [TangentMethod.lengyel].
  ({MeshData mesh, Uint32List copiedFrom}) generateTangents({
    VertexLayout? target,
    TangentMethod method = TangentMethod.mikkTSpace,
    bool splitSeams = true,
  }) {
    final layoutWithTangents =
        target ??
        (layout.has(VertexLayout.tangent)
            ? layout
            : VertexLayout(<VertexAttribute>[
                ...layout.attributes,
                VertexLayout.tangent,
              ]));
    if (!layoutWithTangents.has(VertexLayout.tangent)) {
      throw ArgumentError(
        'The target layout must declare a tangent attribute, got '
        '$layoutWithTangents.',
      );
    }

    final result = convertedTo(layoutWithTangents);
    final stride = layoutWithTangents.floatsPerVertex;
    final tangentOffset = layoutWithTangents.floatOffsetOf(
      VertexLayout.tangent.name,
    );
    final normalOffset = layoutWithTangents.floatOffsetOf(
      VertexLayout.normal.name,
    );
    final uvOffset = layoutWithTangents.floatOffsetOf(
      VertexLayout.texcoord.name,
    );

    // A mesh copied from itself would be mutated in place, which would surprise
    // a caller holding the original.
    final out = identical(result, this)
        ? MeshData(
            layout: layoutWithTangents,
            vertices: Float32List.fromList(result.vertices),
            indices: Uint32List.fromList(result.indices),
          )
        : result;
    final unsplit = (mesh: out, copiedFrom: Uint32List(0));

    if (normalOffset < 0 || uvOffset < 0) {
      for (var v = 0; v < out.vertexCount; v++) {
        final base = v * stride + tangentOffset;
        out.vertices[base] = 1.0;
        out.vertices[base + 1] = 0.0;
        out.vertices[base + 2] = 0.0;
        out.vertices[base + 3] = 1.0;
      }
      return unsplit;
    }

    if (method == TangentMethod.lengyel) {
      _lengyel(out, stride, tangentOffset, normalOffset, uvOffset);
      return unsplit;
    }
    return _mikkTSpace(
      out,
      stride: stride,
      tangentOffset: tangentOffset,
      normalOffset: normalOffset,
      uvOffset: uvOffset,
      splitSeams: splitSeams,
    );
  }
}

/// [mesh] with the MikkTSpace frame written into every vertex, and the
/// vertices a seam needed appended — see [MeshTangents.withGeneratedTangents].
///
/// Run on the triangles rather than the vertices: each corner gets its frame,
/// and a vertex takes the frame its corners agree on. They agree exactly,
/// bit for bit, wherever MikkTSpace did not split them, because corners of
/// one group are handed one computed frame.
({MeshData mesh, Uint32List copiedFrom}) _mikkTSpace(
  MeshData mesh, {
  required int stride,
  required int tangentOffset,
  required int normalOffset,
  required int uvOffset,
  required bool splitSeams,
}) {
  final vertices = mesh.vertices;
  final vertexCount = mesh.vertexCount;
  final indices = Uint32List.fromList(mesh.indices);
  final corners = mikkTSpaceCorners(
    vertices: vertices,
    stride: stride,
    positionOffset: mesh.layout.floatOffsetOf(VertexLayout.position.name),
    normalOffset: normalOffset,
    texcoordOffset: uvOffset,
    indices: indices,
  );

  bool sameFrame(int corner, List<double> frame, int at) =>
      corners[corner * 4] == frame[at] &&
      corners[corner * 4 + 1] == frame[at + 1] &&
      corners[corner * 4 + 2] == frame[at + 2] &&
      corners[corner * 4 + 3] == frame[at + 3];

  // The frame each vertex keeps, first come; the corners that disagree with
  // it are the seams, and a vertex has one only where handedness changes.
  final frames = Float64List(vertexCount * 4);
  final claimed = Int32List(vertexCount)..fillRange(0, vertexCount, -1);
  final disagreeing = <int>[];
  for (var c = 0; c < indices.length; c++) {
    final v = indices[c];
    if (claimed[v] < 0) {
      claimed[v] = c;
      for (var k = 0; k < 4; k++) {
        frames[v * 4 + k] = corners[c * 4 + k];
      }
    } else if (!sameFrame(c, frames, v * 4)) {
      disagreeing.add(c);
    }
  }

  // Unsplit, a vertex holding two frames takes the one more of its corners
  // have, and the first of those on a tie.
  if (!splitSeams && disagreeing.isNotEmpty) {
    final owned = <int, List<int>>{
      for (final c in disagreeing) indices[c]: <int>[],
    };
    for (var c = 0; c < indices.length; c++) {
      owned[indices[c]]?.add(c);
    }
    for (final MapEntry(key: v, value: around) in owned.entries) {
      int agreeing(int c) =>
          around.where((o) => sameFrame(o, corners, c * 4)).length;
      final best = around.reduce((a, b) => agreeing(b) > agreeing(a) ? b : a);
      frames.setRange(v * 4, v * 4 + 4, corners, best * 4);
    }
  }

  // Split, each different frame at a vertex is one copy of it, shared by
  // every corner there that has that frame.
  final copiedFrom = <int>[];
  final copyFrames = <double>[];
  if (splitSeams) {
    final copiesOf = <int, List<int>>{};
    for (final c in disagreeing) {
      final v = indices[c];
      final copies = copiesOf.putIfAbsent(v, () => <int>[]);
      final existing = copies
          .where((copy) => sameFrame(c, copyFrames, copy * 4))
          .firstOrNull;
      final copy = existing ?? copiedFrom.length;
      if (existing == null) {
        copies.add(copy);
        copiedFrom.add(v);
        for (var k = 0; k < 4; k++) {
          copyFrames.add(corners[c * 4 + k]);
        }
      }
      indices[c] = vertexCount + copy;
    }
  }

  final grown = Float32List((vertexCount + copiedFrom.length) * stride)
    ..setRange(0, vertices.length, vertices);
  for (var i = 0; i < copiedFrom.length; i++) {
    grown.setRange(
      (vertexCount + i) * stride,
      (vertexCount + i + 1) * stride,
      vertices,
      copiedFrom[i] * stride,
    );
  }
  final normal = Vector3.zero();
  final tangent = Vector3.zero();
  for (var v = 0; v < vertexCount + copiedFrom.length; v++) {
    final base = v * stride;
    final frame = v < vertexCount ? frames : copyFrames;
    final at = (v < vertexCount ? v : v - vertexCount) * 4;
    final referenced = v >= vertexCount || claimed[v] >= 0;
    normal.setValues(
      grown[base + normalOffset],
      grown[base + normalOffset + 1],
      grown[base + normalOffset + 2],
    );
    tangent.setValues(
      referenced ? frame[at] : 1.0,
      referenced ? frame[at + 1] : 0.0,
      referenced ? frame[at + 2] : 0.0,
    );
    // MikkTSpace's frames already lie in the tangent plane, so for them this
    // changes nothing. It is for the corner no group reached, where the
    // reference writes +X whatever the normal: a normal along X would leave
    // the shader nothing to build a frame from.
    _perpendicularise(tangent, normal);
    final to = base + tangentOffset;
    grown[to] = tangent.x;
    grown[to + 1] = tangent.y;
    grown[to + 2] = tangent.z;
    grown[to + 3] = referenced ? frame[at + 3] : 1.0;
  }

  return (
    mesh: MeshData(layout: mesh.layout, vertices: grown, indices: indices),
    copiedFrom: Uint32List.fromList(copiedFrom),
  );
}

/// [tangent] made unit and perpendicular to [normal] (which is normalised in
/// place), or a fixed axis in that plane when nothing of it is left.
void _perpendicularise(Vector3 tangent, Vector3 normal) {
  if (normal.length2 > 0.0) normal.normalize();
  tangent.sub(normal.scaled(normal.dot(tangent)));
  if (tangent.length2 < 1e-16) {
    // No usable UV direction here; any vector perpendicular to the normal
    // beats a zero one, and a fixed choice keeps the result reproducible.
    tangent.setFrom(
      normal.z.abs() < 0.9 ? Vector3(0.0, 0.0, 1.0) : Vector3(1.0, 0.0, 0.0),
    );
    tangent.sub(normal.scaled(normal.dot(tangent)));
    if (tangent.length2 < 1e-16) tangent.setValues(1.0, 0.0, 0.0);
  }
  tangent.normalize();
}

/// Lengyel's method, written into [out] in place: each triangle contributes
/// the direction in which U grows across its surface, accumulated per vertex
/// and then made orthogonal to the normal.
void _lengyel(
  MeshData out,
  int stride,
  int tangentOffset,
  int normalOffset,
  int uvOffset,
) {
  final count = out.vertexCount;
  final accumulatedT = Float32List(count * 3);
  final accumulatedB = Float32List(count * 3);
  final vertices = out.vertices;

  for (var i = 0; i + 2 < out.indices.length; i += 3) {
    final i0 = out.indices[i];
    final i1 = out.indices[i + 1];
    final i2 = out.indices[i + 2];

    final p0 = i0 * stride;
    final p1 = i1 * stride;
    final p2 = i2 * stride;

    final e1x = vertices[p1] - vertices[p0];
    final e1y = vertices[p1 + 1] - vertices[p0 + 1];
    final e1z = vertices[p1 + 2] - vertices[p0 + 2];
    final e2x = vertices[p2] - vertices[p0];
    final e2y = vertices[p2 + 1] - vertices[p0 + 1];
    final e2z = vertices[p2 + 2] - vertices[p0 + 2];

    final u0 = p0 + uvOffset, u1 = p1 + uvOffset, u2 = p2 + uvOffset;
    final du1 = vertices[u1] - vertices[u0];
    final dv1 = vertices[u1 + 1] - vertices[u0 + 1];
    final du2 = vertices[u2] - vertices[u0];
    final dv2 = vertices[u2 + 1] - vertices[u0 + 1];

    final determinant = du1 * dv2 - du2 * dv1;
    // A degenerate UV triangle — a collapsed island, or a face with no UVs at
    // all — carries no directional information. Skipping it leaves the
    // vertices to whatever their other faces say, which is better than
    // poisoning them with an infinity.
    if (determinant.abs() < 1e-12) continue;
    final r = 1.0 / determinant;

    final tx = (dv2 * e1x - dv1 * e2x) * r;
    final ty = (dv2 * e1y - dv1 * e2y) * r;
    final tz = (dv2 * e1z - dv1 * e2z) * r;

    final bx = (du1 * e2x - du2 * e1x) * r;
    final by = (du1 * e2y - du2 * e1y) * r;
    final bz = (du1 * e2z - du2 * e1z) * r;

    for (final index in <int>[i0, i1, i2]) {
      final t = index * 3;
      accumulatedT[t] += tx;
      accumulatedT[t + 1] += ty;
      accumulatedT[t + 2] += tz;
      accumulatedB[t] += bx;
      accumulatedB[t + 1] += by;
      accumulatedB[t + 2] += bz;
    }
  }

  final normal = Vector3.zero();
  final tangent = Vector3.zero();
  final bitangent = Vector3.zero();
  final cross = Vector3.zero();

  for (var v = 0; v < count; v++) {
    final base = v * stride;
    normal.setValues(
      vertices[base + normalOffset],
      vertices[base + normalOffset + 1],
      vertices[base + normalOffset + 2],
    );
    tangent.setValues(
      accumulatedT[v * 3],
      accumulatedT[v * 3 + 1],
      accumulatedT[v * 3 + 2],
    );
    bitangent.setValues(
      accumulatedB[v * 3],
      accumulatedB[v * 3 + 1],
      accumulatedB[v * 3 + 2],
    );

    // Gram-Schmidt: strip whatever part of the accumulated tangent points
    // along the normal, which is what averaging across faces introduces.
    _perpendicularise(tangent, normal);

    // glTF: bitangent = cross(normal, tangent) * w. The bitangent it wants is
    // **minus** dP/dv, which is the accumulated vector here — texture V grows
    // downwards while a tangent-space normal map's green channel points up,
    // so the two run opposite ways.
    //
    // Hence the inverted comparison. It is not a guess: rendering
    // NormalTangentMirrorTest, whose tangents come from a real exporter,
    // showed the directions agreeing to seven digits while all 2770 signs came
    // out backwards. Getting this wrong lights every mirrored UV island from
    // the wrong side, and on a symmetric model that is half of it.
    normal.crossInto(tangent, cross);
    final w = cross.dot(bitangent) < 0.0 ? 1.0 : -1.0;

    final to = base + tangentOffset;
    vertices[to] = tangent.x;
    vertices[to + 1] = tangent.y;
    vertices[to + 2] = tangent.z;
    vertices[to + 3] = w;
  }
}
