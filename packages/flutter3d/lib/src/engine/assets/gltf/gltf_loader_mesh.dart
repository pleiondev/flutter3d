/// Mesh and primitive decoding: glTF's `meshes` turned into engine
/// [MeshData], read through the [GltfPrimitiveMode] topology declared in its
/// own file — a self-contained enum with no need of anything private here.
///
/// **A part of `gltf_loader.dart`, not a file of its own**, for the same
/// reason as the rest of this pipeline's phases: `_decodeMesh` is called from
/// `_decodeScene` in `gltf_loader_scene.dart`, and every phase reads the
/// private JSON helpers (`_mapList`, `_intList`, `_asInt`, ...) declared at the
/// bottom of `gltf_loader.dart`. Those stay unexported by staying in the same
/// library.
part of 'gltf_loader.dart';

extension _GltfMesh on GltfLoader {
  // ------------------------------------------------------------------- meshes

  List<_DecodedPrimitive> _decodeMesh(
    Map<String, Object?> mesh,
    int meshIndex,
    GltfAccessorReader reader,
    List<String> warnings,
  ) {
    final primitives = _mapList(mesh['primitives']);
    final result = <_DecodedPrimitive>[];

    for (var i = 0; i < primitives.length; i++) {
      final primitive = primitives[i];
      final label = 'meshes[$meshIndex].primitives[$i]';

      final modeCode = _asInt(primitive['mode']) ?? 4;
      final GltfPrimitiveMode mode;
      try {
        mode = GltfPrimitiveMode.fromCode(modeCode);
      } on FormatException {
        warnings.add('$label has unknown mode $modeCode; skipped.');
        continue;
      }
      if (!mode.isTriangles) {
        warnings.add(
          '$label uses ${mode.name}; only triangle topologies are drawn.',
        );
        continue;
      }

      if (primitive['extensions'] is Map) {
        final extensions = (primitive['extensions']! as Map).keys;
        for (final name in extensions) {
          if (name == 'KHR_draco_mesh_compression' ||
              name == 'EXT_meshopt_compression') {
            warnings.add(
              '$label uses $name, which is not implemented; the primitive was '
              'read from its uncompressed accessors instead.',
            );
          }
        }
      }

      final attributes = primitive['attributes'];
      if (attributes is! Map) {
        warnings.add('$label has no attributes; skipped.');
        continue;
      }
      final positionAccessor = _asInt(attributes['POSITION']);
      if (positionAccessor == null) {
        warnings.add('$label has no POSITION; skipped.');
        continue;
      }

      try {
        final decoded = _decodePrimitive(
          label: label,
          mode: mode,
          attributes: attributes.cast<String, Object?>(),
          indicesAccessor: _asInt(primitive['indices']),
          materialIndex: _asInt(primitive['material']),
          reader: reader,
          warnings: warnings,
        );
        if (decoded != null) result.add(decoded);
      } on FormatException catch (error) {
        // One broken primitive should not sink the whole file.
        warnings.add('$label failed to decode: ${error.message}');
      }
    }

    return result;
  }

