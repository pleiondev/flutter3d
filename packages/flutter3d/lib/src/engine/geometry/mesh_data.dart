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
