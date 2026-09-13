/// `anim-22`'s own acceptance: a cylinder with two bones binds its seam
/// 0.5/0.5, and two legs standing close together do not pull on each other.
///
///     dart test test/bind_weights_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_rig/flutter3d_rig.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// A capped tube of triangles: one ring of [segments] vertices per entry of
/// [heights] (ascending, along Y), a triangle strip between consecutive
/// rings, and a fan cap at the first and last ring — a hand-built mesh
/// rather than one of `flutter3d_geometry`'s own shape generators, so a test
/// knows exactly which vertex indices sit on a given ring (the seam) without
/// reverse-engineering a generator's own vertex order.
({List<Vector3> positions, List<int> triangles, List<int> ringStart}) _tube(
  List<double> heights, {
  double radius = 0.3,
  int segments = 12,
  double centerX = 0.0,
  double centerZ = 0.0,
}) {
  final positions = <Vector3>[];
  final ringStart = <int>[];
  for (final y in heights) {
    ringStart.add(positions.length);
    for (var s = 0; s < segments; s++) {
      final angle = 2 * math.pi * s / segments;
      positions.add(
        Vector3(
          centerX + radius * math.cos(angle),
          y,
          centerZ + radius * math.sin(angle),
        ),
      );
    }
  }

  final triangles = <int>[];
  for (var r = 0; r < heights.length - 1; r++) {
    final a0 = ringStart[r];
    final a1 = ringStart[r + 1];
    for (var s = 0; s < segments; s++) {
      final s2 = (s + 1) % segments;
      triangles.addAll(<int>[a0 + s, a1 + s, a1 + s2]);
      triangles.addAll(<int>[a0 + s, a1 + s2, a0 + s2]);
    }
  }

  // Fan caps close the tube, so a ray probing this mesh's own interior
  // cannot sneak in through an open end.
  final bottomCenter = positions.length;
  positions.add(Vector3(centerX, heights.first, centerZ));
  for (var s = 0; s < segments; s++) {
    final s2 = (s + 1) % segments;
    triangles.addAll(<int>[bottomCenter, ringStart[0] + s2, ringStart[0] + s]);
  }
  final topCenter = positions.length;
  positions.add(Vector3(centerX, heights.last, centerZ));
  final lastRing = ringStart.last;
  for (var s = 0; s < segments; s++) {
    final s2 = (s + 1) % segments;
    triangles.addAll(<int>[topCenter, lastRing + s, lastRing + s2]);
  }

  return (positions: positions, triangles: triangles, ringStart: ringStart);
}

/// The ordinary pipeline: raw [bindWeights], pruned to [kMaxSkinInfluences]
/// and renormalized — the shape `paintWeights`' own callers already expect a
/// finished binding in.
Map<int, List<WeightPair>> _bind({
  required List<Vector3> positions,
  required List<int> triangles,
  required List<BoneSegment> bones,
  bool useVisibility = true,
}) => normalizeSkinWeights(
  pruneSkinWeights(
    bindWeights(
      positions: positions,
      triangles: triangles,
      bones: bones,
      useVisibility: useVisibility,
    ),
  ),
);

double _weightOf(List<WeightPair> pairs, int joint) =>
    pairs.where((p) => p.joint == joint).fold(0.0, (sum, p) => sum + p.weight);

