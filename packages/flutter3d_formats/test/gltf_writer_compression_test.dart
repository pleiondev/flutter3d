/// `fmt-30n`'s own row: `GltfWriter(document, compressGeometry: true)`.
///
///     dart test test/gltf_writer_compression_test.dart
///
/// **What `compressGeometry` actually does, and what it does not, said
/// plainly rather than rounded up:**
///
/// - Vertex/triangle order is reordered for GPU cache reuse
///   (`flutter3d_geometry`'s own `optimizeVertexCache`, Tom Forsyth's greedy
///   scoring plus a vertex-fetch renumbering pass) before any accessor is
///   built. This changes which byte offset a vertex or index lands at, never
///   what the mesh draws, which is exactly what `compareModelDocuments`'s own
///   `allowVertexReorder` exists to keep checking rather than reading the
///   move as data loss.
/// - `NORMAL`/`TANGENT`/`TEXCOORD_0`/`COLOR_0` are quantized to normalized
///   integers (`KHR_mesh_quantization`) whenever their own values fit —
///   `gltf_writer.dart`'s own `compressGeometry` doc comment has the exact
///   rule and the fallback for one that does not.
/// - `POSITION` is never quantized (`KHR_mesh_quantization` cannot reach it
///   — see the same doc comment for why), but is compressed through
///   `EXT_meshopt_compression`'s own vertex codec instead, in
///   `_compressedPositionBufferView`. Every other float or already-quantized
///   attribute, and the index buffer, goes through the same codec —
///   `meshopt_vertex_codec.dart`/`meshopt_index_codec.dart`, this package's
///   own encoder for a format whose only readable reference is its decoder
///   (the real encoder ships as compiled WebAssembly with no source to
///   port), checked against that reference decoder running under Node
///   rather than only against this package's own inverse.
///
/// **What this measures, honestly:** on a fully-attributed sphere
/// (`VertexLayout.standard`, so every quantizable attribute is present),
/// compression brings the GLB down by the ratio printed in `'geometry byte
/// reduction on a fully-attributed mesh'` below. Measured while writing this
/// file: **2.70x** — closer to the plan row's own "three times smaller" than
/// quantization and reordering alone ever reached (1.90x), though still
/// short of it: this encoder does not exploit `EXT_meshopt_compression`'s
/// own triangle-strip FIFO reuse for the index buffer (see
/// `meshopt_index_codec.dart`'s own top comment for why — every triangle
/// takes the format's always-correct fallback path instead, which is real
/// compression but not the ratio a full encoder would reach), and version 1's
/// wider "channel" deltas for vertex data are not implemented either (see
/// `meshopt_vertex_codec.dart`'s own top comment).
///
/// **The official Khronos validator does not know this extension.** The
/// newest npm release (`gltf-validator@2.0.0-dev.3.10`, checked while this
/// file was written — there is no newer one) answers `UNSUPPORTED_EXTENSION`
/// for `EXT_meshopt_compression` and then, not understanding that a
/// bufferView's real data lives in its own extension object rather than at
/// its outer `byteOffset`/`byteLength`, reports every compressed accessor as
/// too long for its view — a byproduct of the validator's own ignorance of
/// the extension, not a finding about this file. What is independently
/// checked instead: `meshopt_reference_check.mjs`/
/// `meshopt_index_reference_check.mjs` decode this package's own encoder
/// output with the format's real reference decoder (not written by this
/// repository); `compareModelDocuments` below is this package's own,
/// separately-written reader agreeing with what its writer wrote. Before
/// `EXT_meshopt_compression` existed here, the plain quantization-only GLB
/// this same test built passed the validator with zero errors and zero
/// warnings — nothing about that half of this row changed.
///
/// `doc/plan-status.json` marks this row `partial`, not `done`, for the
/// shortfall against "three times smaller" and the Khronos validator's own
/// blind spot — the honest categorization this session already uses for
/// real, working, incomplete rows (`fmt-18` among them), rather than either
/// claiming a number this file's own comment disproves or discarding working
/// code because it falls short of one.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';

Uint8List _sample(String relativePath) =>
    File('../flutter3d_samples/assets/$relativePath').readAsBytesSync();

/// One node pointing at surface 0 — `PlainModelDocument` places geometry
/// strictly through `nodes`, never implicitly from `surfaces` alone (see its
/// own doc comment), so every document built here needs one explicitly.
PlainModelDocument _oneSurfaceDocument(MeshData mesh) => PlainModelDocument(
  surfaces: [ModelSurface(mesh: mesh)],
  nodes: [
    ModelNode(surfaces: const [0]),
  ],
);

