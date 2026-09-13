import 'dart:math' as math;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A flat grid of [tileSize] x [tileSize] vertices, [tilesX] by [tilesZ] of
/// them, each tile placed [tileGap] apart so a brush entirely inside one tile
/// can never reach another. `tileSize * tileSize` is [SculptMesh.chunkSize]
/// exactly, so each tile is exactly one chunk of vertex indices — vertices
/// are appended tile by tile, row by row within a tile, so a tile's 1024
/// vertices land in one contiguous, chunk-aligned run of indices, the way a
/// terrain system's per-component vertex buffers naturally would.
///
/// This is what makes the acceptance test below deterministic rather than
/// probabilistic: the point under test is whether `SculptMesh` copies only
/// the chunks a stroke's vertices fall in, not whether a particular vertex
/// numbering happens to have spatial locality — a real caller (a paint tool
/// streaming terrain components, a modeller assembling a mesh region by
/// region) already numbers vertices this way for the same reason a texture
/// atlas keeps a decal's texels contiguous.
EditMesh buildTiledGridMesh({
  required int tilesX,
  required int tilesZ,
  int tileSize = 32,
  double spacing = 1,
  double tileGap = 1000,
}) {
  final points = <Vector3>[];
  final faces = <List<int>>[];
  for (var tz = 0; tz < tilesZ; tz++) {
    for (var tx = 0; tx < tilesX; tx++) {
      final originX = tx * tileGap;
      final originZ = tz * tileGap;
      final base = points.length;
      for (var j = 0; j < tileSize; j++) {
        for (var i = 0; i < tileSize; i++) {
          points.add(Vector3(originX + i * spacing, 0, originZ + j * spacing));
        }
      }
      for (var j = 0; j < tileSize - 1; j++) {
        for (var i = 0; i < tileSize - 1; i++) {
          final a = base + j * tileSize + i;
          final b = base + j * tileSize + i + 1;
          final c = base + (j + 1) * tileSize + i + 1;
          final d = base + (j + 1) * tileSize + i;
          faces.add(<int>[a, b, c, d]);
        }
      }
    }
  }
  return EditMesh.fromFaces(points, faces);
}

/// The same geometry [buildTiledGridMesh] builds, but with every vertex slot
/// index scrambled by a fixed-seed random permutation before it reaches
/// [EditMesh.fromFaces] — the adversarial case `fromEditMesh`'s own doc
/// comment names: an input whose slot order carries no spatial locality at
/// all, the opposite end of the spectrum from the tile-contiguous ordering
/// [buildTiledGridMesh] hands out.
EditMesh buildScrambledTiledGridMesh({
  required int tilesX,
  required int tilesZ,
  int tileSize = 32,
  double spacing = 1,
  double tileGap = 1000,
  int seed = 1234,
}) {
  final points = <Vector3>[];
  final faces = <List<int>>[];
  for (var tz = 0; tz < tilesZ; tz++) {
    for (var tx = 0; tx < tilesX; tx++) {
      final originX = tx * tileGap;
      final originZ = tz * tileGap;
      final base = points.length;
      for (var j = 0; j < tileSize; j++) {
        for (var i = 0; i < tileSize; i++) {
          points.add(Vector3(originX + i * spacing, 0, originZ + j * spacing));
        }
      }
      for (var j = 0; j < tileSize - 1; j++) {
        for (var i = 0; i < tileSize - 1; i++) {
          final a = base + j * tileSize + i;
          final b = base + j * tileSize + i + 1;
          final c = base + (j + 1) * tileSize + i + 1;
          final d = base + (j + 1) * tileSize + i;
          faces.add(<int>[a, b, c, d]);
        }
      }
    }
  }

  final permutation = List<int>.generate(points.length, (i) => i)..shuffle(math.Random(seed));
  final scrambledPoints = List<Vector3>.filled(points.length, Vector3.zero());
  for (var oldIndex = 0; oldIndex < points.length; oldIndex++) {
    scrambledPoints[permutation[oldIndex]] = points[oldIndex];
  }
  final scrambledFaces = <List<int>>[
    for (final face in faces) <int>[for (final v in face) permutation[v]],
  ];
  return EditMesh.fromFaces(scrambledPoints, scrambledFaces);
}

