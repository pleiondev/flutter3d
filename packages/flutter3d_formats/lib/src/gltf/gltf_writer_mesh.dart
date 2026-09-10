/// Turns a [ModelSurface]'s interleaved [MeshData] into glTF accessors: one
/// contiguous buffer view per attribute, de-interleaved by
/// [VertexLayout.floatOffsetOf], plus the index accessor.
///
/// **A part of `gltf_writer.dart`, not a file of its own**, for the same
/// reason as every phase of the loader it mirrors: it appends to the single
/// binary blob and the flat `accessors`/`bufferViews` arrays declared there,
/// and keeping those private is what a `part` buys over an import.
part of 'gltf_writer.dart';

/// glTF attribute name → the layout attribute that fills it, in the order a
/// primitive's `attributes` object is built. `POSITION` is not in this list:
/// every surface has one and it is written unconditionally, since a mesh with
/// no position accessor at all is not a mesh glTF can describe.
const List<(String, VertexAttribute)> _kOptionalGltfAttributes = [
  ('NORMAL', VertexLayout.normal),
  ('TEXCOORD_0', VertexLayout.texcoord),
  ('TANGENT', VertexLayout.tangent),
  ('COLOR_0', VertexLayout.color),
  ('JOINTS_0', VertexLayout.joints),
  ('WEIGHTS_0', VertexLayout.weights),
];

extension _GltfWriterMesh on GltfWriter {
  /// The `attributes`/`indices`/`material` object for `document.surfaces[i]`.
  ///
  /// The accessors underneath are cached by [MeshData] identity: two surfaces
  /// sharing one mesh object — a prop instanced across many nodes — write its
  /// vertex and index data once and both primitives point at the same
  /// accessors, which is the geometry half of the plan's dedup ask.
  Map<String, Object?> _primitiveFor(int surfaceIndex) {
    final surface = document.surfaces[surfaceIndex];
    final encoded = _accessorsFor(surface.mesh);
    return <String, Object?>{
      'attributes': encoded.attributes,
      'indices': encoded.indicesAccessor,
      if (surface.materialIndex != null) 'material': surface.materialIndex,
    };
  }

  _EncodedMesh _accessorsFor(MeshData mesh) {
    final cached = _meshAccessorCache[mesh];
    if (cached != null) return cached;

    final layout = mesh.layout;
    final stride = layout.floatsPerVertex;
    final vertexCount = mesh.vertexCount;

    Float32List column(VertexAttribute attribute) {
      final offset = layout.floatOffsetOf(attribute.name);
      final out = Float32List(vertexCount * attribute.componentCount);
      for (var v = 0; v < vertexCount; v++) {
        final from = v * stride + offset;
        final to = v * attribute.componentCount;
        for (var c = 0; c < attribute.componentCount; c++) {
          out[to + c] = mesh.vertices[from + c];
        }
      }
      return out;
    }

    final bounds = mesh.computeBounds();
    final positions = column(VertexLayout.position);
    final positionAccessor = _addAccessor(<String, Object?>{
      'bufferView': _appendBufferView(positions, target: 34962),
      'componentType': GltfComponentType.float.code,
      'type': GltfAccessorType.vec3.name,
      'count': vertexCount,
      'min': <double>[bounds.min.x, bounds.min.y, bounds.min.z],
      'max': <double>[bounds.max.x, bounds.max.y, bounds.max.z],
    });

    final attributes = <String, Object?>{'POSITION': positionAccessor};
    for (final (name, attribute) in _kOptionalGltfAttributes) {
      if (!layout.has(attribute)) continue;
      attributes[name] = _addAccessor(<String, Object?>{
        'bufferView': _appendBufferView(column(attribute), target: 34962),
        'componentType': GltfComponentType.float.code,
        'type': attribute.componentCount == 2
            ? GltfAccessorType.vec2.name
            : attribute.componentCount == 3
            ? GltfAccessorType.vec3.name
            : GltfAccessorType.vec4.name,
        'count': vertexCount,
      });
    }

    final packed = mesh.packIndices();
    final TypedData packedIndices = packed.is16Bit
        ? Uint16List.view(
            packed.bytes.buffer,
            packed.bytes.offsetInBytes,
            packed.count,
          )
        : Uint32List.view(
            packed.bytes.buffer,
            packed.bytes.offsetInBytes,
            packed.count,
          );
    final indicesAccessor = _addAccessor(<String, Object?>{
      'bufferView': _appendBufferView(packedIndices, target: 34963),
      'componentType':
          (packed.is16Bit
                  ? GltfComponentType.unsignedShort
                  : GltfComponentType.unsignedInt)
              .code,
      'type': GltfAccessorType.scalar.name,
      'count': packed.count,
    });

    final result = _EncodedMesh(
      attributes: attributes,
      indicesAccessor: indicesAccessor,
    );
    _meshAccessorCache[mesh] = result;
    return result;
  }
}

/// glTF attribute accessors already written for one [MeshData], cached so a
/// mesh shared by several surfaces is encoded once.
final class _EncodedMesh {
  const _EncodedMesh({required this.attributes, required this.indicesAccessor});

  final Map<String, Object?> attributes;
  final int indicesAccessor;
}