void main() {
  group('bindWeights — seam', () {
    test('a two-bone cylinder binds its seam 0.5/0.5', () {
      final mesh = _tube(<double>[-1.0, 0.0, 1.0], radius: 0.3, segments: 16);
      final bones = <BoneSegment>[
        BoneSegment(Vector3(0, -1, 0), Vector3(0, 0, 0), name: 'lowerLeg'),
        BoneSegment(Vector3(0, 0, 0), Vector3(0, 1, 0), name: 'upperLeg'),
      ];

      final bound = _bind(
        positions: mesh.positions,
        triangles: mesh.triangles,
        bones: bones,
      );

      final seamRing = mesh.ringStart[1];
      for (var s = 0; s < 16; s++) {
        final pairs = bound[seamRing + s]!;
        expect(
          _weightOf(pairs, 0),
          closeTo(0.5, 1e-6),
          reason: 'seam vertex $s, bone 0',
        );
        expect(
          _weightOf(pairs, 1),
          closeTo(0.5, 1e-6),
          reason: 'seam vertex $s, bone 1',
        );
        final total = pairs.fold<double>(0, (sum, p) => sum + p.weight);
        expect(total, closeTo(1.0, 1e-9));
      }
    });

    test('a vertex away from the seam favours its own half', () {
      final mesh = _tube(<double>[-1.0, 0.0, 1.0], radius: 0.3, segments: 16);
      final bones = <BoneSegment>[
        BoneSegment(Vector3(0, -1, 0), Vector3(0, 0, 0)),
        BoneSegment(Vector3(0, 0, 0), Vector3(0, 1, 0)),
      ];

      final bound = _bind(
        positions: mesh.positions,
        triangles: mesh.triangles,
        bones: bones,
      );

      final topRing = mesh.ringStart[2];
      final pairs = bound[topRing]!;
      expect(_weightOf(pairs, 1), greaterThan(0.9));
      expect(_weightOf(pairs, 0), lessThan(0.1));
    });
  });

  group('bindWeights — two legs', () {
    // Two capped tubes standing side by side, close enough that a vertex on
    // one leg's inner wall is not much farther from the *other* leg's bone
    // than it is from its own — the exact shape a pure-distance bind gets
    // wrong. The bones stop short of the tubes' own capped ends (0.2..1.8
    // inside a 0..2 tube) purely so a boundary-ring vertex's line to the
    // *other* leg's bone is never exactly coplanar with that leg's own flat
    // end cap — a numerical accident of this hand-built mesh, not a claim
    // about real rigs, which is why it is called out here rather than left
    // for someone to puzzle over later.
    final legA = _tube(
      <double>[0.0, 1.0, 2.0],
      radius: 0.3,
      segments: 16,
      centerX: -0.4,
    );
    final legB = _tube(
      <double>[0.0, 1.0, 2.0],
      radius: 0.3,
      segments: 16,
      centerX: 0.4,
    );
    final offset = legA.positions.length;
    final positions = <Vector3>[...legA.positions, ...legB.positions];
    final triangles = <int>[
      ...legA.triangles,
      for (final index in legB.triangles) index + offset,
    ];
    final bones = <BoneSegment>[
      BoneSegment(
        Vector3(-0.4, 0.2, 0),
        Vector3(-0.4, 1.8, 0),
        name: 'leftKnee',
      ),
      BoneSegment(
        Vector3(0.4, 0.2, 0),
        Vector3(0.4, 1.8, 0),
        name: 'rightKnee',
      ),
    ];

    // The vertex on leg A's wall that faces leg B most directly: angle 0 is
    // +X from leg A's own centre, i.e. the inner side, at the mid-height
    // ring.
    final innerVertexOfLegA =
        legA.ringStart[1]; // (-0.4 + 0.3, 1.0, 0) = (-0.1, 1.0, 0)

    test(
      'MUTATION CHECK: naive pure-distance binding pulls leg A toward leg B',
      () {
        final naive = _bind(
          positions: positions,
          triangles: triangles,
          bones: bones,
          useVisibility: false,
        );
        final pairs = naive[innerVertexOfLegA]!;
        final ownWeight = _weightOf(pairs, 0);
        final foreignWeight = _weightOf(pairs, 1);

        // This is the failure the row exists to fix: a vertex on leg A's own
        // inner wall picks up real, non-negligible weight from leg B's bone
        // under pure inverse-distance falloff, because the two bones are
        // geometrically close even though the meshes never touch.
        expect(
          foreignWeight,
          greaterThan(0.1),
          reason:
              'sanity check on the test mesh itself: if this is not '
              'comfortably above zero, the naive implementation would not '
              'actually fail here and the visibility assertion below would '
              'not be exercising anything',
        );
        expect(ownWeight + foreignWeight, closeTo(1.0, 1e-9));
      },
    );

    test('visibility through the BVH keeps leg A off leg B\'s bone', () {
      final bound = _bind(
        positions: positions,
        triangles: triangles,
        bones: bones,
      );
      final pairs = bound[innerVertexOfLegA]!;

      expect(_weightOf(pairs, 0), closeTo(1.0, 1e-6));
      expect(
        _weightOf(pairs, 1),
        lessThan(1e-6),
        reason:
            "leg B's bone sits inside leg B's own wall; a straight line "
            "from leg A's surface to it must cross that wall, which the "
            'BVH visibility test is exactly what should catch',
      );
    });

    test('every vertex on leg A is visibility-bound only to its own bone', () {
      final bound = _bind(
        positions: positions,
        triangles: triangles,
        bones: bones,
      );
      for (var v = 0; v < legA.positions.length; v++) {
        final pairs = bound[v]!;
        expect(_weightOf(pairs, 1), lessThan(1e-6), reason: 'leg A vertex $v');
      }
    });
  });

  group('vertexAdjacency', () {
    test('two triangles sharing an edge are mutually adjacent', () {
      // 0-1-2 and 1-3-2, sharing edge 1-2.
      final triangles = <int>[0, 1, 2, 1, 3, 2];
      final adjacency = vertexAdjacency(triangles);
      expect(adjacency[0], unorderedEquals(<int>[1, 2]));
      expect(adjacency[1], unorderedEquals(<int>[0, 2, 3]));
      expect(adjacency[2], unorderedEquals(<int>[0, 1, 3]));
      expect(adjacency[3], unorderedEquals(<int>[1, 2]));
    });
  });

  group('pruneSkinWeights', () {
    test(
      'drops weights below threshold and keeps the largest maxInfluences',
      () {
        final weights = <int, List<WeightPair>>{
          0: <WeightPair>[
            WeightPair(0, 0.5),
            WeightPair(1, 0.3),
            WeightPair(2, 0.1),
            WeightPair(3, 0.09),
            WeightPair(4, 0.0005),
          ],
        };
        final pruned = pruneSkinWeights(
          weights,
          maxInfluences: 3,
          threshold: 1e-3,
        );
        final joints = pruned[0]!.map((p) => p.joint).toList();
        expect(joints, <int>[0, 1, 2]);
      },
    );
  });

  group('normalizeSkinWeights', () {
    test('rescales a vertex\'s weights to sum to one', () {
      final weights = <int, List<WeightPair>>{
        0: <WeightPair>[WeightPair(0, 2.0), WeightPair(1, 6.0)],
      };
      final normalized = normalizeSkinWeights(weights)[0]!;
      final total = normalized.fold<double>(0, (sum, p) => sum + p.weight);
      expect(total, closeTo(1.0, 1e-9));
      expect(_weightOf(normalized, 0), closeTo(0.25, 1e-9));
      expect(_weightOf(normalized, 1), closeTo(0.75, 1e-9));
    });
  });

  group('smoothSkinWeights', () {
    test('blends a vertex toward its neighbours, lambda of the way', () {
      final weights = <int, List<WeightPair>>{
        0: <WeightPair>[WeightPair(0, 1.0)],
        1: <WeightPair>[WeightPair(1, 1.0)],
      };
      final adjacency = <int, List<int>>{
        0: <int>[1],
        1: <int>[0],
      };
      final smoothed = smoothSkinWeights(
        weights,
        adjacency,
        lambda: 0.5,
        iterations: 1,
      );
      // Vertex 0 starts fully on bone 0; its one neighbour is fully on bone
      // 1, so half-way blending should leave it near an even split.
      expect(_weightOf(smoothed[0]!, 0), closeTo(0.5, 1e-9));
      expect(_weightOf(smoothed[0]!, 1), closeTo(0.5, 1e-9));
    });
  });

  group('mirrorSkinWeights', () {
    test(
      'copies weight onto the mirror vertex with the bone name mirrored',
      () {
        final positions = <Vector3>[
          Vector3(-1, 0, 0), // vertex 0: bound to leftKnee
          Vector3(1, 0, 0), // vertex 1: its mirror image across x=0
        ];
        final bones = <BoneSegment>[
          BoneSegment(Vector3(-1, -1, 0), Vector3(-1, 1, 0), name: 'leftKnee'),
          BoneSegment(Vector3(1, -1, 0), Vector3(1, 1, 0), name: 'rightKnee'),
        ];
        final weights = <int, List<WeightPair>>{
          0: <WeightPair>[WeightPair(0, 1.0)],
          1: <WeightPair>[],
        };

        final mirrored = mirrorSkinWeights(
          weights,
          positions,
          bones,
          axis: 0,
          plane: 0.0,
        );

        expect(mirrored[1]!.single.joint, 1);
        expect(mirrored[1]!.single.weight, closeTo(1.0, 1e-9));
        // The source vertex's own weights are untouched.
        expect(mirrored[0]!.single.joint, 0);
      },
    );
  });
}