/// A small, irregular grid with a UV assigned per vertex (uniformly on every
/// corner touching it, so there is no seam for the conversion's "first
/// corner wins" rule to disagree with itself over) — for the round-trip and
/// small correctness tests, where a mesh the size of [buildTiledGridMesh]
/// would make the naive/brute-force comparisons slow to write assertions
/// over.
EditMesh buildSmallUvGridMesh({int cols = 4, int rows = 4}) {
  final builder = EditMeshBuilder();
  final vertices = <List<int>>[];
  for (var j = 0; j <= rows; j++) {
    final row = <int>[];
    for (var i = 0; i <= cols; i++) {
      row.add(builder.addVertex(Vector3(i * 1.0, (i * j) * 0.1, j * 1.0)));
    }
    vertices.add(row);
  }
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      builder.addFace(<int>[
        vertices[j][i],
        vertices[j][i + 1],
        vertices[j + 1][i + 1],
        vertices[j + 1][i],
      ]);
    }
  }
  final mesh = builder.build();
  mesh.beginStep();
  for (var f = 0; f < mesh.faceSlotCount; f++) {
    mesh.forEachHalfEdge(f, (int half) {
      final vertex = mesh.originOf(half);
      final j = vertex ~/ (cols + 1);
      final i = vertex % (cols + 1);
      mesh.setUv(half, Vector2(i / cols, j / rows));
    });
  }
  mesh.endStep();
  return mesh;
}

