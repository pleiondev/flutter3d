import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../../animation/animation.dart';
import '../../geometry/geometry.dart';
import '../asset_resolver.dart';
import '../model_document.dart';
import 'glb_container.dart';
import 'gltf_accessor.dart';
import 'gltf_asset.dart';

/// glTF primitive topology.
///
/// The conversion to a triangle list lives here rather than as a static helper on
/// the loader: it is entirely determined by the topology, and keeping it on the
/// enum means the switch is exhaustive by construction.
enum GltfPrimitiveMode {
  points(0),
  lines(1),
  lineLoop(2),
  lineStrip(3),
  triangles(4),
  triangleStrip(5),
  triangleFan(6);

  const GltfPrimitiveMode(this.code);

  final int code;

  static GltfPrimitiveMode fromCode(int code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw FormatException('Unknown glTF primitive mode $code.');
  }

  /// Whether this topology produces triangles at all.
  bool get isTriangles =>
      this == triangles || this == triangleStrip || this == triangleFan;

  /// Rewrites the indices as an ordinary triangle list.
  ///
  /// Doing it here keeps the renderer on a single primitive type and avoids a
  /// pipeline permutation per topology, which matters when pipelines are built
  /// ahead of time.
  Uint32List toTriangleList(Uint32List indices) {
    switch (this) {
      case GltfPrimitiveMode.triangles:
        // Trailing indices that do not complete a triangle are dropped.
        final usable = indices.length - (indices.length % 3);
        return usable == indices.length
            ? indices
            : Uint32List.sublistView(indices, 0, usable);

      case GltfPrimitiveMode.triangleStrip:
        if (indices.length < 3) return Uint32List(0);
        final out = Uint32List((indices.length - 2) * 3);
        var w = 0;
        for (var i = 0; i + 2 < indices.length; i++) {
          // Every other triangle is wound backwards; swapping two indices
          // restores a consistent orientation for the whole strip.
          if (i.isEven) {
            out[w++] = indices[i];
            out[w++] = indices[i + 1];
            out[w++] = indices[i + 2];
          } else {
            out[w++] = indices[i + 1];
            out[w++] = indices[i];
            out[w++] = indices[i + 2];
          }
        }
        return out;

      case GltfPrimitiveMode.triangleFan:
        if (indices.length < 3) return Uint32List(0);
        final out = Uint32List((indices.length - 2) * 3);
        var w = 0;
        for (var i = 1; i + 1 < indices.length; i++) {
          out[w++] = indices[0];
          out[w++] = indices[i];
          out[w++] = indices[i + 1];
        }
        return out;

      case GltfPrimitiveMode.points:
      case GltfPrimitiveMode.lines:
      case GltfPrimitiveMode.lineLoop:
      case GltfPrimitiveMode.lineStrip:
        return Uint32List(0);
    }
  }
}

/// Decodes glTF 2.0 and GLB into engine geometry.
///
/// Scope: geometry, node hierarchy and metal-rough materials. Skinning,
/// animation and morph targets are parsed as far as the node graph but not yet
/// turned into engine data — they are the next items in the assets layer.
///
/// Compressed extensions (`KHR_draco_mesh_compression`, `EXT_meshopt_compression`)
/// are not supported and are reported through [GltfAsset.warnings] rather than
/// throwing, so a file that merely *offers* a compressed variant still loads.
final class GltfLoader {
  GltfLoader({
    this.layout = VertexLayout.standard,
    this.skinnedLayout = VertexLayout.skinned,
    this.generateFlatNormalsWhenMissing = true,
  });

  /// Target vertex layout. Attributes the layout does not declare are skipped
  /// during decode instead of being read and thrown away.
  final VertexLayout layout;

  /// Used instead of [layout] for a primitive that carries JOINTS_0 and
  /// WEIGHTS_0.
  ///
  /// Chosen per primitive rather than per file: eight extra floats on every
  /// vertex of a static mesh is a third of its size for nothing, and the
  /// renderer picks its vertex stage from the same fact — a mesh either has
  /// skinning attributes and takes the skinned pipeline, or it does not.

