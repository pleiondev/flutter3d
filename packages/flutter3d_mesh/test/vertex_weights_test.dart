/// `anim-09`'s own row: `paintWeight`, `normalizeVertexWeights`,
/// `pruneVertexWeights`, `assignSelection`, `mirrorWeights`,
/// `smoothVertexWeights`, `gradientWeights` — against `EditMesh.cuboid()`.
///
/// **The row's own "мазок 1 % ≤10 % копии"**, read as: a stroke at 1 %
/// strength changes at most 10 % of the vertex's own weight distribution
/// (total variation between before and after) — the row names no unit for
/// "1 %" or "копии", and this is the reading that makes the line a testable
/// bound on how much a small stroke may perturb one vertex, rather than a
/// claim about a whole mesh a one-vertex primitive has no view of.
///
///     dart test test/vertex_weights_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Wraps [body] in one journal step, the way every mutating call here needs.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

double _sum(List<WeightPair> pairs) =>
    pairs.fold<double>(0, (sum, pair) => sum + pair.weight);

void main() {
  group('paintWeight', () {
    test('a stroke on an unskinned vertex leaves it at (0, 1)', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, () => paintWeight(mesh, 0, 0, 0.3));
      final pairs = weightsOf(mesh, 0);
      expect(pairs, hasLength(1));
      expect(pairs.single.joint, 0);
      expect(pairs.single.weight, closeTo(1.0, 1e-6));
    });

    test(
      'accumulates onto an existing joint rather than replacing the vertex',
      () {
        final mesh = EditMesh.cuboid();
        edit(
          mesh,
          () => mesh.setSkin(
            0,
            VertexAttributes(
              joints: Vector4(1, 5, 0, 0),
              weights: Vector4(0.6, 0.4, 0, 0),
            ),
          ),
        );
        edit(mesh, () => paintWeight(mesh, 0, 5, 0.4));
        final pairs = weightsOf(mesh, 0);
        expect(pairs, hasLength(2));
        final five = pairs.firstWhere((p) => p.joint == 5).weight;
        expect(five, greaterThan(0.4)); // grew from its 0.4 share
        expect(_sum(pairs), closeTo(1.0, 1e-6));
      },
    );

    test('sum stays 1±1e-6 and influences stay within the cap after a stroke '
        'that would otherwise add a fifth', () {
      final mesh = EditMesh.cuboid();
      edit(
        mesh,
        () => mesh.setSkin(
          0,
          VertexAttributes(
            joints: Vector4(1, 2, 3, 4),
            weights: Vector4(0.4, 0.3, 0.2, 0.1),
          ),
        ),
      );
      edit(mesh, () => paintWeight(mesh, 0, 9, 0.5, maxInfluences: 4));
      final pairs = weightsOf(mesh, 0);
      expect(pairs.length, lessThanOrEqualTo(4));
      expect(_sum(pairs), closeTo(1.0, 1e-6));
      expect(pairs.map((p) => p.joint), isNot(contains(4)));
    });

    test('a 1% stroke changes at most 10% of the vertex\'s own weight '
        'distribution', () {
      final mesh = EditMesh.cuboid();
      edit(
        mesh,
        () => mesh.setSkin(
          0,
          VertexAttributes(
            joints: Vector4(3, 0, 0, 0),
            weights: Vector4(1, 0, 0, 0),
          ),
        ),
      );
      final before = weightsOf(mesh, 0);
      edit(mesh, () => paintWeight(mesh, 0, 7, 0.01));
      final after = weightsOf(mesh, 0);

      double weightOf(List<WeightPair> pairs, int joint) => pairs
          .where((p) => p.joint == joint)
          .fold<double>(0, (sum, p) => sum + p.weight);
      final joints = <int>{
        for (final p in before) p.joint,
        for (final p in after) p.joint,
      };
      final totalVariation = joints.fold<double>(
        0,
        (sum, joint) =>
            sum + (weightOf(after, joint) - weightOf(before, joint)).abs(),
      );
      expect(totalVariation / 2, lessThanOrEqualTo(0.10));
    });
  });

  group('normalizeVertexWeights', () {
    test(
      'scales stored weights to sum to one without adding or dropping joints',
      () {
        final mesh = EditMesh.cuboid();
        edit(
          mesh,
          () => mesh.setSkin(
            0,
            VertexAttributes(
              joints: Vector4(1, 2, 0, 0),
              weights: Vector4(2, 6, 0, 0),
            ),
          ),
        );
        edit(mesh, () => normalizeVertexWeights(mesh, 0));
        final pairs = weightsOf(mesh, 0);
        expect(pairs, hasLength(2));
        expect(_sum(pairs), closeTo(1.0, 1e-6));
      },
    );
  });

  group('pruneVertexWeights', () {
    test('four stored influences truncate to a smaller cap, renormalized', () {
      // Storage itself already caps at four slots (`mesh-60`'s own subject);
      // pruning further is what this operates on — the ">4 candidates"
      // truncation lives in `paintWeight`'s own accumulation instead, tested
      // above.
      final mesh = EditMesh.cuboid();
      edit(
        mesh,
        () => mesh.setSkin(
          0,
          VertexAttributes(
            joints: Vector4(1, 2, 3, 4),
            weights: Vector4(0.4, 0.3, 0.2, 0.1),
          ),
        ),
      );
      edit(mesh, () => pruneVertexWeights(mesh, 0, 2));
      final pairs = weightsOf(mesh, 0);
      expect(pairs, hasLength(2));
      expect(pairs.map((p) => p.joint).toSet(), <int>{1, 2});
      expect(_sum(pairs), closeTo(1.0, 1e-6));
    });
  });

  group('assignSelection', () {
    test(
      'hard-assigns a whole selection to one joint, dropping other influences',
      () {
        final mesh = EditMesh.cuboid();
        edit(
          mesh,
          () => mesh.setSkin(
            0,
            VertexAttributes(
              joints: Vector4(1, 2, 0, 0),
              weights: Vector4(0.5, 0.5, 0, 0),
            ),
          ),
        );
        edit(mesh, () => assignSelection(mesh, <int>[0, 1], 9, 1.0));
        for (final v in <int>[0, 1]) {
          final pairs = weightsOf(mesh, v);
          expect(pairs, hasLength(1));
          expect(pairs.single.joint, 9);
          expect(pairs.single.weight, closeTo(1.0, 1e-6));
        }
      },
    );
  });

  group('mirrorWeights', () {
    test(
      'a symmetric cube copies weights to the matching vertex, joints remapped',
      () {
        final mesh = EditMesh.cuboid();
        final allVertices = <int>[
          for (var v = 0; v < mesh.vertexSlotCount; v++) v,
        ];

        // Find the two vertices with the largest opposite x — a real pair on
        // the cube's own geometry, not one picked by hand from its layout.
        int left = allVertices.first, right = allVertices.first;
        for (final v in allVertices) {
          final x = mesh.positionOf(v).x;
          if (x < mesh.positionOf(left).x) left = v;
          if (x > mesh.positionOf(right).x) right = v;
        }
        expect(mesh.positionOf(left).x, -mesh.positionOf(right).x);

        edit(
          mesh,
          () => mesh.setSkin(
            left,
            VertexAttributes(
              joints: Vector4(10, 0, 0, 0),
              weights: Vector4(1, 0, 0, 0),
            ),
          ),
        );
        edit(
          mesh,
          () => mirrorWeights(
            mesh,
            allVertices,
            axis: 0,
            jointMirror: <int, int>{10: 11},
          ),
        );
        final mirrored = weightsOf(mesh, right);
        expect(mirrored, hasLength(1));
        expect(mirrored.single.joint, 11);
        expect(mirrored.single.weight, closeTo(1.0, 1e-6));
      },
    );

    test('a vertex on the mirror plane is left alone', () {
      final mesh = EditMesh.cuboid();
      final allVertices = <int>[
        for (var v = 0; v < mesh.vertexSlotCount; v++) v,
      ];
      // Move one vertex onto the x=0 plane and give it a distinctive weight.
      edit(mesh, () => mesh.moveVertex(allVertices.first, Vector3(0, 1, 1)));
      edit(
        mesh,
        () => mesh.setSkin(
          allVertices.first,
          VertexAttributes(
            joints: Vector4(4, 0, 0, 0),
            weights: Vector4(1, 0, 0, 0),
          ),
        ),
      );
      edit(
        mesh,
        () => mirrorWeights(
          mesh,
          allVertices,
          axis: 0,
          jointMirror: <int, int>{4: 5},
        ),
      );
      final pairs = weightsOf(mesh, allVertices.first);
      expect(pairs.single.joint, 4);
    });
  });

  group('smoothVertexWeights', () {
    test('a lone painted vertex spreads partway onto its neighbours', () {
      final mesh = EditMesh.cuboid();
      final allVertices = <int>[
        for (var v = 0; v < mesh.vertexSlotCount; v++) v,
      ];
      final center = allVertices.first;
      edit(
        mesh,
        () => mesh.setSkin(
          center,
          VertexAttributes(
            joints: Vector4(2, 0, 0, 0),
            weights: Vector4(1, 0, 0, 0),
          ),
        ),
      );
      final neighbor = mesh.neighborsOf(center).first;
      // `center`'s own `setSkin` call just allocated the weight layers for
      // the whole mesh, zero-filled — `neighbor` reads its own real,
      // stored zeros now, not the joint-0 default a never-allocated layer
      // would answer with (see `weightsOf`'s own doc comment).
      expect(weightsOf(mesh, neighbor), isEmpty);

      edit(mesh, () => smoothVertexWeights(mesh, allVertices, lambda: 0.5));

      final neighborPairs = weightsOf(mesh, neighbor);
      expect(_sum(neighborPairs), closeTo(1.0, 1e-6));
      final gotSome = neighborPairs.any((p) => p.joint == 2 && p.weight > 0);
      expect(gotSome, isTrue);
    });

    test('sum stays 1±1e-6 after several iterations', () {
      final mesh = EditMesh.cuboid();
      final allVertices = <int>[
        for (var v = 0; v < mesh.vertexSlotCount; v++) v,
      ];
      edit(
        mesh,
        () => mesh.setSkin(
          allVertices.first,
          VertexAttributes(
            joints: Vector4(2, 0, 0, 0),
            weights: Vector4(1, 0, 0, 0),
          ),
        ),
      );
      edit(
        mesh,
        () =>
            smoothVertexWeights(mesh, allVertices, lambda: 0.5, iterations: 3),
      );
      for (final v in allVertices) {
        expect(_sum(weightsOf(mesh, v)), closeTo(1.0, 1e-6));
      }
    });
  });

  group('gradientWeights', () {
    test('blends linearly between two joints along an axis, sum 1±1e-6', () {
      final mesh = EditMesh.cuboid();
      final allVertices = <int>[
        for (var v = 0; v < mesh.vertexSlotCount; v++) v,
      ];
      edit(
        mesh,
        () => gradientWeights(
          mesh,
          allVertices,
          jointA: 1,
          jointB: 2,
          start: Vector3(-1, 0, 0),
          end: Vector3(1, 0, 0),
        ),
      );
      for (final v in allVertices) {
        final pairs = weightsOf(mesh, v);
        expect(_sum(pairs), closeTo(1.0, 1e-6));
        final x = mesh.positionOf(v).x;
        if (x < 0) {
          expect(
            pairs.firstWhere((p) => p.joint == 1).weight,
            greaterThan(0.5),
          );
        } else {
          expect(
            pairs.firstWhere((p) => p.joint == 2).weight,
            greaterThan(0.5),
          );
        }
      }
    });

    test('a vertex beyond either end clamps rather than extrapolating', () {
      final mesh = EditMesh.cuboid();
      final allVertices = <int>[
        for (var v = 0; v < mesh.vertexSlotCount; v++) v,
      ];
      edit(
        mesh,
        () => gradientWeights(
          mesh,
          allVertices,
          jointA: 1,
          jointB: 2,
          start: Vector3(-0.1, 0, 0),
          end: Vector3(0.1, 0, 0),
        ),
      );
      for (final v in allVertices) {
        final pairs = weightsOf(mesh, v);
        for (final pair in pairs) {
          expect(pair.weight, inInclusiveRange(0.0, 1.0));
        }
      }
    });
  });
}
