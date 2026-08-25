import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'mesh_data.dart';
import 'vertex_layout.dart';

/// Tangent generation, split out of [MeshData] because Lengyel's method is a
/// self-contained algorithm that only ever touches [MeshData]'s public
/// surface — an extension keeps it that way rather than granting it access to
/// private state it does not need.
extension MeshTangents on MeshData {
  /// A copy with per-vertex tangents derived from the UV parametrization.
  ///
  /// Lengyel's method: each triangle contributes the direction in which U grows
  /// across its surface, accumulated per vertex and then made orthogonal to the
  /// normal. The `w` component is glTF's bitangent sign, which is what encodes a
  /// mirrored UV island — get it backwards and a normal-mapped surface lights
  /// from the wrong side, which is exactly what `NormalTangentTest` is built to
  /// show.
  ///
  /// Requires normals and texture coordinates. Without UVs there is no tangent
  /// frame to derive, so the neutral tangent is written instead and the caller
  /// gets geometry that at least does not produce NaN.
  MeshData withGeneratedTangents({VertexLayout? target}) {
    final layoutWithTangents = target ??
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
    final tangentOffset =
        layoutWithTangents.floatOffsetOf(VertexLayout.tangent.name);
    final normalOffset =
        layoutWithTangents.floatOffsetOf(VertexLayout.normal.name);
    final uvOffset =
        layoutWithTangents.floatOffsetOf(VertexLayout.texcoord.name);

    // A mesh copied from itself would be mutated in place, which would surprise
    // a caller holding the original.
    final out = identical(result, this)
        ? MeshData(
            layout: layoutWithTangents,
            vertices: Float32List.fromList(result.vertices),
            indices: Uint32List.fromList(result.indices),
          )
        : result;

    if (normalOffset < 0 || uvOffset < 0) {
      for (var v = 0; v < out.vertexCount; v++) {
        final base = v * stride + tangentOffset;
        out.vertices[base] = 1.0;
        out.vertices[base + 1] = 0.0;
        out.vertices[base + 2] = 0.0;
        out.vertices[base + 3] = 1.0;
      }
      return out;
    }

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

      if (normal.length2 > 0.0) normal.normalize();

      // Gram-Schmidt: strip whatever part of the accumulated tangent points
      // along the normal, which is what averaging across faces introduces.
      tangent.sub(normal.scaled(normal.dot(tangent)));

      if (tangent.length2 < 1e-16) {
        // No usable UV direction here; any vector perpendicular to the normal
        // beats a zero one, and a fixed choice keeps the result reproducible.
        tangent.setFrom(
          normal.z.abs() < 0.9
              ? Vector3(0.0, 0.0, 1.0)
              : Vector3(1.0, 0.0, 0.0),
        );
        tangent.sub(normal.scaled(normal.dot(tangent)));
        if (tangent.length2 < 1e-16) tangent.setValues(1.0, 0.0, 0.0);
      }
      tangent.normalize();

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

    return out;
  }
}