  final VertexLayout skinnedLayout;

  /// glTF says a primitive without NORMAL must be shaded flat. Flat shading
  /// needs per-face normals, which forces the mesh to be de-indexed. Set false
  /// to leave normals at zero instead.
  final bool generateFlatNormalsWhenMissing;

  Future<GltfAsset> load(
    Uint8List bytes, {
    AssetUriResolver? resolveUri,
  }) async {
    final container = GlbContainer.parse(bytes);
    final json = container.json;

    _checkRequiredExtensions(json);

    final buffers = await container.resolveBuffers(resolveUri: resolveUri);
    final reader = GltfAccessorReader(json: json, buffers: buffers);

    final warnings = <String>[];
    final images = await _decodeImages(json, buffers, resolveUri, warnings);
    final materials = _decodeMaterials(json, warnings);
    final graph = _decodeScene(json, reader, warnings);
    final animations = _decodeAnimations(json, reader, graph.nodes, warnings);
    final skins = _decodeSkins(json, reader, graph.nodes.length, warnings);

    return GltfAsset(
      surfaces: graph.surfaces,
      materials: materials,
      images: images,
      warnings: warnings,
      nodes: graph.nodes,
      roots: graph.roots,
      animations: animations,
      skins: skins,
    );
  }

  void _checkRequiredExtensions(Map<String, Object?> json) {
    final required = json['extensionsRequired'];
    if (required is! List) return;

    const supported = <String>{
      'KHR_materials_unlit',
      'KHR_materials_emissive_strength',
      'KHR_texture_transform',
    };
    final unsupported =
        required.whereType<String>().where((e) => !supported.contains(e));
    if (unsupported.isNotEmpty) {
      throw FormatException(
        'This file requires extensions that are not implemented: '
        '${unsupported.join(', ')}. extensionsRequired means the asset cannot '
        'be rendered correctly without them.',
      );
    }
  }

  // ---------------------------------------------------------------- scene walk

  _SceneGraph _decodeScene(
    Map<String, Object?> json,
    GltfAccessorReader reader,
    List<String> warnings,
  ) {
    final nodes = _mapList(json['nodes']);
    final meshes = _mapList(json['meshes']);
    final scenes = _mapList(json['scenes']);

    // `scene` picks the default; if absent, the spec leaves the choice to the
    // viewer and scene 0 is the universal convention.
    final sceneIndex = _asInt(json['scene']) ?? 0;
    List<int> roots;
    if (sceneIndex >= 0 && sceneIndex < scenes.length) {
      roots = _intList(scenes[sceneIndex]['nodes']);
    } else if (scenes.isNotEmpty) {
      roots = _intList(scenes.first['nodes']);
    } else {
      // No scenes at all: draw every mesh-bearing node so the file is not
      // silently empty.
      roots = <int>[for (var i = 0; i < nodes.length; i++) i];
      if (nodes.isNotEmpty) {
        warnings.add('No scenes defined; treating all nodes as roots.');
      }
    }

    // Meshes are decoded once and reused: a node graph may reference the same
    // mesh many times, and re-decoding it per node would multiply both work and
    // memory.
    final meshCache = <int, List<_DecodedPrimitive>>{};
    final instances = <ModelSurface>[];
    final onPath = <int>{};

    // Index-aligned with the glTF `nodes` array, because that is what animation
    // channels address. Every node is kept, including the transform-only ones:
    // those are precisely the ones an animation moves.
    final modelNodes = <ModelNode>[
      for (final node in nodes) _modelNodeFrom(node),
    ];

    void visit(int nodeIndex, Matrix4 parentTransform) {
      if (nodeIndex < 0 || nodeIndex >= nodes.length) {
        warnings.add('Node index $nodeIndex is out of range; skipped.');
        return;
      }
      // A malformed file can make the hierarchy cyclic. Without this the walk
      // recurses until the stack dies.
      if (!onPath.add(nodeIndex)) {
        warnings.add('Node $nodeIndex forms a cycle; subtree skipped.');
        return;
      }

      final node = nodes[nodeIndex];
      final world = parentTransform * _localTransform(node);

      final skinIndex = _asInt(node['skin']);
      final meshIndex = _asInt(node['mesh']);
      if (meshIndex != null && meshIndex >= 0 && meshIndex < meshes.length) {
        final primitives = meshCache.putIfAbsent(
          meshIndex,
          () => _decodeMesh(meshes[meshIndex], meshIndex, reader, warnings),
        );
        // A mirroring transform reverses on-screen winding, so record it here
        // rather than making the renderer recompute the determinant per draw.
        final mirrored = world.determinant() < 0.0;
        final nodeName = node['name'];

        for (final primitive in primitives) {
          modelNodes[nodeIndex].surfaces.add(instances.length);
          instances.add(
            ModelSurface(
              name: nodeName is String ? nodeName : null,
              mesh: primitive.mesh,
              // A skinned surface's vertices are already in the skin's own
              // space, so the node transform must NOT be baked in — the joints
              // place it. Baking it applies the node's placement twice, which
              // looks like a model launched away from its skeleton.
              transform: skinIndex == null
                  ? world.clone()
                  : Matrix4.identity(),
              materialIndex: primitive.materialIndex,
              skinIndex: skinIndex,
              flipWinding: skinIndex == null && mirrored,
            ),
          );
        }
      }

      for (final child in _intList(node['children'])) {
        visit(child, world);
      }
      onPath.remove(nodeIndex);
    }

    for (final root in roots) {
      visit(root, Matrix4.identity());
    }
    return _SceneGraph(
      surfaces: instances,
      nodes: modelNodes,
      roots: roots.where((i) => i >= 0 && i < modelNodes.length).toList(),
    );
  }

