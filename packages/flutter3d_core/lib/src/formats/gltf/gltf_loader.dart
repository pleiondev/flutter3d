import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:vector_math/vector_math.dart';

import '../animation/animation_clip.dart';
import '../animation/animation_track.dart';
import '../asset_resolver.dart';
import '../model_document.dart';
import '../model_loader.dart';
import '../texture_transform_bake.dart';
import 'glb_container.dart';
import 'gltf_accessor.dart';
import 'gltf_asset.dart';
import 'gltf_primitive_mode.dart';

export 'gltf_primitive_mode.dart';

part 'gltf_loader_animation.dart';
part 'gltf_loader_images.dart';
part 'gltf_loader_lights_cameras.dart';
part 'gltf_loader_materials.dart';
part 'gltf_loader_mesh.dart';
// This file is the top of the decode pipeline: `load()` and the checks that
// run before it. Each phase below reads glTF JSON that the one before it
// resolved and is split into its own file, but all of them share the private
// JSON helpers at the bottom of this file, so they are `part`s of this
// library rather than files that import it — see each part's doc comment for
// why.
part 'gltf_loader_scene.dart';
part 'gltf_loader_skins.dart';

/// Decodes glTF 2.0 and GLB into engine geometry.
///
/// Scope: geometry, node hierarchy, metal-rough materials, **skinning and
/// animation**. This paragraph said for a long time that the last two were
/// "parsed as far as the node graph but not yet turned into engine data", and
/// two thirds of that had stopped being true: `JOINTS_0`/`WEIGHTS_0` become a
/// `ModelSkin` and the skinned vertex stage, and a channel becomes an
/// `AnimationClip` an `AnimationPlayer` runs.
///
/// **Morph targets are the third**, and this paragraph also used to say they
/// were read past and dropped. A primitive's `targets` become
/// [MeshData.morphTargets], its `extras.targetNames` become their names, and
/// a target with no `POSITION` — legal glTF, meaning "morphs only normals",
/// which nothing here blends — is skipped with a warning through
/// [GltfAsset.warnings] rather than silently, the same channel every other
/// non-fatal gap in this loader already reports through.
///
/// Compressed extensions (`KHR_draco_mesh_compression`, `EXT_meshopt_compression`)
/// are not supported and are reported through [GltfAsset.warnings] rather than
/// throwing, so a file that merely *offers* a compressed variant still loads.
final class GltfLoader implements ModelDecoder {
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

  /// A `.gltf` or `.glb` by name, or a GLB by its `glTF` magic.
  ///
  /// Not a JSON brace with no name: a `.fmat` and a level are JSON too, and a
  /// decoder in an application's own list is asked before anything is sniffed.
  @override
  bool handles(String fileName, Uint8List bytes) {
    final name = fileName.toLowerCase();
    return name.endsWith('.gltf') ||
        name.endsWith('.glb') ||
        (bytes.length >= 4 &&
            bytes[0] == 0x67 &&
            bytes[1] == 0x6C &&
            bytes[2] == 0x54 &&
            bytes[3] == 0x46);
  }

  @override
  Future<ModelDocument> decode(
    Uint8List bytes,
    ModelLoadRequest request,
    AssetUriResolver resolveUri,
  ) => load(bytes, resolveUri: resolveUri);

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
    final lights = _decodeLights(json, warnings);
    final cameras = _decodeCameras(json, warnings);
    final graph = _decodeScene(
      json,
      reader,
      warnings,
      lights.length,
      cameras.length,
    );
    final animations = _decodeAnimations(json, reader, graph.nodes, warnings);
    final skins = _decodeSkins(json, reader, graph.nodes.length, warnings);

    final assetBlock = json['asset'];
    final generator = assetBlock is Map ? assetBlock['generator'] : null;
    // The root document's own `extras`, not `asset`'s — glTF's `asset` object
    // can carry its own `extras` too, a different, narrower thing nothing
    // here reads either, but "extras on the document" (`fmt-19`'s own row)
    // is this one: the top-level object every other key in `json` is a
    // sibling of.
    final documentExtras = _extrasOf(json);

    return GltfAsset(
      surfaces: graph.surfaces,
      materials: materials,
      images: images,
      warnings: warnings,
      nodes: graph.nodes,
      roots: graph.roots,
      animations: animations,
      skins: skins,
      lights: lights,
      cameras: cameras,
      asset: generator is String || documentExtras != null
          ? DocumentAsset(
              generator: generator is String ? generator : null,
              extras: documentExtras,
            )
          : null,
    );
  }

  void _checkRequiredExtensions(Map<String, Object?> json) {
    final required = json['extensionsRequired'];
    if (required is! List) return;

    // Only what something downstream actually reads. `KHR_texture_transform`
    // was on this list and nothing anywhere applied a transform: an
    // atlas-packed model — the export that needs it — passed the gate and
    // then drew every material sampling the whole atlas. A file that requires
    // it is still refused here, because requiring it promises every transform
    // in the file and only some can be kept: one shared by a material's
    // textures is honoured in the coordinates by whoever draws the surface,
    // and textures that disagree are not, which `_decodeMaterials` warns
    // about. A file that merely uses it loads.
    const supported = <String>{
      'KHR_materials_unlit',
      'KHR_materials_emissive_strength',
      // Supported as far as the KTX2 reader goes — Basis ETC1S, and a file's
      // own BC/ETC2/ASTC where the device samples them. A UASTC texture in
      // such a file is refused by name at upload and becomes a warning on the
      // material rather than a refusal of the whole file, since the geometry
      // and every other texture are still worth having.
      'KHR_texture_basisu',
      // `fmt-28`: lights round-trip in full — type, colour, intensity,
      // range, spot angles — so a file naming this as required loses
      // nothing by being let through.
      'KHR_lights_punctual',
      // `fmt-30n`: a normalized integer accessor on NORMAL/TANGENT/
      // TEXCOORD_0/COLOR_0/POSITION was already read correctly before this
      // extension existed — `GltfAccessorReader` applies `normalized` per
      // spec regardless of which attribute it is on, in
      // `GltfComponentType.readDouble`. The extension names a component-type
      // choice this reader already knew how to make, not new behaviour.
      'KHR_mesh_quantization',
      // `fmt-30n`: `GltfAccessorReader._resolveView` decodes
      // `EXT_meshopt_compression`'s own vertex and index bitstreams before
      // an accessor ever reads a byte, so a file naming this as required
      // reads exactly as it would uncompressed.
      'EXT_meshopt_compression',
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

/// [json]'s own `extras`, as an opaque map — `fmt-19`'s own row. Any glTF
/// object may carry one; every phase of this pipeline that decodes one reads
/// it through here, and `gltf_writer.dart`'s own phases write it back
/// unread, which is the whole of what "carried, not interpreted" means.
Map<String, Object?>? _extrasOf(Map<String, Object?> json) {
  final extras = json['extras'];
  return extras is Map ? extras.cast<String, Object?>() : null;
}

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

List<double> _doubleList(Object? value) {
  if (value is! List) return const <double>[];
  return <double>[for (final item in value) ?_asDouble(item)];
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

Vector2? _vec2(Object? value) {
  if (value is! List || value.length < 2) return null;
  return Vector2(_asDouble(value[0]) ?? 0.0, _asDouble(value[1]) ?? 0.0);
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
