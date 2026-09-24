/// The counting sort a cloud is drawn in the order of — `C1`.
///
///     dart test test/engine/splat_sort_test.dart
///
/// The claim is exactness against a plain comparison sort over the same
/// sixteen-bit keys, ties by index: the two-pass counting sort is only a
/// faster way to the same permutation. Separately, the keys themselves are
/// held to be the distances, far to near, to within one quantisation step.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A cloud of [count] splats scattered by [seed] through a box a few metres
/// across, some of them sharing a centre so that ties happen.
SplatCloud _randomCloud(int count, int seed) {
  final random = math.Random(seed);
  final centres = Float32List(count * 3);
  for (var i = 0; i < count; i++) {
    final twin = i > 0 && random.nextInt(10) == 0;
    for (var c = 0; c < 3; c++) {
      centres[i * 3 + c] = twin
          ? centres[(i - 1) * 3 + c]
          : random.nextDouble() * 6.0 - 3.0;
    }
  }
  final rotations = Float32List(count * 4);
  for (var i = 0; i < count; i++) {
    rotations[i * 4 + 3] = 1.0;
  }
  return SplatCloud(
    centres: centres,
    colours: Float32List(count * 4),
    scales: Float32List(count * 3),
    rotations: rotations,
  );
}

void main() {
  test('the counting sort matches a comparator sort on random keys', () {
    // Mutation: sort the high byte first — the order then follows the low
    // byte, and this fails on the first seed.
    for (final seed in <int>[1, 2, 3, 4, 5]) {
      final random = math.Random(seed);
      final count = 1 + random.nextInt(4000);
      final keys = Uint32List.fromList(<int>[
        for (var i = 0; i < count; i++)
          // Narrow ranges some of the time, so ties are common.
          seed.isEven
              ? random.nextInt(kSplatKeyMax + 1)
              : random.nextInt(64) * 1000,
      ]);
      final reference = List<int>.generate(count, (i) => i)
        ..sort((a, b) {
          final byKey = keys[a].compareTo(keys[b]);
          return byKey != 0 ? byKey : a.compareTo(b);
        });

      final order = Uint32List.fromList(List<int>.generate(count, (i) => i));
      sortSplatKeys(
        keys,
        order,
        Uint32List(count),
        Uint32List(count),
        count,
        Uint32List(256),
      );
      expect(order, orderedEquals(reference), reason: 'seed $seed');
    }
  });

  test("a cloud's order matches a comparator sort of its own keys", () {
    for (final seed in <int>[11, 12, 13]) {
      final cloud = _randomCloud(3000, seed);
      final eye = Vector3(0.3, 1.2, 7.0);
      final sorter = SplatSorter()..sort(cloud, eye);

      // The keys the sorter quantised, recomputed here from the distances
      // it is documented to use.
      final distances = <double>[
        for (var i = 0; i < cloud.count; i++)
          Vector3(
            cloud.centres[i * 3],
            cloud.centres[i * 3 + 1],
            cloud.centres[i * 3 + 2],
          ).distanceTo(eye),
      ];
      final near = distances.reduce(math.min);
      final far = distances.reduce(math.max);
      final keyOf = <int>[
        for (final d in distances)
          ((far - Float32List.fromList(<double>[d])[0]) *
                  (kSplatKeyMax / (far - near)))
              .floor()
              .clamp(0, kSplatKeyMax),
      ];
      final reference = List<int>.generate(cloud.count, (i) => i)
        ..sort((a, b) {
          final byKey = keyOf[a].compareTo(keyOf[b]);
          return byKey != 0 ? byKey : a.compareTo(b);
        });
      expect(
        sorter.order.sublist(0, cloud.count),
        orderedEquals(reference),
        reason: 'seed $seed',
      );
    }
  });

  test('far comes before near, to within one step of the key', () {
    // Mutation: quantise `distance − near` instead of `far − distance` — the
    // order comes out near to far and every pair below disagrees.
    final cloud = _randomCloud(2000, 7);
    final eye = Vector3(-2.0, 0.5, 5.0);
    final sorter = SplatSorter()..sort(cloud, eye);
    double distanceOf(int i) => Vector3(
      cloud.centres[i * 3],
      cloud.centres[i * 3 + 1],
      cloud.centres[i * 3 + 2],
    ).distanceTo(eye);

    final step = sorter.lastRange / kSplatKeyMax;
    for (var n = 1; n < cloud.count; n++) {
      final before = distanceOf(sorter.order[n - 1]);
      final after = distanceOf(sorter.order[n]);
      expect(
        before,
        greaterThanOrEqualTo(after - step),
        reason: 'position $n: $before drawn before $after',
      );
    }
  });

  test('turning the camera does not change the order', () {
    // Distance from the eye, not depth along the view axis, which is what
    // lets `SplatQuads` skip the sort for a camera that only looks around.
    // Nothing about the view direction reaches the sort at all.
    final cloud = _randomCloud(500, 9);
    final a = SplatSorter()..sort(cloud, Vector3(0.0, 0.0, 4.0));
    final first = Uint32List.fromList(a.order.sublist(0, cloud.count));
    a.sort(cloud, Vector3(0.0, 0.0, 4.0));
    expect(a.order.sublist(0, cloud.count), orderedEquals(first));
  });

  test('a placed cloud sorts by where it is placed', () {
    // Two splats, the first nearer the eye as stored; a node that moves the
    // cloud past the eye makes the first the far one.
    final cloud = SplatCloud(
      centres: Float32List.fromList(<double>[0, 0, 1, 0, 0, -1]),
      colours: Float32List(8),
      scales: Float32List(6),
      rotations: Float32List.fromList(<double>[0, 0, 0, 1, 0, 0, 0, 1]),
    );
    final eye = Vector3(0.0, 0.0, 5.0);
    final sorter = SplatSorter()..sort(cloud, eye);
    expect(sorter.order.sublist(0, 2), orderedEquals(<int>[1, 0]));

    sorter.sort(
      cloud,
      eye,
      model: Matrix4.compose(
        Vector3(0.0, 0.0, 10.0),
        Quaternion.identity(),
        Vector3(1.0, 1.0, 1.0),
      ),
    );
    expect(sorter.order.sublist(0, 2), orderedEquals(<int>[0, 1]));
  });

  test('an empty cloud and a one-splat cloud sort without complaint', () {
    final sorter = SplatSorter()..sort(_randomCloud(0, 1), Vector3.zero());
    expect(sorter.lastRange, 0.0);
    sorter.sort(_randomCloud(1, 1), Vector3.zero());
    expect(sorter.order[0], 0);
  });
}
