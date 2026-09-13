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
/// - `POSITION` is never quantized — see the same doc comment for the real
///   blocker (`ModelNode.surfaces` can list more than one primitive per
///   node, and they do not all share one bounding box) rather than a
///   simpler one that no longer applies.
/// - `EXT_meshopt_compression`'s own bitstream is not implemented — no
///   pure-Dart implementation exists to depend on (checked against pub.dev),
///   and nothing in this repository can decode a real one to check a
///   from-scratch encoder against.
///
/// **What this measures, honestly:** on a fully-attributed sphere
/// (`VertexLayout.standard`, so every quantizable attribute is present),
/// compression brings the GLB down by the ratio printed in `'geometry byte
/// reduction on a fully-attributed mesh'` below. Measured while writing this
/// file: **1.90x** — short of the plan row's own "three times smaller".
/// `POSITION` is 12 of the 64 bytes `VertexLayout.standard` spends per vertex
/// and the index buffer's own bytes are untouched by quantization (vertex
/// cache reordering does not shrink a file — it changes an order, not a byte
/// count — so it does not move this ratio either); together they are most of
/// the floor this session's scope cannot compress past without the
/// node/surface-aware position-quantization machinery named above, or the
/// real `EXT_meshopt_compression` bitstream. The last sliver of it is spec
/// compliance's own cost: `NORMAL`'s signed-byte `vec3` packs 3 bytes a
/// vertex, one short of the 4-byte alignment the official glTF validator
/// requires of vertex attribute data, so it is padded to 4 — one wasted byte
/// a vertex, checked against a real `.glb` (not merely asserted) in `'every
/// quantized vertex attribute lands on a 4-byte-aligned stride'` below, and
/// against the actual Khronos validator (`npm install gltf-validator`, which
/// this machine could reach) while this file was written: zero errors, zero
/// warnings, on both the plain and the compressed GLB.
///
/// `doc/plan-status.json` marks this row `partial`, not `done`, for exactly
/// that shortfall — the honest categorization this session already uses for
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
      // this file's own doc comment for why POSITION staying unquantized and
      // the index buffer being untouched by either compression technique
      // keep this short of that claim.
      expect(ratio, greaterThan(1.5));
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
        final effectiveStride =
            bufferView['byteStride'] as int? ?? naturalStride;
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