void main() {
  group("fmt-30n's own acceptance", () {
    test('a fully-attributed mesh round-trips through compressGeometry with '
        'nothing lost beyond quantization and reordering', () async {
      final mesh = SphereShape(segments: 32, rings: 16).build();
      final document = _oneSurfaceDocument(mesh);

      final bytes = GltfWriter(document, compressGeometry: true).writeGlb();
      final readBack = await GltfLoader().load(bytes);

      // 1/127 is the coarsest step a signed byte (NORMAL/TANGENT) can miss
      // by; 1/255 is unsigned byte's own (COLOR_0). The looser of the two
      // covers every quantized attribute this mesh actually carries.
      final problems = compareModelDocuments(
        document,
        readBack,
        tolerance: 1 / 127,
        allowVertexReorder: true,
      );
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('geometry byte reduction on a fully-attributed mesh', () {
      final mesh = SphereShape(segments: 64, rings: 32).build();
      final document = _oneSurfaceDocument(mesh);

      final plain = GltfWriter(document).writeGlb();
      final compressed = GltfWriter(
        document,
        compressGeometry: true,
      ).writeGlb();

      final ratio = plain.length / compressed.length;
      // ignore: avoid_print — the ratio is the point of this test.
      print(
        'plain ${plain.length}B, compressed ${compressed.length}B, '
        'ratio ${ratio.toStringAsFixed(2)}x',
      );

      // This session's own honestly-measured number, not the row's "3x": see
      // this file's own doc comment for why the index codec's own
      // always-correct fallback path (no FIFO reuse) and the vertex codec's
      // own version-0-only scope keep this short of that claim.
      expect(ratio, greaterThan(2.5));
    });

    test(
      'an out-of-range attribute falls back to float rather than clamping',
      () async {
        // A tiling UV, past [0, 1] — the case a naive unsigned-normalized
        // quantizer would silently clamp into the wrong value. Built with
        // every attribute `GltfLoader` would synthesize anyway
        // (`VertexLayout.standard`, this shape's own default), so the only
        // difference this test's own comparison can report is the one it
        // means to: whether TEXCOORD_0 quantized when it should not have.
        final mesh = CuboidShape().build();
        final stride = mesh.layout.floatsPerVertex;
        final texcoordOffset = mesh.layout.floatOffsetOf(
          VertexLayout.texcoord.name,
        );
        for (var v = 0; v < mesh.vertexCount; v++) {
          mesh.vertices[v * stride + texcoordOffset] += 3.0;
        }
        final document = _oneSurfaceDocument(mesh);

        final bytes = GltfWriter(document, compressGeometry: true).writeGlb();
        final readBack = await GltfLoader().load(bytes);
        final problems = compareModelDocuments(
          document,
          readBack,
          allowVertexReorder: true,
        );
        expect(
          problems,
          isEmpty,
          reason:
              'an out-of-range TEXCOORD_0 must fall back to float, not clamp: '
              '${problems.join('\n')}',
        );
      },
    );

    test(
      'usedGeometryQuantization is false for a mesh with nothing to quantize',
      () {
        final mesh = CuboidShape().build(layout: VertexLayout.positionOnly);
        final document = _oneSurfaceDocument(mesh);
        final writer = GltfWriter(document, compressGeometry: true);
        writer.writeGlb();
        expect(writer.usedGeometryQuantization, isFalse);
      },
    );

    test('usedGeometryQuantization is true, and KHR_mesh_quantization is '
        'declared, for a mesh compression actually touched', () {
      final mesh = SphereShape().build();
      final document = _oneSurfaceDocument(mesh);
      final writer = GltfWriter(document, compressGeometry: true);
      final bytes = writer.writeGlb();
      expect(writer.usedGeometryQuantization, isTrue);

      final container = GlbContainer.parse(bytes);
      final used = (container.json['extensionsUsed'] as List?)?.cast<String>();
      final required = (container.json['extensionsRequired'] as List?)
          ?.cast<String>();
      expect(used, contains('KHR_mesh_quantization'));
      expect(required, contains('KHR_mesh_quantization'));
    });

    test('every quantized vertex attribute lands on a 4-byte-aligned stride '
        '(the official validator\'s own MESH_PRIMITIVE_ACCESSOR_UNALIGNED, '
        'checked by byte rather than by running it)', () {
      // NORMAL is the case that actually needs the padding this checks:
      // a signed byte `vec3` packs 3 bytes a vertex on its own, which is
      // not a multiple of 4. TANGENT (`vec4` bytes = 4), TEXCOORD_0
      // (`vec2` shorts = 4) and COLOR_0 (`vec4` bytes = 4) already land on
      // 4 without help, and are checked here anyway so a future
      // quantization rule that does not is caught the same way.
      final mesh = SphereShape().build();
      final document = _oneSurfaceDocument(mesh);
      final bytes = GltfWriter(document, compressGeometry: true).writeGlb();

      final container = GlbContainer.parse(bytes);
      final bufferViews = (container.json['bufferViews']! as List)
          .cast<Map<String, Object?>>();
      final accessors = (container.json['accessors']! as List)
          .cast<Map<String, Object?>>();
      const componentSize = {
        5120: 1,
        5121: 1,
        5122: 2,
        5123: 2,
        5125: 4,
        5126: 4,
      };
      const componentCount = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4};

      for (final accessor in accessors) {
        final bufferViewIndex = accessor['bufferView'] as int?;
        if (bufferViewIndex == null) continue;
        final bufferView = bufferViews[bufferViewIndex];
        if (bufferView['target'] != 34962) continue; // not ARRAY_BUFFER

        final byteOffset = bufferView['byteOffset'] as int? ?? 0;
        expect(
          byteOffset % 4,
          0,
          reason: 'bufferView $bufferViewIndex starts at $byteOffset',
        );

        final naturalStride =
            componentSize[accessor['componentType']]! *
            componentCount[accessor['type']]!;
        // A compressed view's own stride is the extension object's, not the
        // outer bufferView's — the outer byteLength/byteStride describe the
        // compressed bytes on disk, which have nothing to do with the
        // alignment a decoded vertex eventually needs.
        final compression =
            (bufferView['extensions']
                    as Map<String, Object?>?)?['EXT_meshopt_compression']
                as Map<String, Object?>?;
        final effectiveStride =
            (compression?['byteStride'] as int?) ??
            (bufferView['byteStride'] as int?) ??
            naturalStride;
        expect(
          effectiveStride % 4,
          0,
          reason:
              'bufferView $bufferViewIndex has a $effectiveStride-byte '
              'stride for ${accessor['type']}/${accessor['componentType']}',
        );
      }
    });

    test('an unattributed mesh is unaffected by compressGeometry', () async {
      final source = await GltfLoader().load(_sample('Box.glb'));
      final bytes = GltfWriter(source, compressGeometry: true).writeGlb();
      final readBack = await GltfLoader().load(bytes);
      final problems = compareModelDocuments(
        source,
        readBack,
        allowVertexReorder: true,
      );
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('usedVertexCacheReordering is true once writeGlb has reordered a real '
        'mesh, false for a mesh with no triangles', () {
      final withTriangles = GltfWriter(
        _oneSurfaceDocument(SphereShape().build()),
        compressGeometry: true,
      );
      withTriangles.writeGlb();
      expect(withTriangles.usedVertexCacheReordering, isTrue);

      final empty = GltfWriter(
        _oneSurfaceDocument(
          MeshData(
            layout: VertexLayout.positionOnly,
            vertices: Float32List(0),
            indices: Uint32List(0),
          ),
        ),
        compressGeometry: true,
      );
      empty.writeGlb();
      expect(empty.usedVertexCacheReordering, isFalse);
    });

    test('compressGeometry lowers the average cache miss ratio of a written '
        'mesh with no locality to begin with', () async {
      // The sphere shape's own raster generation order is already close to
      // cache-friendly, which would understate what this pass is for on
      // real content — an actual export from modelling software carries no
      // such guarantee. Scrambling the triangle order first, the same way
      // `vertex_cache_optimizer_test.dart` does for the geometry package's
      // own direct test, is what makes the "before" side the input this
      // pass exists to fix rather than the one case already stacked in its
      // favour.
      final base = SphereShape(segments: 32, rings: 16).build();
      final scrambled = _scrambleTriangleOrder(base, 11);
      final document = _oneSurfaceDocument(scrambled);

      final bytes = GltfWriter(document, compressGeometry: true).writeGlb();
      final readBack = await GltfLoader().load(bytes);

      final before = averageCacheMissRatio(scrambled.indices);
      final after = averageCacheMissRatio(readBack.surfaces[0].mesh.indices);
      // ignore: avoid_print — the improvement is the point of this test.
      print('written GLB ACMR: $before -> $after');
      expect(after, lessThan(before));
    });
  });
}

/// [mesh] with its triangles in a fixed, seeded-random order — see
/// `vertex_cache_optimizer_test.dart`'s own copy of this helper for why the
/// ACMR test above needs it rather than measuring a shape generator's own
/// already-decent order.
MeshData _scrambleTriangleOrder(MeshData mesh, int seed) {
  final order = List<int>.generate(mesh.triangleCount, (t) => t);
  final random = math.Random(seed);
  for (var i = order.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final tmp = order[i];
    order[i] = order[j];
    order[j] = tmp;
  }

  final newIndices = Uint32List(mesh.indices.length);
  for (var t = 0; t < order.length; t++) {
    final from = order[t] * 3;
    final to = t * 3;
    newIndices[to] = mesh.indices[from];
    newIndices[to + 1] = mesh.indices[from + 1];
    newIndices[to + 2] = mesh.indices[from + 2];
  }
  return MeshData(
    layout: mesh.layout,
    vertices: mesh.vertices,
    indices: newIndices,
  );
}