void main() {
  group('SculptMesh chunked copy-on-write acceptance', () {
    test('a brush touching ~1% of vertices copies at most 2% of chunks', () {
      const tilesX = 10;
      const tilesZ = 10;
      const tileSize = 32;
      final editMesh = buildTiledGridMesh(tilesX: tilesX, tilesZ: tilesZ, tileSize: tileSize);
      final sculpt = SculptMesh.fromEditMesh(editMesh);

      final totalVertices = sculpt.vertexCount;
      final totalChunks = sculpt.chunkCount;
      expect(totalVertices, tilesX * tilesZ * tileSize * tileSize);
      expect(totalChunks, tilesX * tilesZ);

      // Snapshot every chunk's backing array by identity before the stroke.
      final before = sculpt.snapshotChunkPositions();

      // Aim the brush at the middle tile: tile (5, 5) of a 10x10 grid. Which
      // chunk index that lands in is no longer `tz * tilesX + tx` — `pro-sc-02`'s
      // own fix sorts vertices by Morton code rather than input order — so
      // this only asserts the tile still lands in exactly one chunk, not
      // which one.
      const targetTx = 5;
      const targetTz = 5;
      const tileGap = 1000.0;
      final centre = Vector3(
        targetTx * tileGap + (tileSize - 1) / 2,
        0,
        targetTz * tileGap + (tileSize - 1) / 2,
      );
      // Big enough to reach every corner of the tile (corner distance is
      // about 21.9 at tileSize=32, spacing=1), small enough to stay far short
      // of the 1000-unit gap to the next tile.
      const radius = 25.0;

      final result = sculpt.applyBrush(
        center: centre,
        radius: radius,
        displace: (int vertex, Vector3 position, double falloff) =>
            position + Vector3(0, falloff, 0),
      );

      // The whole target tile, and nothing else — one chunk, whichever index
      // the Morton sort gave it.
      expect(result.touchedVertices.length, tileSize * tileSize);
      expect(result.touchedChunks, hasLength(1));

      final vertexFraction = result.touchedVertices.length / totalVertices;
      final chunkFraction = result.touchedChunks.length / totalChunks;
      // ignore: avoid_print
      print(
        'brush touched ${result.touchedVertices.length}/$totalVertices vertices '
        '(${(vertexFraction * 100).toStringAsFixed(3)}%) and '
        '${result.touchedChunks.length}/$totalChunks chunks '
        '(${(chunkFraction * 100).toStringAsFixed(3)}%)',
      );

      expect(vertexFraction, closeTo(0.01, 0.005));
      expect(chunkFraction, lessThanOrEqualTo(0.02));

      // Copy-on-write, verified by object identity: the touched chunk got a
      // new array, and every other chunk kept the exact one it started with.
      for (var c = 0; c < totalChunks; c++) {
        final same = identical(before[c], sculpt.chunkPositions(c));
        if (result.touchedChunks.contains(c)) {
          expect(same, isFalse, reason: 'chunk $c was touched and should have been copied');
          expect(sculpt.chunkVersion(c), 1);
        } else {
          expect(same, isTrue, reason: 'chunk $c was not touched and should be untouched');
          expect(sculpt.chunkVersion(c), 0);
        }
      }
      expect(sculpt.dirtyChunks, result.touchedChunks.toSet());
    });

    test('a second, disjoint stroke only ever adds to the dirty set', () {
      final editMesh = buildTiledGridMesh(tilesX: 4, tilesZ: 4, tileSize: 32);
      final sculpt = SculptMesh.fromEditMesh(editMesh);
      const tileGap = 1000.0;

      sculpt.applyBrush(
        center: Vector3(15.5, 0, 15.5),
        radius: 25,
        displace: (_, Vector3 p, double f) => p + Vector3(0, f, 0),
      );
      sculpt.applyBrush(
        center: Vector3(3 * tileGap + 15.5, 0, 3 * tileGap + 15.5),
        radius: 25,
        displace: (_, Vector3 p, double f) => p + Vector3(0, f, 0),
      );

      expect(sculpt.dirtyChunks, <int>{0, 15});
      sculpt.clearDirtyChunks();
      expect(sculpt.dirtyChunks, isEmpty);
    });

    test(
      'pro-sc-02\'s own acceptance: the ≤2% bound holds even when the input '
      'has no spatial locality at all',
      () {
        const tilesX = 10;
        const tilesZ = 10;
        const tileSize = 32;
        final editMesh = buildScrambledTiledGridMesh(
          tilesX: tilesX,
          tilesZ: tilesZ,
          tileSize: tileSize,
        );
        final sculpt = SculptMesh.fromEditMesh(editMesh);

        final totalVertices = sculpt.vertexCount;
        final totalChunks = sculpt.chunkCount;
        expect(totalVertices, tilesX * tilesZ * tileSize * tileSize);
        expect(totalChunks, tilesX * tilesZ);

        // The same physical tile `buildTiledGridMesh`'s own acceptance test
        // targets — scrambling the input's vertex slot order changes nothing
        // about where the geometry actually sits in space.
        const targetTx = 5;
        const targetTz = 5;
        const tileGap = 1000.0;
        final centre = Vector3(
          targetTx * tileGap + (tileSize - 1) / 2,
          0,
          targetTz * tileGap + (tileSize - 1) / 2,
        );
        const radius = 25.0;

        final result = sculpt.applyBrush(
          center: centre,
          radius: radius,
          displace: (int vertex, Vector3 position, double falloff) =>
              position + Vector3(0, falloff, 0),
        );

        final vertexFraction = result.touchedVertices.length / totalVertices;
        final chunkFraction = result.touchedChunks.length / totalChunks;
        // ignore: avoid_print
        print(
          'scrambled input: brush touched ${result.touchedVertices.length}/$totalVertices '
          'vertices (${(vertexFraction * 100).toStringAsFixed(3)}%) and '
          '${result.touchedChunks.length}/$totalChunks chunks '
          '(${(chunkFraction * 100).toStringAsFixed(3)}%)',
        );

        // Without `fromEditMesh`'s own Morton reordering, a stroke this
        // compact over an input with no spatial locality would scatter its
        // touched vertices over nearly every chunk — this is the assertion
        // that fails without the fix `pro-sc-02` asks for.
        expect(result.touchedVertices.length, tileSize * tileSize);
        expect(chunkFraction, lessThanOrEqualTo(0.02));
      },
    );
  });

  group('SculptMesh EditMesh conversion', () {
    test('round trip preserves positions and UVs', () {
      final original = buildSmallUvGridMesh();
      final sculpt = SculptMesh.fromEditMesh(original);
      final roundTripped = sculpt.toEditMesh();

      expect(roundTripped.vertexSlotCount, original.vertexSlotCount);

      // `fromEditMesh` renumbers vertices by Morton code (`pro-sc-02`'s own
      // chunk-touch guarantee needs that), so vertex `v` in `original` is not
      // generally vertex `v` in `roundTripped` any more — a round trip is
      // checked here by matching each vertex back to the original by its own
      // position, which is exactly what "preserves positions and UVs" means
      // without also promising to preserve index order.
      String key(Vector3 p) =>
          '${p.x.toStringAsFixed(6)},${p.y.toStringAsFixed(6)},${p.z.toStringAsFixed(6)}';

      final originalUvByPosition = <String, Vector2>{};
      final originalPositions = <String>{};
      final scratchPosition = Vector3.zero();
      final scratchUv = Vector2.zero();
      for (var v = 0; v < original.vertexSlotCount; v++) {
        if (!original.isVertexAlive(v)) continue;
        original.positionOf(v, scratchPosition);
        originalPositions.add(key(scratchPosition));
      }
      for (var f = 0; f < original.faceSlotCount; f++) {
        if (!original.isFaceAlive(f)) continue;
        original.forEachHalfEdge(f, (int half) {
          final vertex = original.originOf(half);
          original.positionOf(vertex, scratchPosition);
          original.uvOf(half, scratchUv);
          originalUvByPosition[key(scratchPosition)] = scratchUv.clone();
        });
      }

      final roundTrippedPositions = <String>{};
      for (var v = 0; v < roundTripped.vertexSlotCount; v++) {
        if (!roundTripped.isVertexAlive(v)) continue;
        roundTripped.positionOf(v, scratchPosition);
        roundTrippedPositions.add(key(scratchPosition));
      }
      expect(roundTrippedPositions, originalPositions);

      // Every corner of the round-tripped mesh should carry the UV the
      // original had at that same position — true here because the fixture
      // has no seams, so `fromEditMesh`'s "first corner wins" rule always saw
      // the same value.
      for (var f = 0; f < roundTripped.faceSlotCount; f++) {
        if (!roundTripped.isFaceAlive(f)) continue;
        roundTripped.forEachHalfEdge(f, (int half) {
          final vertex = roundTripped.originOf(half);
          roundTripped.positionOf(vertex, scratchPosition);
          roundTripped.uvOf(half, scratchUv);
          final expectedUv = originalUvByPosition[key(scratchPosition)];
          expect(expectedUv, isNotNull, reason: 'no original vertex at $scratchPosition');
          expect(scratchUv.x, closeTo(expectedUv!.x, 1e-9));
          expect(scratchUv.y, closeTo(expectedUv.y, 1e-9));
        });
      }
    });

    test('fromEditMesh skips dead vertices and faces', () {
      final builder = EditMeshBuilder();
      final a = builder.addVertex(Vector3(0, 0, 0));
      final b = builder.addVertex(Vector3(1, 0, 0));
      final c = builder.addVertex(Vector3(0, 1, 0));
      builder.addFace(<int>[a, b, c]);
      final mesh = builder.build();

      mesh.beginStep();
      final orphan = mesh.addVertex(Vector3(9, 9, 9));
      final d = mesh.addVertex(Vector3(1, 1, 0));
      final extraFace = mesh.addFace(<int>[b, d, c]);
      mesh.deleteFace(extraFace);
      mesh.deleteVertex(orphan);
      mesh.deleteVertex(d);
      mesh.endStep();

      final sculpt = SculptMesh.fromEditMesh(mesh);
      expect(sculpt.vertexCount, 3);
      expect(sculpt.triangleCount, 1);
    });
  });

  group('SculptMesh CSR adjacency', () {
    test('matches a naive adjacency map on a small mesh', () {
      final mesh = buildSmallUvGridMesh(cols: 3, rows: 3);
      final sculpt = SculptMesh.fromEditMesh(mesh);

      final naive = List<Set<int>>.generate(sculpt.vertexCount, (_) => <int>{});
      final triangles = sculpt.triangles;
      for (var t = 0; t < triangles.length; t += 3) {
        final a = triangles[t];
        final b = triangles[t + 1];
        final c = triangles[t + 2];
        naive[a].addAll(<int>[b, c]);
        naive[b].addAll(<int>[a, c]);
        naive[c].addAll(<int>[a, b]);
      }

      for (var v = 0; v < sculpt.vertexCount; v++) {
        expect(sculpt.neighborsOf(v).toSet(), naive[v], reason: 'vertex $v');
      }
      expect(sculpt.adjacencyOffsets.length, sculpt.vertexCount + 1);
      expect(sculpt.adjacencyOffsets.last, sculpt.adjacencyNeighbors.length);
    });
  });

  group('SculptMesh spatial grid', () {
    test('radius search matches brute force over the whole mesh', () {
      final mesh = buildSmallUvGridMesh(cols: 6, rows: 6);
      final sculpt = SculptMesh.fromEditMesh(mesh);

      final centre = Vector3(3, 0.2, 3);
      const radius = 2.5;

      final fromGrid = sculpt.verticesWithinRadius(centre, radius).toSet();

      final bruteForce = <int>{};
      final p = Vector3.zero();
      for (var v = 0; v < sculpt.vertexCount; v++) {
        sculpt.positionOf(v, p);
        if ((p - centre).length <= radius) bruteForce.add(v);
      }

      expect(fromGrid, bruteForce);
      expect(fromGrid, isNotEmpty);
      expect(fromGrid.length, lessThan(sculpt.vertexCount));
    });

    test('empty result far from every vertex', () {
      final mesh = buildSmallUvGridMesh(cols: 3, rows: 3);
      final sculpt = SculptMesh.fromEditMesh(mesh);
      expect(sculpt.verticesWithinRadius(Vector3(1000, 1000, 1000), 1), isEmpty);
    });
  });
}
