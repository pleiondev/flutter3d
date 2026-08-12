import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'vertex_layout.dart';

/// Opaque white: a vertex colour multiplies the surface, so this is the value
/// that changes nothing.
final Vector4 kNeutralColor = Vector4(1.0, 1.0, 1.0, 1.0);

/// Every vertex bound to joint zero.
///
/// Paired with [kNeutralWeights], this leaves a vertex following the first
/// joint rigidly, which is what an unrigged vertex in a skinned mesh should do.
final Vector4 kNeutralJoints = Vector4(0.0, 0.0, 0.0, 0.0);

/// All the influence on the first joint.
///
/// Not all zeros: weights that sum to zero collapse the vertex to the origin,
/// so a mesh missing WEIGHTS_0 would implode rather than simply not deform.
final Vector4 kNeutralWeights = Vector4(1.0, 0.0, 0.0, 0.0);

/// A unit tangent along +X with a positive bitangent sign.
///
/// Arbitrary in direction — any unit vector would do for a mesh with no UVs —
/// but it must not be zero, because the shader normalizes it.
final Vector4 kNeutralTangent = Vector4(1.0, 0.0, 0.0, 1.0);

/// Indices packed for GPU upload.
final class PackedIndices {
  const PackedIndices(this.bytes, this.count, {required this.is16Bit});

  final ByteData bytes;
  final int count;
  final bool is16Bit;
}

/// CPU-side geometry: interleaved vertices plus indices.
///
/// This layer deliberately knows nothing about any graphics backend, which keeps it
/// testable without a GPU and portable to another backend.
final class MeshData {
  MeshData({
    required this.layout,
    required this.vertices,
    required this.indices,
  }) {
    final stride = layout.floatsPerVertex;
    if (vertices.length % stride != 0) {
      throw ArgumentError(
        'vertices length (${vertices.length}) is not a multiple of the vertex '
        'size ($stride floats); layout and data disagree.',
      );
    }
    if (indices.length % 3 != 0) {
      throw ArgumentError(
        'indices length (${indices.length}) is not a multiple of 3, so these '
        'are not triangles.',
      );
    }
  }

  final VertexLayout layout;
  final Float32List vertices;

  /// Indices are always 32-bit on the CPU side; narrowing to 16 bit happens
  /// only when packing for the GPU.
  final Uint32List indices;

  int get vertexCount => vertices.length ~/ layout.floatsPerVertex;
  int get indexCount => indices.length;
  int get triangleCount => indices.length ~/ 3;

  bool get fitsIn16BitIndices => vertexCount <= 0x10000;

  ByteData get vertexBytes => vertices.buffer.asByteData(
        vertices.offsetInBytes,
        vertices.lengthInBytes,
      );

  /// Prepares indices for upload. Uses 16 bit wherever possible: half the
  /// bandwidth and memory, and primitives never exceed 65536 vertices.
  PackedIndices packIndices() {
    if (fitsIn16BitIndices) {
      final narrow = Uint16List(indices.length);
      for (var i = 0; i < indices.length; i++) {
        narrow[i] = indices[i];
      }
      return PackedIndices(
        narrow.buffer.asByteData(),
        indices.length,
        is16Bit: true,
      );
    }
    return PackedIndices(
      indices.buffer.asByteData(indices.offsetInBytes, indices.lengthInBytes),
      indices.length,
      is16Bit: false,
    );
  }

  /// Reads a vertex position. Passing [out] avoids allocating in hot loops: in
  /// Dart every `Vector3` is a heap object, and on large meshes GC pauses eat
  /// the frame budget faster than draw calls do.
  Vector3 positionAt(int index, [Vector3? out]) {
    final result = out ?? Vector3.zero();
    final o = index * layout.floatsPerVertex;
    result.setValues(vertices[o], vertices[o + 1], vertices[o + 2]);
    return result;
  }

