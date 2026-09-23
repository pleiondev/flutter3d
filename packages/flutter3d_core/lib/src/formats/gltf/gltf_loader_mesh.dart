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
    final meshName = mesh['name'];

    // What a target is called, when the exporter said. glTF puts these in
    // `mesh.extras.targetNames`, which is a convention every tool follows and
    // the specification does not require — so this is a list that is usually
    // empty and occasionally the only way a game can ask for "blink".
    final extras = mesh['extras'];
    final names = extras is Map ? extras['targetNames'] : null;
    final targetNames = <String>[
      if (names is List)
        for (final name in names)
          if (name is String) name,
    ];

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

      // Morph targets are read here and blended by `MorphBlend`. What used to
      // stand in this place was a warning that they were dropped.
      final targets = primitive['targets'];

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

      // `fmt-15`'s own name for what follows: a primitive compressed with
      // either extension keeps its ordinary accessors as a fallback only
      // when an exporter chose to write one — the common case leaves them
      // with no `bufferView` at all, since the real data lives in the
      // extension's own buffer instead. Reading a bufferView-less accessor
      // is legal and reads as all zeros (`GltfAccessorReader`'s own rule,
      // correct for a sparse accessor's base) but wrong here: a degenerate
      // mesh pinched to the origin, decoded in silence.
      //
      // `gfx-82n`: Draco is decoded, and its values are put behind the
      // primitive's own accessors, so everything below reads a compressed
      // primitive exactly as it reads any other. Only when the payload does
      // *not* decode is the primitive back in `fmt-15`'s position — and then
      // the warning carries the decoder's reason, because "skipped" with no
      // why is the hole in the model this row was opened to close.
      final extensions = primitive['extensions'];
      final unreadExtensions = <String>[
        if (extensions is Map) ...<String>[
          if (extensions.containsKey('KHR_draco_mesh_compression'))
            if (_supplyDraco(
                  extension: extensions['KHR_draco_mesh_compression'],
                  attributes: attributes,
                  indicesAccessor: _asInt(primitive['indices']),
                  reader: reader,
                )
                case final problem?)
              'KHR_draco_mesh_compression, which did not decode: $problem',
          // On a primitive this is not where the extension lives — it
          // belongs to a buffer view, where `GltfAccessorReader` decodes it —
          // so one named here is one this loader has nothing to do with.
          if (extensions.containsKey('EXT_meshopt_compression'))
            'EXT_meshopt_compression, which is not implemented on a primitive',
        ],
      ];
      for (final name in unreadExtensions) {
        warnings.add(
          '$label uses $name; read from its own uncompressed accessors when '
          'it has any.',
        );
      }
      if (unreadExtensions.isNotEmpty && !reader.hasData(positionAccessor)) {
        warnings.add(
          '$label\'s POSITION accessor has no buffer view of its own; the '
          'compressed data has nowhere else to be read from, so the '
          'primitive is skipped rather than decoded as zeros.',
        );
        continue;
      }

      try {
        final decoded = _decodePrimitive(
          label: label,
          mode: mode,
          attributes: attributes.cast<String, Object?>(),
          indicesAccessor: _asInt(primitive['indices']),
          materialIndex: _asInt(primitive['material']),
          targets: targets is List ? targets : const <Object?>[],
          targetNames: targetNames,
          reader: reader,
          warnings: warnings,
        );
        if (decoded != null) {
          result.add(
            _DecodedPrimitive(
              mesh: decoded.mesh,
              materialIndex: decoded.materialIndex,
              authoredAttributes: decoded.authoredAttributes,
              meshName: meshName is String ? meshName : null,
            ),
          );
        }
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
    required List<Object?> targets,
    required List<String> targetNames,
    required GltfAccessorReader reader,
    required List<String> warnings,
  }) {
    final positionAccessor = _asInt(attributes['POSITION'])!;
    if (reader.typeOf(positionAccessor) != GltfAccessorType.vec3) {
      throw FormatException(
        'POSITION is ${reader.typeOf(positionAccessor).name}, not VEC3',
      );
    }
    final positions = reader.readAsFloats(positionAccessor);
    final vertexCount = reader.countOf(positionAccessor);
    if (vertexCount == 0) return null;

    // Every attribute is read one element per POSITION vertex and at the width
    // its name implies, so an accessor that is shorter, or of another type, is
    // dropped with a warning here rather than indexed past its end below.
    int? usable(String name, Set<GltfAccessorType> types) {
      final accessor = _asInt(attributes[name]);
      if (accessor == null) return null;
      final type = reader.typeOf(accessor);
      final count = reader.countOf(accessor);
      if (count == vertexCount && types.contains(type)) return accessor;
      warnings.add(
        '$label $name is $count ${type.name} elements for $vertexCount '
        'vertices; ignored.',
      );
      return null;
    }

    const vec2 = <GltfAccessorType>{GltfAccessorType.vec2};
    const vec3 = <GltfAccessorType>{GltfAccessorType.vec3};
    const vec4 = <GltfAccessorType>{GltfAccessorType.vec4};

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

    final normalAccessor = wantsNormal ? usable('NORMAL', vec3) : null;
    final normals = normalAccessor == null
        ? null
        : reader.readAsFloats(normalAccessor);

    final texcoordAccessor = wantsTexcoord ? usable('TEXCOORD_0', vec2) : null;
    final texcoords = texcoordAccessor == null
        ? null
        : reader.readAsFloats(texcoordAccessor);

    final tangentAccessor = wantsTangent ? usable('TANGENT', vec4) : null;
    final tangents = tangentAccessor == null
        ? null
        : reader.readAsFloats(tangentAccessor);

    final colorAccessor = wantsColor
        ? usable('COLOR_0', const {
            GltfAccessorType.vec3,
            GltfAccessorType.vec4,
          })
        : null;
    final colors = colorAccessor == null
        ? null
        : reader.readAsFloats(colorAccessor);
    final colorComponents = colorAccessor == null
        ? 4
        : reader.typeOf(colorAccessor).componentCount;

    Uint32List? joints;
    Float32List? weights;
    if (wantsSkinning) {
      final jointAccessor = usable('JOINTS_0', vec4);
      final weightAccessor = usable('WEIGHTS_0', vec4);
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
    //
    // The authored set is decided here, before generation: `tangents == null`
    // is still "the file had none", and after this line every primitive that
    // wanted one has a tangent whether the file did or not.
    final authored = <String>{
      VertexLayout.position.name,
      if (normals != null) VertexLayout.normal.name,
      if (texcoords != null) VertexLayout.texcoord.name,
      if (tangents != null) VertexLayout.tangent.name,
      if (colors != null) VertexLayout.color.name,
      if (joints != null && weights != null) ...<String>[
        VertexLayout.joints.name,
        VertexLayout.weights.name,
      ],
    };
    if (wantsTangent && tangents == null) {
      mesh = mesh.withGeneratedTangents(target: primitiveLayout);
    }

    // Last, because `withGeneratedTangents` returns a fresh mesh and would drop
    // anything attached before it.
    if (targets.isNotEmpty) {
      final morphs = _readMorphTargets(
        label: label,
        targets: targets,
        targetNames: targetNames,
        sourceVertexCount: vertexCount,
        builtVertexCount: mesh.vertexCount,
        split: needsFlatNormals,
        reader: reader,
        warnings: warnings,
      );
      if (morphs.isNotEmpty) mesh = mesh.withMorphTargets(morphs);
    }

    return _DecodedPrimitive(
      mesh: mesh,
      materialIndex: materialIndex,
      authoredAttributes: authored,
    );
  }
}

