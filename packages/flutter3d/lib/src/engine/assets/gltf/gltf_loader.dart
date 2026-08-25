import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../../animation/animation.dart';
import '../../geometry/geometry.dart';
import '../asset_resolver.dart';
import '../model_document.dart';
import 'glb_container.dart';
import 'gltf_accessor.dart';
import 'gltf_asset.dart';
import 'gltf_primitive_mode.dart';

export 'gltf_primitive_mode.dart';

// This file is the top of the decode pipeline: `load()` and the checks that
// run before it. Each phase below reads glTF JSON that the one before it
// resolved and is split into its own file, but all of them share the private
// JSON helpers at the bottom of this file, so they are `part`s of this
// library rather than files that import it — see each part's doc comment for
// why.
part 'gltf_loader_scene.dart';
part 'gltf_loader_skins.dart';
part 'gltf_loader_animation.dart';
part 'gltf_loader_mesh.dart';
part 'gltf_loader_materials.dart';
part 'gltf_loader_images.dart';

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
}

// --------------------------------------------------------------- JSON helpers
//
// Shared by every phase above, and the reason they are `part`s of this
// library rather than files that import it: making these public just so
// another file could see them would widen `GltfLoader`'s surface for no
// reader's benefit.

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
