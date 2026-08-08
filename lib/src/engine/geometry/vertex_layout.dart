/// Describes a single vertex attribute.
///
/// flutter_gpu has no attribute descriptors: a vertex buffer is bound as one
/// opaque blob and the actual layout is taken from the order of `in`
/// declarations in the vertex shader. The layout is therefore a contract
/// between shader and CPU-side geometry that nothing validates for us.
/// [VertexLayout] at least makes it explicit and keeps it in one place.
final class VertexAttribute {
  const VertexAttribute(this.name, this.componentCount);

  /// Must match the name of the `in` variable in the shader.
  final String name;

  /// Number of float components.
  final int componentCount;

  @override
  String toString() => '$name(x$componentCount)';
}

/// An ordered set of attributes making up an interleaved vertex.
final class VertexLayout {
  const VertexLayout(this.attributes);

  final List<VertexAttribute> attributes;

  static const VertexAttribute position = VertexAttribute('position', 3);
  static const VertexAttribute normal = VertexAttribute('normal', 3);
  static const VertexAttribute texcoord = VertexAttribute('texcoord', 2);

  /// xyz is the direction, w is the bitangent sign (glTF convention).
  static const VertexAttribute tangent = VertexAttribute('tangent', 4);
  static const VertexAttribute color = VertexAttribute('color', 4);

  static const VertexLayout positionOnly = VertexLayout([position]);

  /// The debug line layout, matching shaders/debug_line.vert.
  static const VertexLayout positionColor = VertexLayout([position, color]);

  static const VertexLayout positionNormal = VertexLayout([position, normal]);
  static const VertexLayout positionNormalTexcoord = VertexLayout([
    position,
    normal,
    texcoord,
  ]);
  static const VertexLayout positionNormalTexcoordTangent = VertexLayout([
    position,
    normal,
    texcoord,
    tangent,
  ]);

  /// What the engine's mesh shader reads: position, normal, UV, tangent, colour.
  ///
  /// One layout for everything rather than a permutation per attribute set. The
  /// vertex layout is structural — flutter_gpu takes it from the shader's `in`
  /// declarations — so a second layout means a second vertex shader and a second
  /// pipeline for every lighting model. At 64 bytes a vertex this costs twice
  /// what position/normal/UV did, which buys normal mapping and vertex colours
  /// without multiplying the bundle.
  static const VertexLayout standard = VertexLayout([
    position,
    normal,
    texcoord,
    tangent,
    color,
  ]);

  int get floatsPerVertex {
    var total = 0;
    for (final a in attributes) {
      total += a.componentCount;
    }
    return total;
  }

  int get strideInBytes => floatsPerVertex * 4;

  bool has(VertexAttribute attribute) => floatOffsetOf(attribute.name) >= 0;

  /// Offset of an attribute within a vertex, in floats. `-1` when absent.
  int floatOffsetOf(String name) {
    var offset = 0;
    for (final a in attributes) {
      if (a.name == name) return offset;
      offset += a.componentCount;
    }
    return -1;
  }

  @override
  String toString() => 'VertexLayout(${attributes.join(', ')})';
}