  /// One glTF node as a [ModelNode], with its transform kept as TRS.
  ///
  /// A `matrix` node is decomposed, which loses shear — the same trade-off
  /// three.js and Babylon make, and shear in authored assets is vanishingly
  /// rare. TRS is what the scene graph stores and what animation interpolates,
  /// so keeping a matrix here would only move the decomposition later.
  ModelNode _modelNodeFrom(Map<String, Object?> node) {
    final name = node['name'];
    final translation = Vector3.zero();
    final rotation = Quaternion.identity();
    final scale = Vector3(1.0, 1.0, 1.0);

    final matrix = node['matrix'];
    if (matrix is List && matrix.length == 16) {
      _localTransform(node).decompose(translation, rotation, scale);
    } else {
      final t = _vec3(node['translation']);
      if (t != null) translation.setFrom(t);
      final s = _vec3(node['scale']);
      if (s != null) scale.setFrom(s);
      final r = node['rotation'];
      if (r is List && r.length == 4) {
        rotation
          ..setValues(
            _asDouble(r[0]) ?? 0.0,
            _asDouble(r[1]) ?? 0.0,
            _asDouble(r[2]) ?? 0.0,
            _asDouble(r[3]) ?? 1.0,
          )
          ..normalize();
      }
    }

    return ModelNode(
      name: name is String ? name : null,
      translation: translation,
      rotation: rotation,
      scale: scale,
      children: _intList(node['children']),
    );
  }

  // -------------------------------------------------------------------- skins