/// Decodes a primitive's `KHR_draco_mesh_compression` payload and puts its
/// values behind the primitive's own accessors — `gfx-82n`. Returns why it
/// could not, or null.
///
/// **By id, not by order.** The extension maps each attribute *name* to a
/// Draco unique id, and the primitive maps the same name to an accessor; the
/// name is the only thing the two have in common, so that is what joins them.
/// An attribute the primitive lists and the extension does not is left alone
/// — the specification lets an exporter keep some attributes uncompressed,
/// with buffer views of their own.
///
/// **All or nothing.** Every accessor is checked against the decoded mesh
/// before any is given data, so a payload that decodes to the wrong vertex
/// count leaves the primitive exactly as it would be if the payload had not
/// decoded at all, rather than with positions from one source and normals
/// from another.
///
/// A problem comes back as a string, not as an exception, because nothing is
/// exceptional about it: the caller warns and falls back, which is what it
/// did for every compressed primitive before this existed.
String? _supplyDraco({
  required Object? extension,
  required Map<Object?, Object?> attributes,
  required int? indicesAccessor,
  required GltfAccessorReader reader,
}) {
  if (extension is! Map) return 'the extension is not an object';
  final bufferView = _asInt(extension['bufferView']);
  final ids = extension['attributes'];
  if (bufferView == null || ids is! Map) {
    return 'the extension names no bufferView, or no attributes';
  }
  if (indicesAccessor == null) {
    return 'the primitive has no indices accessor for the decoded faces to '
        'go behind';
  }

  try {
    final mesh = decodeDraco(reader.bytesOfBufferView(bufferView));

    final supplies =
        <({int accessor, Float32List? floats, List<int>? integers})>[
          (accessor: indicesAccessor, floats: null, integers: mesh.indices),
          for (final MapEntry(key: name, value: id) in ids.entries)
            if (_asInt(attributes[name]) case final accessor?)
              switch (mesh.attributes[_asInt(id)]) {
                final attribute? => (
                  accessor: accessor,
                  floats: attribute.values,
                  integers: attribute.integers,
                ),
                null => throw FormatException(
                  'the extension maps $name to Draco attribute $id, which the '
                  'payload does not have',
                ),
              },
        ];

    for (final supply in supplies) {
      final declared =
          reader.countOf(supply.accessor) *
          reader.typeOf(supply.accessor).componentCount;
      final decoded = supply.integers?.length ?? supply.floats?.length;
      if (declared != decoded) {
        return 'accessors[${supply.accessor}] declares $declared components '
            'and the payload decodes to $decoded';
      }
    }
    for (final supply in supplies) {
      reader.supplyDecoded(
        supply.accessor,
        floats: supply.floats,
        integers: supply.integers,
      );
    }
    return null;
  } on DracoException catch (error) {
    return error.message;
  } on FormatException catch (error) {
    return error.message;
  }
}