  Aabb3 computeBounds() {
    if (vertexCount == 0) return Aabb3();
    final stride = layout.floatsPerVertex;
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;

    for (var o = 0; o < vertices.length; o += stride) {
      final x = vertices[o], y = vertices[o + 1], z = vertices[o + 2];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    return Aabb3.minMax(Vector3(minX, minY, minZ), Vector3(maxX, maxY, maxZ));
  }

  /// Signed volume of the mesh.
  ///
  /// For a closed surface whose triangles wind counter-clockwise when seen
  /// from outside, this is positive. It is a cheap, objective winding check:
  /// without it index order has to be eyeballed, and the mistake only shows up
  /// as an inside-out model once backface culling is enabled.
  double signedVolume() {
    final a = Vector3.zero();
    final b = Vector3.zero();
    final c = Vector3.zero();
    final cross = Vector3.zero();
    var total = 0.0;

    for (var i = 0; i < indices.length; i += 3) {
      positionAt(indices[i], a);
      positionAt(indices[i + 1], b);
      positionAt(indices[i + 2], c);
      b.crossInto(c, cross);
      total += a.dot(cross);
    }
    return total / 6.0;
  }

  /// A transformed copy. Normals use the inverse-transpose, otherwise
  /// non-uniform scale skews them.
  MeshData transformed(Matrix4 matrix) {
    final stride = layout.floatsPerVertex;
    final out = Float32List.fromList(vertices);

    final normalOffset = layout.floatOffsetOf(VertexLayout.normal.name);
    final normalMatrix = normalOffset >= 0
        ? (matrix.getRotation()..invert()).transposed()
        : null;

    final p = Vector3.zero();
    final n = Vector3.zero();

    for (var o = 0; o < out.length; o += stride) {
      p.setValues(out[o], out[o + 1], out[o + 2]);
      matrix.transform3(p);
      out[o] = p.x;
      out[o + 1] = p.y;
      out[o + 2] = p.z;

      if (normalMatrix != null) {
        final no = o + normalOffset;
        n.setValues(out[no], out[no + 1], out[no + 2]);
        normalMatrix.transform(n);
        n.normalize();
        out[no] = n.x;
        out[no + 1] = n.y;
        out[no + 2] = n.z;
      }
    }

    return MeshData(
      layout: layout,
      vertices: out,
      indices: Uint32List.fromList(indices),
    );
  }

  /// A copy in a different vertex layout.
  ///
  /// Attributes present in both are copied by name; attributes only the target
  /// declares get their neutral value. Attributes only the source has are
  /// dropped. Returns `this` when the layouts already match, so calling it
  /// defensively costs nothing.
  MeshData convertedTo(VertexLayout target) {
    if (identical(target, layout) ||
        target.attributes.length == layout.attributes.length &&
            target.floatsPerVertex == layout.floatsPerVertex &&
            _sameAttributeNames(target)) {
      return this;
    }

    final sourceStride = layout.floatsPerVertex;
    final targetStride = target.floatsPerVertex;
    final count = vertexCount;
    final out = Float32List(count * targetStride);

    for (final attribute in target.attributes) {
      final to = target.floatOffsetOf(attribute.name);
      final from = layout.floatOffsetOf(attribute.name);

      if (from < 0) {
        final neutral = _neutralFor(attribute);
        if (neutral == null) continue; // already zero
        for (var v = 0; v < count; v++) {
          final base = v * targetStride + to;
          for (var c = 0; c < attribute.componentCount; c++) {
            out[base + c] = neutral[c];
          }
        }
        continue;
      }

      // Only the components both layouts have; a vec3 tangent read into a vec4
      // slot leaves its w at zero rather than at whatever came next in memory.
      final sourceAttribute = layout.attributes.firstWhere(
        (a) => a.name == attribute.name,
      );
      final shared = math.min(
        attribute.componentCount,
        sourceAttribute.componentCount,
      );
      for (var v = 0; v < count; v++) {
        final src = v * sourceStride + from;
        final dst = v * targetStride + to;
        for (var c = 0; c < shared; c++) {
          out[dst + c] = vertices[src + c];
        }
      }
    }

    return MeshData(
      layout: target,
      vertices: out,
      indices: Uint32List.fromList(indices),
    );
  }

  bool _sameAttributeNames(VertexLayout other) {
    for (var i = 0; i < other.attributes.length; i++) {
      if (other.attributes[i].name != layout.attributes[i].name) return false;
    }
    return true;
  }

  static List<double>? _neutralFor(VertexAttribute attribute) {
    if (attribute.name == VertexLayout.color.name) {
      return const <double>[1.0, 1.0, 1.0, 1.0];
    }
    if (attribute.name == VertexLayout.tangent.name) {
      return const <double>[1.0, 0.0, 0.0, 1.0];
    }
    if (attribute.name == VertexLayout.weights.name) {
      return const <double>[1.0, 0.0, 0.0, 0.0];
    }
    // Joints default to zero, which is already what an unwritten slot holds.
    return null;
  }

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

  /// Concatenates meshes that share a layout, rebasing indices.
  static MeshData merge(List<MeshData> parts) {
    if (parts.isEmpty) {
      throw ArgumentError('Nothing to merge: the mesh list is empty.');
    }
    final layout = parts.first.layout;
    for (final part in parts) {
      if (part.layout.floatsPerVertex != layout.floatsPerVertex) {
        throw ArgumentError('Only meshes with the same layout can be merged.');
      }
    }

    var totalFloats = 0;
    var totalIndices = 0;
    for (final part in parts) {
      totalFloats += part.vertices.length;
      totalIndices += part.indices.length;
    }

    final vertices = Float32List(totalFloats);
    final indices = Uint32List(totalIndices);
    var vOffset = 0;
    var iOffset = 0;
    var vertexBase = 0;

    for (final part in parts) {
      vertices.setRange(vOffset, vOffset + part.vertices.length, part.vertices);
      for (var i = 0; i < part.indices.length; i++) {
        indices[iOffset + i] = part.indices[i] + vertexBase;
      }
      vOffset += part.vertices.length;
      iOffset += part.indices.length;
      vertexBase += part.vertexCount;
    }

    return MeshData(layout: layout, vertices: vertices, indices: indices);
  }

  @override
  String toString() =>
      'MeshData($vertexCount vertices, $triangleCount triangles, $layout)';
}

/// Accumulates vertices and indices into growing typed arrays.
///
/// It runs at load time rather than per frame, but grows by doubling instead of
/// using `List<double>` so the data already sits in the form that goes to the
/// GPU.
final class MeshBuilder {
  MeshBuilder(
    this.layout, {
    int reserveVertices = 64,
    int reserveIndices = 128,
  })  : _floatsPerVertex = layout.floatsPerVertex,
        _positionOffset = layout.floatOffsetOf(VertexLayout.position.name),
        _normalOffset = layout.floatOffsetOf(VertexLayout.normal.name),
        _texcoordOffset = layout.floatOffsetOf(VertexLayout.texcoord.name),
        _tangentOffset = layout.floatOffsetOf(VertexLayout.tangent.name),
        _colorOffset = layout.floatOffsetOf(VertexLayout.color.name),
        _jointsOffset = layout.floatOffsetOf(VertexLayout.joints.name),
        _weightsOffset = layout.floatOffsetOf(VertexLayout.weights.name) {
    _vertices = Float32List(
      math.max(1, reserveVertices) * layout.floatsPerVertex,
    );
    _indices = Uint32List(math.max(3, reserveIndices));
  }

