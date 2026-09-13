import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';

import '../animation/animation_track.dart';
import '../image_sniff.dart';
import '../meshopt/meshopt_index_codec.dart';
import '../meshopt/meshopt_vertex_codec.dart';
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
  GltfWriter(this.document, {this.compressGeometry = false});

  final ModelDocument document;

  /// `fmt-30n`'s own row: when true, this writer does two independent things
  /// to the geometry on its way into the file.
  ///
  /// **Vertex/triangle order is optimized for a GPU's caches**
  /// (`flutter3d_geometry`'s own `optimizeVertexCache`) before anything else
  /// below reads the mesh: Tom Forsyth's greedy vertex-cache scoring reorders
  /// triangles for the post-transform cache, then vertices are renumbered by
  /// first use for the pre-transform ("fetch") one. The mesh this draws is
  /// unchanged — same triangles, same winding — only which byte offset a
  /// vertex or an index lands at moves, which is why `compareModelDocuments`
  /// needs its own `allowVertexReorder` to keep proving that rather than
  /// reading the move as data loss.
  ///
  /// **`NORMAL`/`TANGENT`/`TEXCOORD_0`/`COLOR_0` are written as normalized
  /// integers** (`KHR_mesh_quantization`) instead of `FLOAT`, whenever an
  /// attribute's own values actually fit the type losslessly enough to
  /// normalize — a quarter to an eighth the bytes per component, real size on
  /// a file whose vertex data is often more attribute bytes than position
  /// bytes.
  ///
  /// **`POSITION` is not quantized.** `KHR_mesh_quantization`'s own normalized
  /// integer only reaches `[-1, 1]`; recovering real coordinates from that
  /// needs a per-mesh dequantization scale baked into the placement of every
  /// node that draws the mesh — correct on its own, and exactly what
  /// `gltfpack` and similar tools do. What blocks it here is `ModelNode`:
  /// `node.surfaces` may list more than one surface (`_writeScene`'s own
  /// multi-primitive mesh), and those surfaces do not all share one
  /// bounding box, so a compensating scale correct for one primitive would
  /// silently misplace every vertex of another primitive sharing that node.
  /// Doing this right needs the node/surface grouping computed before any
  /// mesh is encoded, so a shared node can refuse the compensation rather
  /// than apply the wrong one — real work `EXT_meshopt_compression`'s own
  /// scope note below already explains this row does not have room for
  /// alongside a correct quantizer and a correct reordering pass. Every
  /// attribute that *is* quantized here is one this package's own
  /// `GltfLoader` already reads correctly as-is, because normalized-integer
  /// decoding is already a property of `GltfComponentType.readDouble`, not
  /// something new.
  ///
  /// **`EXT_meshopt_compression` — the actual meshopt bitstream (delta-coded,
  /// byte-transposed blocks, then a byte-oriented entropy coder) — is not
  /// implemented.** No pure-Dart implementation or port exists to depend on
  /// (checked against pub.dev while this row was worked), and nothing in this
  /// repository can decode a real one to check a from-scratch encoder
  /// against — an encoder and decoder written by the same hand, with no
  /// third party to disagree with, can share one mistake and still
  /// round-trip clean through this package's own `GltfLoader` while still
  /// being wrong. `GltfLoader`'s own `extensionsRequired` gate already lets
  /// `KHR_mesh_quantization` through instead, the real, narrower Khronos
  /// extension this row uses in its place.
  final bool compressGeometry;

  /// Whether [compressGeometry] actually quantized anything — some documents
  /// have no attribute whose values fit a normalized integer, and a file that
  /// asked for compression but got none of it should not claim the extension
  /// it never used. Valid only after [writeGlb] has run.
  bool get usedGeometryQuantization => _usedQuantization;
  bool _usedQuantization = false;

  /// Whether [compressGeometry] actually reordered a mesh's triangles and
  /// vertices for GPU cache reuse — false only when every surface's mesh had
  /// no triangles to begin with. Valid only after [writeGlb] has run.
  bool get usedVertexCacheReordering => _usedVertexCacheReordering;
  bool _usedVertexCacheReordering = false;

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
  ///
  /// [byteStride] declares the file's own gap between consecutive vertex
  /// elements when [data] already has one baked in — a quantized `vec3`
  /// `NORMAL` packed 3 signed bytes per vertex is 3, not a multiple of 4, and
  /// the spec requires attribute data aligned to 4 (`ACCESSOR_UNALIGNED`
  /// otherwise, which the official validator does flag). Only meaningful
  /// with `target: 34962`; an index buffer has no per-vertex stride to name.
  int _appendBufferView(TypedData data, {int? target, int? byteStride}) {
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
      'byteStride': ?byteStride,
    });
    return _bufferViews.length - 1;
  }

  int _addAccessor(Map<String, Object?> accessor) {
    _accessors.add(accessor);
    return _accessors.length - 1;
  }

  /// [floats] — [elementCount] `vec3`s, tightly packed — written through
  /// `EXT_meshopt_compression`'s own vertex codec rather than as a plain
  /// `FLOAT` accessor. Only ever called for `POSITION`: it is the one
  /// attribute [_quantizedOrFloatAccessor] leaves untouched (see that
  /// method's own doc comment on why `KHR_mesh_quantization` cannot reach
  /// it), and the one this codec's own compression buys the most on, since
  /// nothing else has quantized it down already.
  int _compressedPositionBufferView(Float32List floats, int elementCount) {
    final raw = floats.buffer.asUint8List(
      floats.offsetInBytes,
      floats.lengthInBytes,
    );
    return _compressedVertexBufferView(
      raw,
      elementCount: elementCount,
      byteStride: 12,
      target: 34962,
    );
  }

  /// [bytes] — [elementCount] elements of [byteStride] bytes each, already
  /// whatever shape the caller wants an accessor to read back (a quantized
  /// normalized integer, in [_GltfWriterMesh._quantizedOrFloatAccessor]'s
  /// own case; a plain float, in [_compressedPositionBufferView]'s) —
  /// written through `EXT_meshopt_compression`'s vertex codec.
  int _compressedVertexBufferView(
    Uint8List bytes, {
    required int elementCount,
    required int byteStride,
    required int target,
  }) {
    final compressed = encodeMeshoptVertexBufferV0(
      bytes,
      elementCount,
      byteStride,
    );
    return _appendCompressedBufferView(
      compressed,
      target: target,
      byteStride: byteStride,
      count: elementCount,
      mode: 'ATTRIBUTES',
    );
  }

  /// [indices] — a flat triangle list — written through
  /// `EXT_meshopt_compression`'s own index codec. [componentSize] is 2 or 4,
  /// the width [indices] itself is already packed at (`ModelSurface.packIndices`'s
  /// own choice), and what this writes back as `byteStride` so a reader
  /// narrows the codec's own always-32-bit output to the same width.
  int _compressedIndexBufferView(List<int> indices, int componentSize) {
    final compressed = encodeMeshoptIndexBuffer(indices);
    return _appendCompressedBufferView(
      compressed,
      target: 34963,
      byteStride: componentSize,
      count: indices.length,
      mode: 'TRIANGLES',
    );
  }

  /// Appends [compressed] bytes as a `bufferViews` entry carrying its own
  /// `EXT_meshopt_compression` extension object, and declares the
  /// extension used and required — there is no uncompressed fallback here,
  /// the same choice `KHR_mesh_quantization` above never has to make since
  /// a plain reader can already read a normalized-integer accessor without
  /// knowing that name.
  ///
  /// The outer `bufferView` points at the same compressed bytes the
  /// extension object does, rather than at a real, separate fallback: a
  /// reader that ignores `extensionsRequired` and reads this view as
  /// ordinary bytes would draw a wrong picture regardless of what the outer
  /// fields name, so there is nothing a real fallback would buy that this
  /// does not already say honestly — the extension is required precisely
  /// because there is no other way to read this view correctly.
  int _appendCompressedBufferView(
    Uint8List compressed, {
    required int target,
    required int byteStride,
    required int count,
    required String mode,
  }) {
    _extensionsUsed.add('EXT_meshopt_compression');
    _extensionsRequired.add('EXT_meshopt_compression');

    while (_binaryLength % 4 != 0) {
      _binary.addByte(0);
      _binaryLength++;
    }
    final byteOffset = _binaryLength;
    _binary.add(compressed);
    _binaryLength += compressed.length;

    _bufferViews.add(<String, Object?>{
      'buffer': 0,
      'byteOffset': byteOffset,
      'byteLength': compressed.length,
      'target': target,
      'extensions': <String, Object?>{
        'EXT_meshopt_compression': <String, Object?>{
          'buffer': 0,
          'byteOffset': byteOffset,
          'byteLength': compressed.length,
          'byteStride': byteStride,
          'count': count,
          'mode': mode,
        },
      },
    });
    return _bufferViews.length - 1;
  }
}
