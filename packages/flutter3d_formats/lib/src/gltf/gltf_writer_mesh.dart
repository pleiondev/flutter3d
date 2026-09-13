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

/// The normalized-integer encoding `fmt-30n` uses for one glTF attribute name,
/// or null when that attribute is never quantized (`JOINTS_0` stays an
/// explicit unsigned type already, handled on its own; `WEIGHTS_0` is left
/// float since a weight already carries the precision its own renormalization
/// needs).
///
/// `signed` picks the value range a component is checked and encoded against:
/// `[-1, 1]` for a direction, `[0, 1]` for a coordinate or colour channel.
({GltfComponentType componentType, bool signed})? _quantizationOf(
  String attributeName,
) => switch (attributeName) {
  'NORMAL' ||
  'TANGENT' => (componentType: GltfComponentType.byte, signed: true),
  'TEXCOORD_0' => (
    componentType: GltfComponentType.unsignedShort,
    signed: false,
  ),
  'COLOR_0' => (componentType: GltfComponentType.unsignedByte, signed: false),
  _ => null,
};

extension _GltfWriterMesh on GltfWriter {
  /// [floats] written as a normalized-integer accessor of [glTFType] when
  /// [name] has a quantization rule ([_quantizationOf]) and every value in
  /// [floats] actually falls inside that rule's own range — with enough
  /// margin that quantizing it back out reads as the same number, not a
  /// clamp — else the ordinary `FLOAT` accessor `compressGeometry: false`
  /// would have written.
  ///
  /// **Never clamps a value that does not fit.** A texture tiled past `[0,
  /// 1]`, or a normal that came in already denormalized past `[-1, 1]` by
  /// more than rounding, would lose real information to a `[-1, 1]`/`[0, 1]`
  /// squeeze — exactly the "understates the row's own claim" failure this
  /// session does not ship. Falling back to float for that one attribute on
  /// that one primitive costs nothing but the bytes it would have saved.
  int _quantizedOrFloatAccessor(String name, Float32List floats, String type) {
    final componentCount = type == GltfAccessorType.vec2.name
        ? 2
        : type == GltfAccessorType.vec3.name
        ? 3
        : 4;
    final rule = _quantizationOf(name);
    if (rule != null && _fitsQuantization(floats, signed: rule.signed)) {
      _usedQuantization = true;
      _extensionsUsed.add('KHR_mesh_quantization');
      _extensionsRequired.add('KHR_mesh_quantization');
      final encoded = _encodeNormalized(
        floats,
        rule.componentType,
        rule.signed,
      );

      // glTF requires vertex attribute data aligned to 4 bytes
      // (`MESH_PRIMITIVE_ACCESSOR_UNALIGNED` in the official validator). A
      // `vec3` of a 1-byte component — `NORMAL`, quantized to a signed byte —
      // packs 3 bytes a vertex, which is not; every other quantized shape
      // here (`vec4` bytes, `vec2` shorts) already lands on 4. Padding to a
      // 4-byte stride costs one wasted byte a vertex, still far short of the
      // 12 a `FLOAT` vec3 would have spent.
      final naturalStride = componentCount * rule.componentType.sizeInBytes;
      final paddedStride = (naturalStride + 3) & ~3;
      final bufferData = paddedStride == naturalStride
          ? encoded
          : _paddedToStride(encoded, naturalStride, paddedStride);

      return _addAccessor(<String, Object?>{
        'bufferView': _appendBufferView(
          bufferData,
          target: 34962,
          byteStride: paddedStride == naturalStride ? null : paddedStride,
        ),
        'componentType': rule.componentType.code,
        'normalized': true,
        'type': type,
        'count': floats.length ~/ componentCount,
      });
    }
    return _addAccessor(<String, Object?>{
      'bufferView': _appendBufferView(floats, target: 34962),
      'componentType': GltfComponentType.float.code,
      'type': type,
      'count': floats.length ~/ componentCount,
    });
  }