/// Reads a primitive's morph targets, or says why it could not.
///
/// **Only where the built vertices are the file's vertices.** A target is a
/// delta per source vertex, and this loader has one path that changes the
/// count: flat-shading a primitive with no NORMAL splits every shared vertex,
/// three per triangle. Remapping the deltas through that split is possible and
/// is not done, because the case cannot arise for the thing morph targets are
/// for — a face carries normals, and a mesh authored to deform without them is
/// a mesh whose deltas would be blended into flat facets anyway. It warns
/// instead, which is the same shape the old unconditional warning had and now
/// fires for the one case rather than all of them.
List<MorphTarget> _readMorphTargets({
  required String label,
  required List<Object?> targets,
  required List<String> targetNames,
  required int sourceVertexCount,
  required int builtVertexCount,
  required bool split,
  required GltfAccessorReader reader,
  required List<String> warnings,
}) {
  if (split || builtVertexCount != sourceVertexCount) {
    warnings.add(
      '$label has ${targets.length} morph target(s) and was rebuilt with '
      '$builtVertexCount vertices from $sourceVertexCount, so the deltas no '
      'longer line up with the vertices; the base shape is drawn. A primitive '
      'with NORMAL is not rebuilt.',
    );
    return const <MorphTarget>[];
  }

  final read = <MorphTarget>[];
  for (var i = 0; i < targets.length; i++) {
    final target = targets[i];
    if (target is! Map) continue;
    final positionAccessor = _asInt(target['POSITION']);
    if (positionAccessor == null) {
      // glTF allows a target that morphs only normals. Nothing this engine
      // draws is authored that way, and reading one would mean carrying a
      // target with no positions through every layer below.
      warnings.add('$label morph target $i has no POSITION and was skipped.');
      continue;
    }
    if (reader.countOf(positionAccessor) != sourceVertexCount ||
        reader.typeOf(positionAccessor) != GltfAccessorType.vec3) {
      warnings.add(
        '$label morph target $i covers ${reader.countOf(positionAccessor)} '
        '${reader.typeOf(positionAccessor).name} vertices and the primitive '
        'has $sourceVertexCount VEC3; skipped.',
      );
      continue;
    }

    // A target's NORMAL and TANGENT deltas are both VEC3 — a tangent delta
    // has no handedness to move.
    Float32List? deltasOf(String name) {
      final accessor = _asInt(target[name]);
      if (accessor == null) return null;
      if (reader.countOf(accessor) != sourceVertexCount ||
          reader.typeOf(accessor) != GltfAccessorType.vec3) {
        return null;
      }
      return reader.readAsFloats(accessor);
    }

    read.add(
      MorphTarget(
        vertexCount: sourceVertexCount,
        positions: reader.readAsFloats(positionAccessor),
        normals: deltasOf('NORMAL'),
        tangents: deltasOf('TANGENT'),
        name: i < targetNames.length ? targetNames[i] : null,
      ),
    );
  }
  return read;
}

final class _DecodedPrimitive {
  const _DecodedPrimitive({
    required this.mesh,
    required this.materialIndex,
    required this.authoredAttributes,
    this.meshName,
  });

  final MeshData mesh;
  final int? materialIndex;
  final Set<String> authoredAttributes;
  final String? meshName;
}