  /// Decodes `skins` into engine skeletons.
  ///
  /// Joints are node indices, which is what makes skinning and animation
  /// independent: the player writes node transforms and the skin reads them, so
  /// neither feature has to know the other exists.
  List<ModelSkin> _decodeSkins(
    Map<String, Object?> json,
    GltfAccessorReader reader,
    int nodeCount,
    List<String> warnings,
  ) {
    final skins = _mapList(json['skins']);
    if (skins.isEmpty) return const <ModelSkin>[];

    final result = <ModelSkin>[];
    for (var i = 0; i < skins.length; i++) {
      final skin = skins[i];
      final label = 'skins[$i]';
      final joints = _intList(skin['joints']);

      if (joints.isEmpty) {
        warnings.add('$label has no joints; skipped.');
        continue;
      }
      final outOfRange = joints.where((j) => j < 0 || j >= nodeCount);
      if (outOfRange.isNotEmpty) {
        warnings.add(
          '$label names joints ${outOfRange.join(', ')}, which are not nodes; '
          'skipped.',
        );
        continue;
      }

      // The spec allows the matrices to be absent, meaning every one is
      // identity — a skeleton already at the origin in bind pose.
      final accessor = _asInt(skin['inverseBindMatrices']);
      final matrices = <Matrix4>[];
      if (accessor == null) {
        for (var j = 0; j < joints.length; j++) {
          matrices.add(Matrix4.identity());
        }
      } else {
        final floats = reader.readAsFloats(accessor);
        if (floats.length < joints.length * 16) {
          warnings.add(
            '$label has ${joints.length} joints but only '
            '${floats.length ~/ 16} inverse bind matrices; skipped.',
          );
          continue;
        }
        for (var j = 0; j < joints.length; j++) {
          // Column-major in the file and column-major in vector_math, so the
          // sixteen floats go straight in.
          final storage = Float32List(16);
          for (var e = 0; e < 16; e++) {
            storage[e] = floats[j * 16 + e];
          }
          matrices.add(Matrix4.fromFloat32List(storage));
        }
      }

      final skeleton = _asInt(skin['skeleton']);
      final name = skin['name'];
      result.add(
        ModelSkin(
          name: name is String ? name : null,
          joints: joints,
          inverseBindMatrices: matrices,
          skeletonRoot:
              skeleton != null && skeleton >= 0 && skeleton < nodeCount
                  ? skeleton
                  : null,
        ),
      );
    }
    return result;
  }

  // ---------------------------------------------------------------- animation

