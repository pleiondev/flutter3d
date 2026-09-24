/// A splat tree drawn under a budget, and paged in as the cut asks — `C7`.
///
///     dart test test/engine/splat_lod_test.dart
///
/// The two properties the item promises are held on random clouds from many
/// eyes: a cut never holds more splats than its budget, and a budget that
/// covers the cloud gets the cloud itself back — the original splats, none
/// merged. The merge is held to the arithmetic it claims (the moment-matched
/// mean and covariance), the file to a round trip, and the paging to reading
/// less of the file for a small budget than for a large one.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

SplatCloud _randomCloud(int n, int seed) {
  final random = math.Random(seed);
  double r(double lo, double hi) => lo + (hi - lo) * random.nextDouble();
  final rotations = Float32List(n * 4);
  for (var i = 0; i < n; i++) {
    final q = Quaternion(r(-1, 1), r(-1, 1), r(-1, 1), r(-1, 1))..normalize();
    rotations.setAll(i * 4, <double>[q.x, q.y, q.z, q.w]);
  }
  return SplatCloud(
    // Clustered, as a capture is: most splats on a few surfaces.
    centres: Float32List.fromList(<double>[
      for (var i = 0; i < n; i++) ...<double>[
        r(-10, 10) * (i.isEven ? 1 : 0.1),
        r(-2, 2),
        r(-10, 10),
      ],
    ]),
    colours: Float32List.fromList(<double>[
      for (var i = 0; i < n * 4; i++) r(0, 1),
    ]),
    scales: Float32List.fromList(<double>[
      for (var i = 0; i < n * 3; i++) r(0.01, 0.2),
    ]),
    rotations: rotations,
  );
}

/// Every splat of [cloud] as a sortable key, so two clouds can be compared
/// as sets whatever order they were assembled in.
List<String> _keys(SplatCloud cloud) => <String>[
  for (var i = 0; i < cloud.count; i++)
    <double>[
      for (var k = 0; k < 3; k++) cloud.centres[i * 3 + k],
      for (var k = 0; k < 4; k++) cloud.colours[i * 4 + k],
      for (var k = 0; k < 3; k++) cloud.scales[i * 3 + k],
    ].join(','),
]..sort();

