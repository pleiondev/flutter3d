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
/// Scope: geometry, node hierarchy, metal-rough materials, **skinning and
/// animation**. This paragraph said for a long time that the last two were
/// "parsed as far as the node graph but not yet turned into engine data", and
/// two thirds of that had stopped being true: `JOINTS_0`/`WEIGHTS_0` become a
/// `ModelSkin` and the skinned vertex stage, and a channel becomes an
/// `AnimationClip` an `AnimationPlayer` runs.
///
/// **Morph targets are the third**, and are genuinely absent: a primitive's
/// `targets` are read past, so a mesh with them loads its base shape and is
/// drawn unmoved. That is reported through [GltfAsset.warnings] like every
/// other non-fatal gap — it was not, and a model that loaded "fine" and simply
/// never changed shape is the sort of thing somebody chases in the wrong file.
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

    // Only what something downstream actually reads. `KHR_texture_transform`
    // was on this list and nothing anywhere applied a transform: an
    // atlas-packed model — the export that needs it — passed the gate and
    // then drew every material sampling the whole atlas. A file that requires
    // it is refused here, and one that merely uses it gets a warning where
    // its texture is read, in `_decodeMaterials`.
    const supported = <String>{
      'KHR_materials_unlit',
      'KHR_materials_emissive_strength',
      // Supported as far as the KTX2 reader goes — Basis ETC1S, and a file's
      // own BC/ETC2/ASTC where the device samples them. A UASTC texture in
      // such a file is refused by name at upload and becomes a warning on the
      // material rather than a refusal of the whole file, since the geometry
      // and every other texture are still worth having.
      'KHR_texture_basisu',
    };
    final unsupported = required.whereType<String>().where(
      (e) => !supported.contains(e),
    );
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
  return <int>[for (final item in value) ?_asInt(item)];
}

/// The image a texture's `KHR_texture_basisu` extension names, or null when
/// it names none. [warnings] hears about an extension block that is there
/// and malformed, which is a different thing from one that is absent.
int? _basisuSource(Map<String, Object?> texture, List<String> warnings) {
  final extensions = texture['extensions'];
  if (extensions is! Map) return null;
  final basisu = extensions['KHR_texture_basisu'];
  if (basisu == null) return null;
  if (basisu is! Map) {
    warnings.add('a texture\'s KHR_texture_basisu is not an object; ignored.');
    return null;
  }
  return _asInt(basisu['source']);
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