  /// Decodes `animations` into engine clips.
  ///
  /// Channels are grouped per clip and addressed by node index, which is why the
  /// node array above is kept index-aligned with glTF's rather than compacted to
  /// the nodes that happen to draw something.
  List<AnimationClip> _decodeAnimations(
    Map<String, Object?> json,
    GltfAccessorReader reader,
    List<ModelNode> nodes,
    List<String> warnings,
  ) {
    final animations = _mapList(json['animations']);
    if (animations.isEmpty) return const <AnimationClip>[];

    final clips = <AnimationClip>[];
    for (var a = 0; a < animations.length; a++) {
      final animation = animations[a];
      final label = 'animations[$a]';
      final samplers = _mapList(animation['samplers']);
      final channels = _mapList(animation['channels']);
      final tracks = <AnimationTrack>[];

      for (var c = 0; c < channels.length; c++) {
        final channel = channels[c];
        final channelLabel = '$label.channels[$c]';

        final target = channel['target'];
        if (target is! Map) {
          warnings.add('$channelLabel has no target; skipped.');
          continue;
        }
        final nodeIndex = _asInt(target['node']);
        if (nodeIndex == null) {
          // A channel with no node is legal and means "do nothing", which the
          // spec allows so that a clip can be authored before its target is.
          continue;
        }
        if (nodeIndex < 0 || nodeIndex >= nodes.length) {
          warnings.add('$channelLabel targets node $nodeIndex, which does not '
              'exist; skipped.');
          continue;
        }

        final pathName = target['path'];
        final path =
            AnimationPath.fromGltf(pathName is String ? pathName : null);
        if (path == null) {
          warnings.add('$channelLabel targets unknown path "$pathName"; '
              'skipped.');
          continue;
        }

        final samplerIndex = _asInt(channel['sampler']);
        if (samplerIndex == null ||
            samplerIndex < 0 ||
            samplerIndex >= samplers.length) {
          warnings.add('$channelLabel references sampler $samplerIndex, which '
              'does not exist; skipped.');
          continue;
        }
        final sampler = samplers[samplerIndex];

        final inputAccessor = _asInt(sampler['input']);
        final outputAccessor = _asInt(sampler['output']);
        if (inputAccessor == null || outputAccessor == null) {
          warnings.add('$label.samplers[$samplerIndex] is missing input or '
              'output; skipped.');
          continue;
        }

        final interpolationName = sampler['interpolation'];
        final interpolation = AnimationInterpolation.fromGltf(
          interpolationName is String ? interpolationName : null,
        );

        final Float32List times;
        final Float32List values;
        try {
          times = reader.readAsFloats(inputAccessor);
          values = reader.readAsFloats(outputAccessor);
        } on FormatException catch (error) {
          warnings.add('$channelLabel could not be read: ${error.message}');
          continue;
        }

        if (times.isEmpty) {
          warnings.add('$channelLabel has no keyframes; skipped.');
          continue;
        }

        // Weight tracks carry one value per morph target, and only the value
        // count knows how many that is.
        final perKey = interpolation.valuesPerKey;
        final componentCount = path == AnimationPath.weights
            ? values.length ~/ (times.length * perKey)
            : path.componentCount;

        if (componentCount <= 0 ||
            values.length != times.length * componentCount * perKey) {
          warnings.add(
            '$channelLabel has ${times.length} keys but ${values.length} '
            'values, which does not divide into ${interpolation.name} '
            '${path.name} keyframes; skipped.',
          );
          continue;
        }

        if (path == AnimationPath.weights) {
          warnings.add('$channelLabel animates morph target weights, which are '
              'decoded but not applied.');
        }

        tracks.add(
          AnimationTrack(
            nodeIndex: nodeIndex,
            path: path,
            interpolation: interpolation,
            times: times,
            values: values,
            componentCount: componentCount,
          ),
        );
      }

      if (tracks.isEmpty) {
        warnings.add('$label has no usable channels; skipped.');
        continue;
      }

      final name = animation['name'];
      clips.add(
        AnimationClip(
          name: name is String ? name : 'animation $a',
          tracks: tracks,
        ),
      );
    }

    return clips;
  }

  /// Node-local transform: either an explicit matrix or a TRS triple, never
  /// both per the spec.
  Matrix4 _localTransform(Map<String, Object?> node) {
    final matrix = node['matrix'];
    if (matrix is List && matrix.length == 16) {
      // glTF stores matrices column-major, which is also vector_math's storage
      // order, so the values go straight in.
      final storage = Float32List(16);
      for (var i = 0; i < 16; i++) {
        storage[i] = _asDouble(matrix[i]) ?? 0.0;
      }
      return Matrix4.fromFloat32List(storage);
    }

    final translation = _vec3(node['translation']) ?? Vector3.zero();
    final scale = _vec3(node['scale']) ?? Vector3(1.0, 1.0, 1.0);
    final rotationList = node['rotation'];
    // glTF quaternions are stored xyzw; Quaternion(x, y, z, w) matches.
    final rotation = rotationList is List && rotationList.length == 4
        ? Quaternion(
            _asDouble(rotationList[0]) ?? 0.0,
            _asDouble(rotationList[1]) ?? 0.0,
            _asDouble(rotationList[2]) ?? 0.0,
            _asDouble(rotationList[3]) ?? 1.0,
          )
        : Quaternion.identity();

    return Matrix4.compose(translation, rotation.normalized(), scale);
  }

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
        final extensions = (primitive['extensions'] as Map).keys;
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
    final hasSkinAttributes = attributes['JOINTS_0'] != null &&
        attributes['WEIGHTS_0'] != null;
    final primitiveLayout =
        hasSkinAttributes && skinnedLayout.isSkinned ? skinnedLayout : layout;

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

  // ---------------------------------------------------------------- materials