void main() {
  group('the cut', () {
    final cloud = _randomCloud(6000, 7);
    final tree = buildSplatOctree(cloud, leafCapacity: 128, grid: 4);
    final eyes = <Vector3>[
      Vector3(0, 0, 30),
      Vector3(12, 3, 0),
      Vector3(0, 0, 0),
      Vector3(-4, 40, -4),
    ];

    test('never exceeds its budget and converges to the full cloud as the '
        'budget grows', () {
      expect(tree.leafSplatCount, cloud.count);
      expect(tree.nodes.first.splatCount, lessThanOrEqualTo(64));
      for (final eye in eyes) {
        var previous = 0;
        for (final budget in <int>[64, 100, 300, 1000, 2500, 5999, 6000]) {
          final lod = SplatLod(tree, budget: budget);
          final drawn = lod.choose(eye);
          expect(drawn.count, lod.cutSplatCount);
          expect(drawn.count, lessThanOrEqualTo(budget), reason: '$eye');
          expect(drawn.count, greaterThanOrEqualTo(previous));
          previous = drawn.count;
        }
        final full = SplatLod(tree, budget: 1 << 30).choose(eye);
        expect(_keys(full), _keys(cloud), reason: 'at $eye');
      }
    });

    test('a cut covers every leaf exactly once', () {
      final lod = SplatLod(tree, budget: 700)..choose(eyes.first);
      final covered = List<int>.filled(tree.nodes.length, 0);
      void cover(int index) {
        covered[index]++;
        final node = tree.nodes[index];
        for (var c = 0; c < node.childCount; c++) {
          cover(node.firstChild + c);
        }
      }

      lod.cut.forEach(cover);
      for (final (k, node) in tree.nodes.indexed) {
        if (node.isLeaf) expect(covered[k], 1, reason: 'leaf $k');
      }
    });

    test('spends its budget near the eye', () {
      // The same budget from two sides of the cloud: the half nearer the eye
      // gets the finer splats, so more of them.
      int nearSide(Vector3 eye) {
        final drawn = SplatLod(tree, budget: 800).choose(eye);
        var near = 0;
        for (var i = 0; i < drawn.count; i++) {
          if ((drawn.centres[i * 3 + 2] > 0) == (eye.z > 0)) near++;
        }
        return near;
      }

      final front = nearSide(Vector3(0, 0, 25));
      final back = nearSide(Vector3(0, 0, -25));
      expect(front, greaterThan(400));
      expect(back, greaterThan(400));
    });

    test('a budget below the root draws nothing rather than too much', () {
      final lod = SplatLod(tree, budget: tree.nodes.first.splatCount - 1);
      expect(lod.choose(eyes.first).count, 0);
    });
  });

  group('the merge', () {
    test('a lone splat merges into itself', () {
      final one = _randomCloud(1, 3);
      final merged = mergeSplats(
        <SplatCloud>[one],
        centre: Vector3.zero(),
        half: 20,
        grid: 4,
      );
      expect(merged.count, 1);
      final a = Float32List(6), b = Float32List(6);
      one.covarianceOf(0, a);
      merged.covarianceOf(0, b);
      for (var k = 0; k < 6; k++) {
        expect(b[k], closeTo(a[k], 1e-6));
      }
      for (var k = 0; k < 4; k++) {
        expect(merged.colours[k], closeTo(one.colours[k], 1e-6));
      }
    });

    test('many splats merge into their weighted mean and covariance', () {
      final cloud = _randomCloud(40, 11);
      final merged = mergeSplats(
        <SplatCloud>[cloud],
        centre: Vector3.zero(),
        half: 20,
        grid: 1,
      );
      expect(merged.count, 1);

      // The moment match, worked out here directly.
      final covariance = Float32List(6);
      var total = 0.0;
      final mean = Float64List(3);
      final second = Float64List(6);
      for (var i = 0; i < cloud.count; i++) {
        final s = cloud.scales;
        final w =
            cloud.colours[i * 4 + 3] *
            math.pow(s[i * 3] * s[i * 3 + 1] * s[i * 3 + 2], 2 / 3);
        final p = <double>[
          for (var k = 0; k < 3; k++) cloud.centres[i * 3 + k],
        ];
        cloud.covarianceOf(i, covariance);
        total += w;
        for (var k = 0; k < 3; k++) {
          mean[k] += w * p[k];
        }
        var at = 0;
        for (var r = 0; r < 3; r++) {
          for (var c = r; c < 3; c++) {
            second[at] += w * (covariance[at] + p[r] * p[c]);
            at++;
          }
        }
      }
      for (var k = 0; k < 3; k++) {
        mean[k] /= total;
        expect(merged.centres[k], closeTo(mean[k], 1e-4));
      }
      merged.covarianceOf(0, covariance);
      var at = 0;
      for (var r = 0; r < 3; r++) {
        for (var c = r; c < 3; c++) {
          final expected = second[at] / total - mean[r] * mean[c];
          expect(
            covariance[at],
            closeTo(expected, 1e-3 * (1 + expected.abs())),
          );
          at++;
        }
      }
    });

    test('the eigen solver rebuilds the matrix it was given', () {
      final m = Float64List.fromList(<double>[
        4, 1, 0.5, //
        1, 3, 0.2, //
        0.5, 0.2, 0.001,
      ]);
      final (values, v) = symmetricEigen3(m);
      final det =
          v[0] * (v[4] * v[8] - v[7] * v[5]) -
          v[3] * (v[1] * v[8] - v[7] * v[2]) +
          v[6] * (v[1] * v[5] - v[4] * v[2]);
      expect(det, closeTo(1, 1e-9));
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 3; c++) {
          var sum = 0.0;
          for (var k = 0; k < 3; k++) {
            sum += v[k * 3 + r] * values[k] * v[k * 3 + c];
          }
          expect(sum, closeTo(m[r * 3 + c], 1e-9));
        }
      }
    });
  });

  group('the file', () {
    final cloud = _randomCloud(3000, 5);
    final tree = buildSplatOctree(cloud, leafCapacity: 64, grid: 4);
    final bytes = encodeSplatOctree(tree);

    test('round-trips every node and page', () {
      final back = parseSplatOctree(bytes);
      expect(back.nodes.length, tree.nodes.length);
      expect(back.leafSplatCount, cloud.count);
      for (final (k, node) in tree.nodes.indexed) {
        final other = back.nodes[k];
        expect(other.firstChild, node.firstChild);
        expect(other.childCount, node.childCount);
        expect(other.pageOffset, node.pageOffset);
        expect(_keys(other.splats!), _keys(node.splats!));
      }
    });

    test('refuses what is not one', () {
      expect(
        () => parseSplatOctree(Uint8List(64)),
        throwsA(isA<SplatOctreeException>()),
      );
    });

    test('pages in only what a small budget draws, and all of it for a '
        'large one', () async {
      Future<(int, SplatCloud)> settle(int budget) async {
        final paged = await PagedSplatOctree.open(
          splatBytesReader(bytes),
          maxInFlight: 2,
        );
        final lod = SplatLod.paged(paged, budget: budget);
        final eye = Vector3(0, 0, 30);
        var drawn = lod.choose(eye);
        // Walk, wait for what the walk asked for, walk again — the frames a
        // viewer would draw while the pages arrive.
        for (var pass = 0; pass < 200; pass++) {
          await paged.idle;
          final version = paged.tree.pageVersion;
          drawn = lod.choose(eye);
          expect(drawn.count, lessThanOrEqualTo(budget));
          await paged.idle;
          if (paged.tree.pageVersion == version) break;
        }
        return (paged.bytesRead, drawn);
      }

      final (small, _) = await settle(300);
      final (large, all) = await settle(1 << 30);
      expect(small, lessThan(bytes.length ~/ 2));
      expect(_keys(all), _keys(cloud));
      // Every page once, none twice.
      expect(large, bytes.length);
    });
  });

  group('SplatQuads.lod', () {
    final tree = buildSplatOctree(_randomCloud(2000, 9), leafCapacity: 64);
    final right = Vector3(1, 0, 0), up = Vector3(0, 1, 0);

    test('draws the cut, and cuts again only when it sorts', () {
      final lod = SplatLod(tree, budget: 500);
      final quads = SplatQuads.lod(lod);
      quads.build(eye: Vector3(0, 0, 30), right: right, up: up);
      expect(quads.cloud.count, lod.cutSplatCount);
      expect(quads.vertexCount, lod.cutSplatCount * kSplatVerticesPerSplat);
      expect(quads.sorts, 1);

      // A move too small to re-sort keeps the cut it has.
      quads.build(eye: Vector3(0, 0, 30.0001), right: right, up: up);
      expect(quads.sorts, 1);

      // A new budget is a new cut, and so a sort.
      lod.budget = 2000;
      quads.build(eye: Vector3(0, 0, 30.0001), right: right, up: up);
      expect(quads.sorts, 2);
      expect(quads.cloud.count, 2000);
    });
  });
}
