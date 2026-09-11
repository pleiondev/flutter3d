import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';

import '../animation/animation_track.dart';
import '../image_sniff.dart';
import '../model_document.dart';
import 'glb_container.dart';
import 'gltf_accessor.dart';
// For `toGltfFilters`, the exact inverse of `_decodeSampler`'s filter half —
// kept beside the code it undoes rather than duplicated here.
import 'gltf_loader.dart';

// One phase per file, mirroring `gltf_loader.dart`'s own split: geometry,
// scene hierarchy, materials, images. Every phase appends to the single
// binary blob and the flat JSON arrays declared below, so they are `part`s of
// this library rather than files that import it — the same reasoning as the
// loader's own parts.
part 'gltf_writer_animation.dart';
part 'gltf_writer_images.dart';
part 'gltf_writer_lights_cameras.dart';
part 'gltf_writer_materials.dart';
part 'gltf_writer_mesh.dart';
part 'gltf_writer_scene.dart';

/// Serializes any [ModelDocument] into glTF's binary container.
///
/// Takes a [ModelDocument] rather than something engine-specific for the same
/// reason [F3dWriter] does: one writer serves every decoder this package has —
/// glTF, OBJ, `.f3d` — so exporting a model imported from any of them needs no
/// format-specific code at the call site.
///
/// Geometry, materials, skins, animations and morph targets — the whole
/// document, less what nothing here reads: a surface's `flipWinding` is
/// re-derived by any reader from the same node transform this writes, and is
/// not stored twice.
///
/// Everything is embedded in the GLB's own binary chunk — vertex data and
/// image bytes alike — so [writeGlb] always produces one self-contained file,
/// never a `.gltf` with siblings to lose track of.
final class GltfWriter {
  GltfWriter(this.document);

  final ModelDocument document;

  final BytesBuilder _binary = BytesBuilder();
  int _binaryLength = 0;

  final List<Map<String, Object?>> _bufferViews = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _accessors = <Map<String, Object?>>[];

  /// Geometry accessors already written for a [MeshData], keyed by identity —
  /// see `_accessorsFor` in `gltf_writer_mesh.dart`.
  final Map<MeshData, _EncodedMesh> _meshAccessorCache =
      <MeshData, _EncodedMesh>{};

  /// Extension names a material actually used, so `extensionsUsed` lists only
  /// what the file needs rather than every extension this writer knows about.
  final Set<String> _extensionsUsed = <String>{};

  /// The subset of [_extensionsUsed] a reader cannot fall back without —
  /// `fmt-21`'s own `KHR_texture_basisu`, whose texture has no core
  /// `source` to read instead. Every other extension this writer emits
  /// degrades gracefully in a reader that ignores it, so nothing else is
  /// ever added here.
  final Set<String> _extensionsRequired = <String>{};

  /// What [writeGlb] could not carry — `fmt-12`'s own row. Mostly empty:
  /// glTF is the format everything else in this package is measured
  /// against for completeness. The one case this writer knows about is
  /// `fmt-21`'s own: a KTX2 image that is not Basis Universal (its own
  /// `vkFormat` names a real, already-compressed block format rather than
  /// `VK_FORMAT_UNDEFINED`) still gets embedded as the core image — the
  /// best this writer can do for it — but a plain reader has no
  /// `KHR_texture_basisu` transcoder to fall back on either, so it is
  /// warned about rather than silently written as if it were PNG or JPEG.
  List<String> get warnings {
    final nonBasisKtx2 = document.images
        .where(
          (image) =>
              sniffImageMimeType(image.bytes) == 'image/ktx2' &&
              !isKtx2BasisUniversal(image.bytes),
        )
        .length;
    if (nonBasisKtx2 == 0) return const <String>[];
    final message =
        '$nonBasisKtx2 image(s) are KTX2 but not Basis Universal '
        '(vkFormat names a real format, not VK_FORMAT_UNDEFINED); written '
        'as the core image, which core glTF has no room to say is KTX2 at '
        'all';
    return <String>[message];
  }

  /// Encodes the document. The result is a complete `.glb` file.
  Uint8List writeGlb() {
    final (materials, samplers, textures) = _writeMaterials();
    final images = _writeImages();
    final primitives = <Map<String, Object?>>[
      for (var i = 0; i < document.surfaces.length; i++) _primitiveFor(i),
    ];
    final (meshes, nodes, scenes) = _writeScene(primitives);
    final skins = _writeSkins();
    final animations = _writeAnimations();
    final lights = _writeLights();
    final cameras = _writeCameras();

    final json = <String, Object?>{
      'asset': <String, Object?>{
        'version': '2.0',
        if (document.asset?.generator != null)
          'generator': document.asset!.generator,
      },
      // The root document's own `extras`, not `asset`'s — see
      // `GltfLoader.load`'s own comment on the same distinction.
      if (document.asset?.extras != null) 'extras': document.asset!.extras,
      if (_extensionsUsed.isNotEmpty)
        'extensionsUsed': _extensionsUsed.toList(),
      if (_extensionsRequired.isNotEmpty)
        'extensionsRequired': _extensionsRequired.toList(),
      if (lights.isNotEmpty)
        'extensions': <String, Object?>{
          'KHR_lights_punctual': <String, Object?>{'lights': lights},
        },
      if (scenes.isNotEmpty) 'scene': 0,
      if (scenes.isNotEmpty) 'scenes': scenes,
      if (nodes.isNotEmpty) 'nodes': nodes,
      if (meshes.isNotEmpty) 'meshes': meshes,
      if (cameras.isNotEmpty) 'cameras': cameras,
      if (skins.isNotEmpty) 'skins': skins,
      if (animations.isNotEmpty) 'animations': animations,
      if (materials.isNotEmpty) 'materials': materials,
      if (samplers.isNotEmpty) 'samplers': samplers,
      if (textures.isNotEmpty) 'textures': textures,
      if (images.isNotEmpty) 'images': images,
      if (_accessors.isNotEmpty) 'accessors': _accessors,
      if (_bufferViews.isNotEmpty) 'bufferViews': _bufferViews,
      if (_binaryLength > 0)
        'buffers': <Object?>[
          <String, Object?>{'byteLength': _binaryLength},
        ],
    };

    return GlbContainer.encode(
      json,
      binary: _binaryLength > 0 ? _binary.toBytes() : null,
    );
  }

  // ------------------------------------------------------------ binary blob

  /// Appends [data] to the binary chunk at a 4-byte boundary and records a
  /// `bufferViews` entry for it. `target` is glTF's `ARRAY_BUFFER` (34962) or
  /// `ELEMENT_ARRAY_BUFFER` (34963), omitted for data — like images — that a
  /// GPU never binds directly.
  int _appendBufferView(TypedData data, {int? target}) {
    while (_binaryLength % 4 != 0) {
      _binary.addByte(0);
      _binaryLength++;
    }
    final byteOffset = _binaryLength;
    final bytes = Uint8List.sublistView(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    _binary.add(bytes);
    _binaryLength += bytes.length;

    _bufferViews.add(<String, Object?>{
      'buffer': 0,
      'byteOffset': byteOffset,
      'byteLength': bytes.length,
      'target': ?target,
    });
    return _bufferViews.length - 1;
  }

  int _addAccessor(Map<String, Object?> accessor) {
    _accessors.add(accessor);
    return _accessors.length - 1;
  }
}