  List<SurfaceMaterial> _decodeMaterials(
    Map<String, Object?> json,
    List<String> warnings,
  ) {
    final materials = _mapList(json['materials']);
    final textures = _mapList(json['textures']);
    final samplers = _mapList(json['samplers']);

    TextureBinding? textureRef(Object? value) {
      if (value is! Map) return null;
      final textureIndex = _asInt(value['index']);
      if (textureIndex == null ||
          textureIndex < 0 ||
          textureIndex >= textures.length) {
        return null;
      }
      final texture = textures[textureIndex];
      final imageIndex = _asInt(texture['source']);
      if (imageIndex == null) {
        // A texture may carry only an extension-provided source (e.g. KTX2),
        // which we do not decode.
        warnings.add(
          'textures[$textureIndex] has no core "source" image; ignored.',
        );
        return null;
      }

      final samplerIndex = _asInt(texture['sampler']);
      final sampler = samplerIndex != null &&
              samplerIndex >= 0 &&
              samplerIndex < samplers.length
          ? _decodeSampler(samplers[samplerIndex])
          : const TextureSampling();

      final texCoord = _asInt(value['texCoord']) ?? 0;
      if (texCoord != 0) {
        warnings.add(
          'A texture uses TEXCOORD_$texCoord; only set 0 is decoded.',
        );
      }

      return TextureBinding(
        imageIndex: imageIndex,
        texCoordSet: texCoord,
        sampling: sampler,
      );
    }

    return <SurfaceMaterial>[
      for (final material in materials)
        () {
          final pbr = material['pbrMetallicRoughness'];
          final pbrMap =
              pbr is Map ? pbr.cast<String, Object?>() : <String, Object?>{};
          final extensions = material['extensions'];
          final extensionsMap = extensions is Map
              ? extensions.cast<String, Object?>()
              : <String, Object?>{};

          final emissiveStrengthExt =
              extensionsMap['KHR_materials_emissive_strength'];
          final normalTex = material['normalTexture'];
          final occlusionTex = material['occlusionTexture'];

          final name = material['name'];
          final alphaMode = material['alphaMode'];

          return SurfaceMaterial(
            name: name is String ? name : null,
            baseColor: _vec4(pbrMap['baseColorFactor']),
            metallic: _asDouble(pbrMap['metallicFactor']) ?? 1.0,
            roughness: _asDouble(pbrMap['roughnessFactor']) ?? 1.0,
            baseColorTexture: textureRef(pbrMap['baseColorTexture']),
            metallicRoughnessTexture:
                textureRef(pbrMap['metallicRoughnessTexture']),
            normalTexture: textureRef(normalTex),
            normalScale: normalTex is Map
                ? (_asDouble(normalTex['scale']) ?? 1.0)
                : 1.0,
            occlusionTexture: textureRef(occlusionTex),
            occlusionStrength: occlusionTex is Map
                ? (_asDouble(occlusionTex['strength']) ?? 1.0)
                : 1.0,
            emissiveTexture: textureRef(material['emissiveTexture']),
            emissive: _vec3(material['emissiveFactor']),
            emissiveStrength: emissiveStrengthExt is Map
                ? (_asDouble(emissiveStrengthExt['emissiveStrength']) ?? 1.0)
                : 1.0,
            alphaMode: switch (alphaMode) {
              'MASK' => SurfaceAlphaMode.mask,
              'BLEND' => SurfaceAlphaMode.blend,
              _ => SurfaceAlphaMode.opaque,
            },
            alphaCutoff: _asDouble(material['alphaCutoff']) ?? 0.5,
            doubleSided: material['doubleSided'] == true,
            unlit: extensionsMap.containsKey('KHR_materials_unlit'),
          );
        }(),
    ];
  }

