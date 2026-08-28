import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'mesh_data.dart';
import 'vertex_layout.dart';

/// Accumulates vertices and indices into growing typed arrays.
///
/// It runs at load time rather than per frame, but grows by doubling instead of
/// using `List<double>` so the data already sits in the form that goes to the
/// GPU.
final class MeshBuilder {
  MeshBuilder(this.layout, {int reserveVertices = 64, int reserveIndices = 128})
    : _floatsPerVertex = layout.floatsPerVertex,
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