  final VertexLayout layout;
  final int _floatsPerVertex;
  final int _positionOffset;
  final int _normalOffset;
  final int _texcoordOffset;
  final int _tangentOffset;
  final int _colorOffset;
  final int _jointsOffset;
  final int _weightsOffset;

  late Float32List _vertices;
  late Uint32List _indices;
  int _vertexFloats = 0;
  int _indexCount = 0;

  int get vertexCount => _vertexFloats ~/ _floatsPerVertex;
  int get indexCount => _indexCount;

  /// Appends a vertex and returns its index.
  ///
  /// Attributes absent from the layout are silently ignored, which lets one
  /// piece of generator code build geometry for several layouts.
  ///
  /// Attributes the layout *declares* but the caller does not supply get a
  /// neutral value rather than zero. Zero is not neutral for either of the two
  /// that have a neutral: a zero vertex colour multiplies the surface to black,
  /// and a zero tangent yields a degenerate TBN full of NaN. Getting a
  /// featureless black model out of a generator that simply did not mention
  /// colour is a bad trade for the sake of a memset.
  int addVertex({
    Vector3? position,
    Vector3? normal,
    Vector2? texcoord,
    Vector4? tangent,
    Vector4? color,
    Vector4? joints,
    Vector4? weights,
  }) {
    if (_vertexFloats + _floatsPerVertex > _vertices.length) {
      _vertices = _growFloats(_vertices, _vertexFloats + _floatsPerVertex);
    }
    final base = _vertexFloats;

    if (_positionOffset >= 0 && position != null) {
      _vertices[base + _positionOffset] = position.x;
      _vertices[base + _positionOffset + 1] = position.y;
      _vertices[base + _positionOffset + 2] = position.z;
    }
    if (_normalOffset >= 0 && normal != null) {
      _vertices[base + _normalOffset] = normal.x;
      _vertices[base + _normalOffset + 1] = normal.y;
      _vertices[base + _normalOffset + 2] = normal.z;
    }
    if (_texcoordOffset >= 0 && texcoord != null) {
      _vertices[base + _texcoordOffset] = texcoord.x;
      _vertices[base + _texcoordOffset + 1] = texcoord.y;
    }
    if (_tangentOffset >= 0) {
      final t = tangent ?? kNeutralTangent;
      _vertices[base + _tangentOffset] = t.x;
      _vertices[base + _tangentOffset + 1] = t.y;
      _vertices[base + _tangentOffset + 2] = t.z;
      _vertices[base + _tangentOffset + 3] = t.w;
    }
    if (_colorOffset >= 0) {
      final c = color ?? kNeutralColor;
      _vertices[base + _colorOffset] = c.x;
      _vertices[base + _colorOffset + 1] = c.y;
      _vertices[base + _colorOffset + 2] = c.z;
      _vertices[base + _colorOffset + 3] = c.w;
    }
    if (_jointsOffset >= 0) {
      final j = joints ?? kNeutralJoints;
      _vertices[base + _jointsOffset] = j.x;
      _vertices[base + _jointsOffset + 1] = j.y;
      _vertices[base + _jointsOffset + 2] = j.z;
      _vertices[base + _jointsOffset + 3] = j.w;
    }
    if (_weightsOffset >= 0) {
      final w = weights ?? kNeutralWeights;
      _vertices[base + _weightsOffset] = w.x;
      _vertices[base + _weightsOffset + 1] = w.y;
      _vertices[base + _weightsOffset + 2] = w.z;
      _vertices[base + _weightsOffset + 3] = w.w;
    }

    _vertexFloats += _floatsPerVertex;
    return base ~/ _floatsPerVertex;
  }

