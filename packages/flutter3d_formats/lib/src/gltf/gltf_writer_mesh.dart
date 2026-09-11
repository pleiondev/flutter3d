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
      if (encoded.targets.isNotEmpty) 'targets': encoded.targets,
    };
  }

  /// Morph target names for `document.surfaces[i].mesh`, for the mesh-level
  /// `extras.targetNames` a glTF file puts beside its primitives' `targets`.
  ///
  /// Safe to call only after every surface has gone through `_primitiveFor`
  /// once — `writeGlb` does that before building the scene — since this reads
  /// the same cache rather than re-encoding.
  List<String?> _targetNamesFor(int surfaceIndex) =>
      _accessorsFor(document.surfaces[surfaceIndex].mesh).targetNames;

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

      // JOINTS_0 is the one attribute glTF requires as integers — a reader
      // is allowed to refuse a float accessor here, and this package's own
      // does. `VertexLayout.joints` stores indices as floats on purpose (a
      // float32 is exact up to 2^24, so nothing is lost converting), but the
      // file has to say UNSIGNED_SHORT or the round trip decodes to nothing.
      if (name == 'JOINTS_0') {
        final floats = column(attribute);
        final joints = Uint16List(floats.length);
        for (var i = 0; i < floats.length; i++) {
          joints[i] = floats[i].round();
        }
        attributes[name] = _addAccessor(<String, Object?>{
          'bufferView': _appendBufferView(joints, target: 34962),
          'componentType': GltfComponentType.unsignedShort.code,
          'type': GltfAccessorType.vec4.name,
          'count': vertexCount,
        });
        continue;
      }

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

    final targets = <Map<String, Object?>>[
      for (final target in mesh.morphTargets)
        <String, Object?>{
          'POSITION': _addAccessor(<String, Object?>{
            'bufferView': _appendBufferView(target.positions),
            'componentType': GltfComponentType.float.code,
            'type': GltfAccessorType.vec3.name,
            'count': vertexCount,
            // Required on every morph accessor, not only the base POSITION —
            // the spec's own rule, and the one dimension `computeBounds`
            // cannot answer since it reads a mesh's base vertices, not a
            // target's deltas. `MorphTarget.displacement` is that box already
            // computed, kept for exactly this.
            'min': <double>[
              target.displacement.min.x,
              target.displacement.min.y,
              target.displacement.min.z,
            ],
            'max': <double>[
              target.displacement.max.x,
              target.displacement.max.y,
              target.displacement.max.z,
            ],
          }),
          if (target.normals case final normals?)
            'NORMAL': _addAccessor(<String, Object?>{
              'bufferView': _appendBufferView(normals),
              'componentType': GltfComponentType.float.code,
              'type': GltfAccessorType.vec3.name,
              'count': vertexCount,
            }),
          if (target.tangents case final tangents?)
            'TANGENT': _addAccessor(<String, Object?>{
              'bufferView': _appendBufferView(tangents),
              'componentType': GltfComponentType.float.code,
              'type': GltfAccessorType.vec3.name,
              'count': vertexCount,
            }),
        },
    ];

    final result = _EncodedMesh(
      attributes: attributes,
      indicesAccessor: indicesAccessor,
      targets: targets,
      // Index-aligned with [targets] — glTF's `extras.targetNames[i]` names
      // `primitive.targets[i]` — so a target with no name still holds its
      // place with `null` rather than shifting every name after it left.
      targetNames: <String?>[
        for (final target in mesh.morphTargets) target.name,
      ],
    );
    _meshAccessorCache[mesh] = result;
    return result;
  }
}

/// glTF attribute accessors already written for one [MeshData], cached so a
/// mesh shared by several surfaces is encoded once.
final class _EncodedMesh {
  const _EncodedMesh({
    required this.attributes,
    required this.indicesAccessor,
    required this.targets,
    required this.targetNames,
  });

  final Map<String, Object?> attributes;
  final int indicesAccessor;

  /// One `{POSITION, NORMAL?, TANGENT?}` per morph target, index-aligned with
  /// [MeshData.morphTargets] and with [targetNames].
  final List<Map<String, Object?>> targets;
  final List<String?> targetNames;
}