  static TextureSampling _decodeSampler(Map<String, Object?> sampler) {
    // Filter codes: 9728 NEAREST, 9729 LINEAR, plus the four mipmap variants.
    final magFilter = _asInt(sampler['magFilter']);
    final minFilter = _asInt(sampler['minFilter']);

    TextureWrap wrap(Object? code) => switch (_asInt(code)) {
          33071 => TextureWrap.clampToEdge,
          33648 => TextureWrap.mirroredRepeat,
          _ => TextureWrap.repeat,
        };

    return TextureSampling(
      magLinear: magFilter != 9728,
      minLinear: minFilter != 9728 && minFilter != 9984 && minFilter != 9986,
      useMipmaps: minFilter == null || minFilter >= 9984,
      wrapS: wrap(sampler['wrapS']),
      wrapT: wrap(sampler['wrapT']),
    );
  }

  // ------------------------------------------------------------------- images

  Future<List<EncodedImage>> _decodeImages(
    Map<String, Object?> json,
    List<Uint8List> buffers,
    AssetUriResolver? resolveUri,
    List<String> warnings,
  ) async {
    final images = _mapList(json['images']);
    final bufferViews = _mapList(json['bufferViews']);
    final result = <EncodedImage>[];

    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      final name = image['name'];
      final mimeType = image['mimeType'];
      final uri = image['uri'];
      final bufferViewIndex = _asInt(image['bufferView']);

      Uint8List? bytes;
      if (uri is String) {
        if (uri.startsWith('data:')) {
          bytes = decodeDataUri(uri);
        } else if (resolveUri != null) {
          try {
            bytes = await resolveUri(uri);
          } catch (error) {
            warnings.add('images[$i] could not load "$uri": $error');
          }
        } else {
          warnings.add(
            'images[$i] points at "$uri" but no URI resolver was supplied.',
          );
        }
      } else if (bufferViewIndex != null &&
          bufferViewIndex >= 0 &&
          bufferViewIndex < bufferViews.length) {
        final view = bufferViews[bufferViewIndex];
        final bufferIndex = _asInt(view['buffer']) ?? 0;
        if (bufferIndex < buffers.length) {
          final offset = _asInt(view['byteOffset']) ?? 0;
          final length = _asInt(view['byteLength']) ?? 0;
          final buffer = buffers[bufferIndex];
          if (offset + length <= buffer.length) {
            bytes = Uint8List.sublistView(buffer, offset, offset + length);
          } else {
            warnings.add('images[$i] bufferView is out of range.');
          }
        }
      } else {
        warnings.add('images[$i] has neither uri nor bufferView.');
      }

      result.add(
        EncodedImage(
          name: name is String ? name : null,
          bytes: bytes ?? Uint8List(0),
          mimeType: mimeType is String ? mimeType : null,
        ),
      );
    }

    return result;
  }
}

final class _DecodedPrimitive {
  const _DecodedPrimitive({required this.mesh, required this.materialIndex});

  final MeshData mesh;
  final int? materialIndex;
}

/// The scene walk's two outputs: the flattened surfaces and the hierarchy they
/// came from.
final class _SceneGraph {
  const _SceneGraph({
    required this.surfaces,
    required this.nodes,
    required this.roots,
  });

  final List<ModelSurface> surfaces;

  /// Index-aligned with the file's `nodes` array.
  final List<ModelNode> nodes;

  final List<int> roots;
}

// --------------------------------------------------------------- JSON helpers

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final item in value)
      if (item is Map) item.cast<String, Object?>() else <String, Object?>{},
  ];
}

List<int> _intList(Object? value) {
  if (value is! List) return const <int>[];
  return <int>[
    for (final item in value) ?_asInt(item),
  ];
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  return null;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return null;
}

Vector3? _vec3(Object? value) {
  if (value is! List || value.length < 3) return null;
  return Vector3(
    _asDouble(value[0]) ?? 0.0,
    _asDouble(value[1]) ?? 0.0,
    _asDouble(value[2]) ?? 0.0,
  );
}

Vector4? _vec4(Object? value) {
  if (value is! List || value.length < 4) return null;
  return Vector4(
    _asDouble(value[0]) ?? 0.0,
    _asDouble(value[1]) ?? 0.0,
    _asDouble(value[2]) ?? 0.0,
    _asDouble(value[3]) ?? 0.0,
  );
}