  _DecodedPrimitive? _decodePrimitive({
    required String label,
    required GltfPrimitiveMode mode,
    required Map<String, Object?> attributes,
    required int? indicesAccessor,
    required int? materialIndex,
    required GltfAccessorReader reader,
    required List<String> warnings,
  }) {
    final positionAccessor = _asInt(attributes['POSITION'])!;
    final positions = reader.readAsFloats(positionAccessor);
    final vertexCount = reader.countOf(positionAccessor);
    if (vertexCount == 0) return null;

    // A primitive with joint attributes is a skinned mesh, whichever node ends
    // up drawing it, so the layout follows the data rather than the caller.
    final hasSkinAttributes =
        attributes['JOINTS_0'] != null && attributes['WEIGHTS_0'] != null;
    final primitiveLayout = hasSkinAttributes && skinnedLayout.isSkinned
        ? skinnedLayout
        : layout;

    final wantsNormal = primitiveLayout.has(VertexLayout.normal);
    final wantsTexcoord = primitiveLayout.has(VertexLayout.texcoord);
    final wantsTangent = primitiveLayout.has(VertexLayout.tangent);
    final wantsColor = primitiveLayout.has(VertexLayout.color);
    final wantsSkinning = primitiveLayout.isSkinned;

    Float32List? normals;
    final normalAccessor = _asInt(attributes['NORMAL']);
    if (wantsNormal && normalAccessor != null) {
      normals = reader.readAsFloats(normalAccessor);
    }

    Float32List? texcoords;
    final texcoordAccessor = _asInt(attributes['TEXCOORD_0']);
    if (wantsTexcoord && texcoordAccessor != null) {
      texcoords = reader.readAsFloats(texcoordAccessor);
    }

    Float32List? tangents;
    final tangentAccessor = _asInt(attributes['TANGENT']);
    if (wantsTangent && tangentAccessor != null) {
      tangents = reader.readAsFloats(tangentAccessor);
    }

    Float32List? colors;
    var colorComponents = 4;
    final colorAccessor = _asInt(attributes['COLOR_0']);
    if (wantsColor && colorAccessor != null) {
      colors = reader.readAsFloats(colorAccessor);
      colorComponents = reader.typeOf(colorAccessor).componentCount;
    }

    Uint32List? joints;
    Float32List? weights;
    if (wantsSkinning) {
      final jointAccessor = _asInt(attributes['JOINTS_0']);
      final weightAccessor = _asInt(attributes['WEIGHTS_0']);
      // Joints are read as integers, not floats: the accessor is an unsigned
      // byte or short, and running it through the normalization path would turn
      // joint 3 of 200 into 0.015.
      if (jointAccessor != null) joints = reader.readAsUint32(jointAccessor);
      if (weightAccessor != null) {
        weights = reader.readAsFloats(weightAccessor);
      }
      if ((joints == null) != (weights == null)) {
        warnings.add(
          '$label has only one of JOINTS_0 and WEIGHTS_0; both are needed to '
          'skin, so the primitive was left rigid.',
        );
        joints = null;
        weights = null;
      }
    }

    // Indices are optional; without them vertices are consumed in order.
    Uint32List indices;
    if (indicesAccessor != null) {
      indices = reader.readAsUint32(indicesAccessor);
    } else {
      indices = Uint32List(vertexCount);
      for (var i = 0; i < vertexCount; i++) {
        indices[i] = i;
      }
    }

    indices = mode.toTriangleList(indices);
    if (indices.isEmpty) {
      warnings.add('$label produced no triangles; skipped.');
      return null;
    }

    for (final index in indices) {
      if (index >= vertexCount) {
        throw FormatException(
          'index $index exceeds the $vertexCount vertices of POSITION',
        );
      }
    }

    final needsFlatNormals =
        wantsNormal && normals == null && generateFlatNormalsWhenMissing;

    final builder = MeshBuilder(
      primitiveLayout,
      reserveVertices: needsFlatNormals ? indices.length : vertexCount,
      reserveIndices: indices.length,
    );

    final position = Vector3.zero();
    final normal = Vector3.zero();
    final texcoord = Vector2.zero();
    final tangent = Vector4(0.0, 0.0, 0.0, 1.0);
    final color = Vector4(1.0, 1.0, 1.0, 1.0);
    final jointIndices = Vector4.zero();
    final jointWeights = Vector4(1.0, 0.0, 0.0, 0.0);

    void readVertex(int source) {
      final p = source * 3;
      position.setValues(positions[p], positions[p + 1], positions[p + 2]);

      if (normals != null) {
        final n = source * 3;
        normal.setValues(normals[n], normals[n + 1], normals[n + 2]);
      }
      if (texcoords != null) {
        final t = source * 2;
        texcoord.setValues(texcoords[t], texcoords[t + 1]);
      } else {
        texcoord.setZero();
      }
      if (tangents != null) {
        final t = source * 4;
        tangent.setValues(
          tangents[t],
          tangents[t + 1],
          tangents[t + 2],
          tangents[t + 3],
        );
      }
      if (colors != null) {
        final c = source * colorComponents;
        color.setValues(
          colors[c],
          colors[c + 1],
          colors[c + 2],
          colorComponents == 4 ? colors[c + 3] : 1.0,
        );
      }
      if (joints != null && weights != null) {
        final j = source * 4;
        jointIndices.setValues(
          joints[j].toDouble(),
          joints[j + 1].toDouble(),
          joints[j + 2].toDouble(),
          joints[j + 3].toDouble(),
        );
        jointWeights.setValues(
          weights[j],
          weights[j + 1],
          weights[j + 2],
          weights[j + 3],
        );
      }
    }

    if (needsFlatNormals) {
      // Flat shading needs one normal per face, so shared vertices have to be
      // split. This grows the vertex count to 3x the triangle count, which is
      // the price the spec's flat-shading rule implies.
      final a = Vector3.zero();
      final b = Vector3.zero();
      final c = Vector3.zero();
      final faceNormal = Vector3.zero();

      for (var i = 0; i < indices.length; i += 3) {
        final i0 = indices[i], i1 = indices[i + 1], i2 = indices[i + 2];
        a.setValues(
          positions[i0 * 3],
          positions[i0 * 3 + 1],
          positions[i0 * 3 + 2],
        );
        b.setValues(
          positions[i1 * 3],
          positions[i1 * 3 + 1],
          positions[i1 * 3 + 2],
        );
        c.setValues(
          positions[i2 * 3],
          positions[i2 * 3 + 1],
          positions[i2 * 3 + 2],
        );
        (b - a).crossInto(c - a, faceNormal);
        if (faceNormal.length2 > 0.0) faceNormal.normalize();

        final base = builder.vertexCount;
        for (final source in <int>[i0, i1, i2]) {
          readVertex(source);
          normal.setFrom(faceNormal);
          builder.addVertex(
            position: position,
            normal: normal,
            texcoord: texcoord,
            tangent: tangent,
            color: color,
            joints: jointIndices,
            weights: jointWeights,
          );
        }
        builder.addTriangle(base, base + 1, base + 2);
      }
    } else {
      if (wantsNormal && normals == null) {
        warnings.add(
          '$label has no NORMAL; vertices were left with zero normals.',
        );
      }
      for (var source = 0; source < vertexCount; source++) {
        readVertex(source);
        builder.addVertex(
          position: position,
          normal: normal,
          texcoord: texcoord,
          tangent: tangent,
          color: color,
          joints: jointIndices,
          weights: jointWeights,
        );
      }
      for (var i = 0; i < indices.length; i += 3) {
        builder.addTriangle(indices[i], indices[i + 1], indices[i + 2]);
      }
    }

    var mesh = builder.build();

    // glTF says a normal-mapped primitive without TANGENT must have tangents
    // computed with a standard algorithm. Doing it unconditionally when the
    // layout asks for tangents is simpler and no less correct: without UVs the
    // generator writes the neutral frame, which is what the vertices already
    // hold.
    if (wantsTangent && tangents == null) {
      mesh = mesh.withGeneratedTangents(target: primitiveLayout);
    }

    return _DecodedPrimitive(mesh: mesh, materialIndex: materialIndex);
  }
}

final class _DecodedPrimitive {
  const _DecodedPrimitive({required this.mesh, required this.materialIndex});

  final MeshData mesh;
  final int? materialIndex;
}
