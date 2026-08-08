import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'vertex_layout.dart';

/// Indices packed for GPU upload.
final class PackedIndices {
  const PackedIndices(this.bytes, this.count, {required this.is16Bit});

  final ByteData bytes;
  final int count;
  final bool is16Bit;
}

/// CPU-side geometry: interleaved vertices plus indices.
///
/// This layer deliberately knows nothing about flutter_gpu, which keeps it
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
        _colorOffset = layout.floatOffsetOf(VertexLayout.color.name) {
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
  int addVertex({
    Vector3? position,
    Vector3? normal,
    Vector2? texcoord,
    Vector4? tangent,
    Vector4? color,
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
    if (_tangentOffset >= 0 && tangent != null) {
      _vertices[base + _tangentOffset] = tangent.x;
      _vertices[base + _tangentOffset + 1] = tangent.y;
      _vertices[base + _tangentOffset + 2] = tangent.z;
      _vertices[base + _tangentOffset + 3] = tangent.w;
    }
    if (_colorOffset >= 0 && color != null) {
      _vertices[base + _colorOffset] = color.x;
      _vertices[base + _colorOffset + 1] = color.y;
      _vertices[base + _colorOffset + 2] = color.z;
      _vertices[base + _colorOffset + 3] = color.w;
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