  /// [source]'s bytes, packed [naturalStride] bytes a vertex, repacked at
  /// [paddedStride] bytes a vertex with the gap zero-filled.
  Uint8List _paddedToStride(
    TypedData source,
    int naturalStride,
    int paddedStride,
  ) {
    final bytes = Uint8List.sublistView(
      source.buffer.asUint8List(source.offsetInBytes, source.lengthInBytes),
    );
    final vertexCount = bytes.length ~/ naturalStride;
    final out = Uint8List(vertexCount * paddedStride);
    for (var v = 0; v < vertexCount; v++) {
      out.setRange(
        v * paddedStride,
        v * paddedStride + naturalStride,
        bytes,
        v * naturalStride,
      );
    }
    return out;
  }

  /// Whether every value in [floats] sits within the range a normalized
  /// integer can represent without clamping — `[-1, 1]` when [signed],
  /// `[0, 1]` otherwise — allowing `1e-4` of slack for the ordinary rounding
  /// error a computed normal or an interpolated colour already carries.
  bool _fitsQuantization(Float32List floats, {required bool signed}) {
    const slack = 1e-4;
    final low = signed ? -1.0 - slack : -slack;
    const high = 1.0 + slack;
    for (final v in floats) {
      if (v < low || v > high) return false;
    }
    return true;
  }

  /// [floats] packed into [componentType]'s own bytes, each value clamped to
  /// exactly `[-1, 1]`/`[0, 1]` first (the `1e-4` slack [_fitsQuantization]
  /// allowed in is rounding error, not room the encoded value should keep)
  /// and rounded to the nearest representable integer — the same asymmetric
  /// signed range [GltfComponentType.readDouble] decodes, so the round trip
  /// through this package's own loader is exact up to that rounding.
  TypedData _encodeNormalized(
    Float32List floats,
    GltfComponentType componentType,
    bool signed,
  ) {
    switch (componentType) {
      case GltfComponentType.byte:
        final out = Int8List(floats.length);
        for (var i = 0; i < floats.length; i++) {
          out[i] = (floats[i].clamp(-1.0, 1.0) * 127.0).round();
        }
        return out;
      case GltfComponentType.unsignedByte:
        final out = Uint8List(floats.length);
        for (var i = 0; i < floats.length; i++) {
          out[i] = (floats[i].clamp(0.0, 1.0) * 255.0).round();
        }
        return out;
      case GltfComponentType.unsignedShort:
        final out = Uint16List(floats.length);
        for (var i = 0; i < floats.length; i++) {
          out[i] = (floats[i].clamp(0.0, 1.0) * 65535.0).round();
        }
        return out;
      default:
        throw StateError('$componentType is not a quantization target.');
    }
  }

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

    // Reordered for GPU cache reuse before anything below reads a single
    // float, so every accessor built past this line already carries the
    // compressed geometry's own vertex/triangle order — `_meshAccessorCache`
    // stays keyed by the original mesh's identity so a mesh shared by two
    // surfaces is still reordered and encoded once.
    final source = compressGeometry ? optimizeVertexCache(mesh) : mesh;
    if (!identical(source, mesh)) _usedVertexCacheReordering = true;

    final layout = source.layout;
    final stride = layout.floatsPerVertex;
    final vertexCount = source.vertexCount;

    Float32List column(VertexAttribute attribute) {
      final offset = layout.floatOffsetOf(attribute.name);
      final out = Float32List(vertexCount * attribute.componentCount);
      for (var v = 0; v < vertexCount; v++) {
        final from = v * stride + offset;
        final to = v * attribute.componentCount;
        for (var c = 0; c < attribute.componentCount; c++) {
          out[to + c] = source.vertices[from + c];
        }
      }
      return out;
    }

    final bounds = source.computeBounds();
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

      final type = attribute.componentCount == 2
          ? GltfAccessorType.vec2.name
          : attribute.componentCount == 3
          ? GltfAccessorType.vec3.name
          : GltfAccessorType.vec4.name;
      final floats = column(attribute);
      attributes[name] = compressGeometry
          ? _quantizedOrFloatAccessor(name, floats, type)
          : _addAccessor(<String, Object?>{
              'bufferView': _appendBufferView(floats, target: 34962),
              'componentType': GltfComponentType.float.code,
              'type': type,
              'count': vertexCount,
            });
    }

    final packed = source.packIndices();
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
      for (final target in source.morphTargets)
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
        for (final target in source.morphTargets) target.name,
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