  void addTriangle(int a, int b, int c) {
    if (_indexCount + 3 > _indices.length) {
      _indices = _growIndices(_indices, _indexCount + 3);
    }
    _indices[_indexCount++] = a;
    _indices[_indexCount++] = b;
    _indices[_indexCount++] = c;
  }

  /// A quad along the outline a -> b -> c -> d, split across the a-c diagonal.
  void addQuad(int a, int b, int c, int d) {
    addTriangle(a, b, c);
    addTriangle(a, c, d);
  }

  MeshData build() => MeshData(
        layout: layout,
        vertices: Float32List.sublistView(_vertices, 0, _vertexFloats),
        indices: Uint32List.sublistView(_indices, 0, _indexCount),
      );

  static Float32List _growFloats(Float32List current, int needed) {
    var capacity = math.max(current.length * 2, 16);
    while (capacity < needed) {
      capacity *= 2;
    }
    final grown = Float32List(capacity);
    grown.setRange(0, current.length, current);
    return grown;
  }

  static Uint32List _growIndices(Uint32List current, int needed) {
    var capacity = math.max(current.length * 2, 16);
    while (capacity < needed) {
      capacity *= 2;
    }
    final grown = Uint32List(capacity);
    grown.setRange(0, current.length, current);
    return grown;
  }
}
