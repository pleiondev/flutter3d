/// `mesh-60`'s own row: weight operations over up to eight candidate
/// pairs, truncated to a stored-slot count and renormalized —
/// `normalizeWeights`, `limitInfluences`, `weightsOf`.
///
///     dart test test/weight_ops_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('weightsOf', () {
    test('an unskinned vertex reads joint 0 at full weight', () {
      // `EditMesh.skinOf`'s own contract: the first joint at full weight is
      // what an unskinned vertex means to the shader, not "no binding".
      final mesh = EditMesh.cuboid();
      final pairs = weightsOf(mesh, 0);
      expect(pairs, hasLength(1));
      expect(pairs.single.joint, 0);
      expect(pairs.single.weight, closeTo(1.0, 1e-9));
    });

    test('round-trips what setSkin wrote, zero-weight slots dropped', () {
      final mesh = EditMesh.cuboid()
        ..beginStep()
        ..setSkin(
          0,
          VertexAttributes(
            joints: Vector4(2, 5, 0, 0),
            weights: Vector4(0.7, 0.3, 0.0, 0.0),
          ),
        )
        ..endStep();
      final pairs = weightsOf(mesh, 0);
      expect(pairs, hasLength(2));
      expect(pairs[0].joint, 2);
      expect(pairs[0].weight, closeTo(0.7, 1e-6));
      expect(pairs[1].joint, 5);
      expect(pairs[1].weight, closeTo(0.3, 1e-6));
    });
  });

  group('normalizeWeights', () {
    test('scales weights to sum to one', () {
      final scaled = normalizeWeights(<WeightPair>[
        WeightPair(0, 2.0),
        WeightPair(1, 6.0),
      ]);
      final total = scaled.fold<double>(0, (sum, p) => sum + p.weight);
      expect(total, closeTo(1.0, 1e-9));
      expect(scaled[0].weight, closeTo(0.25, 1e-9));
      expect(scaled[1].weight, closeTo(0.75, 1e-9));
    });

    test('a near-zero total is left unchanged rather than divided by', () {
      final pairs = <WeightPair>[WeightPair(0, 1e-12)];
      expect(normalizeWeights(pairs), same(pairs));
    });

    test('an empty list stays empty', () {
      expect(normalizeWeights(const <WeightPair>[]), isEmpty);
    });
  });

  group('limitInfluences', () {
    test('five bones truncate to four, summing to one', () {
      final limited = limitInfluences(<WeightPair>[
        WeightPair(0, 0.30),
        WeightPair(1, 0.25),
        WeightPair(2, 0.20),
        WeightPair(3, 0.15),
        WeightPair(4, 0.10),
      ], 4);
      expect(limited, hasLength(4));
      expect(limited.map((p) => p.joint), <int>[0, 1, 2, 3]);
      final total = limited.fold<double>(0, (sum, p) => sum + p.weight);
      expect(total, closeTo(1.0, 1e-6));
      // The two heaviest keep the same ratio to each other post-renormalize.
      expect(limited[0].weight / limited[1].weight, closeTo(0.30 / 0.25, 1e-9));
    });

    test('drops non-positive weights before ranking', () {
      final limited = limitInfluences(<WeightPair>[
        WeightPair(0, 0.5),
        WeightPair(1, -0.1),
        WeightPair(2, 0.0),
        WeightPair(3, 0.5),
      ], 4);
      expect(limited.map((p) => p.joint).toSet(), <int>{0, 3});
    });

    test('fewer pairs than the cap are kept as-is, only renormalized', () {
      final limited = limitInfluences(<WeightPair>[WeightPair(7, 0.4)], 4);
      expect(limited, hasLength(1));
      expect(limited.single.weight, closeTo(1.0, 1e-9));
    });
  });

  group('toVertexAttributes', () {
    test(
      'a loop cut between two full-weight endpoints lands at (0.5, 0.5)',
      () {
        // The same case `VertexAttributes.lerp` already covers for a split —
        // named here as `mesh-60`'s own acceptance line for it.
        final a = VertexAttributes(
          joints: Vector4(1, 0, 0, 0),
          weights: Vector4(1, 0, 0, 0),
        );
        final b = VertexAttributes(
          joints: Vector4(3, 0, 0, 0),
          weights: Vector4(1, 0, 0, 0),
        );
        final mid = VertexAttributes.lerp(a, b, 0.5);
        final pairs = <WeightPair>[
          for (var i = 0; i < 4; i++)
            if (mid.weights[i] > 0)
              WeightPair(mid.joints[i].round(), mid.weights[i]),
        ];
        final result = toVertexAttributes(pairs);
        expect(result.weights.x, closeTo(0.5, 1e-9));
        expect(result.weights.y, closeTo(0.5, 1e-9));
      },
    );

    test('more than four candidates keep only the four heaviest', () {
      final result = toVertexAttributes(<WeightPair>[
        WeightPair(0, 0.30),
        WeightPair(1, 0.25),
        WeightPair(2, 0.20),
        WeightPair(3, 0.15),
        WeightPair(4, 0.10),
      ]);
      final total =
          result.weights.x +
          result.weights.y +
          result.weights.z +
          result.weights.w;
      expect(total, closeTo(1.0, 1e-6));
      expect(result.joints.storage, isNot(contains(4.0)));
    });

    test('round-trips through EditMesh.setSkin/skinOf', () {
      final written = toVertexAttributes(<WeightPair>[
        WeightPair(2, 0.6),
        WeightPair(9, 0.4),
      ]);
      final mesh = EditMesh.cuboid()
        ..beginStep()
        ..setSkin(0, written)
        ..endStep();
      final pairs = weightsOf(mesh, 0);
      expect(pairs, hasLength(2));
      expect(pairs[0].joint, 2);
      expect(pairs[0].weight, closeTo(0.6, 1e-6));
      expect(pairs[1].joint, 9);
      expect(pairs[1].weight, closeTo(0.4, 1e-6));
    });
  });
}
