/// A modifier stack, and the one modifier that exists to prove it works.
///
///     dart test test/modifier_test.dart
///
/// `mesh-40`'s own acceptance is about the stack, not about geometry: a base
/// evaluated twice costs one fold, and a modifier's own fields round-trip
/// through JSON. `ArrayModifier` (`mesh-42`) is what gives the stack
/// something real to fold, chosen because it needs no reflection or winding
/// flip — a translated copy is still wound the way the original was.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('ModifierStack', () {
    test('the same base evaluated twice folds the stack once', () {
      final stack = ModifierStack(<Modifier>[
        ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
      ]);
      final base = EditMesh.cuboid();

      final first = stack.evaluate(base, ModifierContext());
      final second = stack.evaluate(base, ModifierContext());

      // Mutation: drop the `identical(base, _lastBase)` check and always
      // re-fold — both calls still answer the same *shape*, so only
      // `identical` on the result itself catches a stack that recomputes
      // when its own acceptance says it must not.
      expect(identical(first, second), isTrue);
    });

    test('a different base re-folds rather than answering the old cache', () {
      final stack = ModifierStack(<Modifier>[
        ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
      ]);
      final first = stack.evaluate(EditMesh.cuboid(), ModifierContext());
      final second = stack.evaluate(EditMesh.cuboid(), ModifierContext());

      expect(identical(first, second), isFalse);
    });

    test('an empty stack hands the base straight back', () {
      final stack = ModifierStack(const <Modifier>[]);
      final base = EditMesh.cuboid();
      expect(identical(stack.evaluate(base, ModifierContext()), base), isTrue);
    });

    test('the same base but a different operand mesh re-folds too', () {
      final stack = ModifierStack(<Modifier>[
        BooleanModifier(
          operation: CsgOperation.union,
          operandId: 1,
          operandTransform: Matrix4.translationValues(0.5, 0.3, 0.2),
        ),
      ]);
      final base = EditMesh.cuboid();
      final operandA = EditMesh.cuboid();
      final operandB = EditMesh.cuboid();

      final first = stack.evaluate(
        base,
        ModifierContext(operands: <int, EditMesh>{1: operandA}),
      );
      final second = stack.evaluate(
        base,
        ModifierContext(operands: <int, EditMesh>{1: operandB}),
      );

      // Mutation: cache on `base`'s own identity alone, the way this class
      // used to before `BooleanModifier` existed — `second` would then be
      // `identical` to `first`, a stale answer from before the operand's
      // own mesh (a different instance, even though it started out an
      // identical cube) was swapped in. `mesh-48`'s own acceptance is this
      // exact case one level up, at `ModifierEvaluationCache`: a changed
      // operand must never be read through a cache keyed on this object's
      // own base alone.
      expect(identical(first, second), isFalse);
    });

    test('the same base and the same operand mesh instance answers the '
        'cached result', () {
      final stack = ModifierStack(<Modifier>[
        BooleanModifier(
          operation: CsgOperation.union,
          operandId: 1,
          operandTransform: Matrix4.translationValues(0.5, 0.3, 0.2),
        ),
      ]);
      final base = EditMesh.cuboid();
      final operand = EditMesh.cuboid();

      final first = stack.evaluate(
        base,
        ModifierContext(operands: <int, EditMesh>{1: operand}),
      );
      final second = stack.evaluate(
        base,
        ModifierContext(operands: <int, EditMesh>{1: operand}),
      );

      expect(identical(first, second), isTrue);
    });
  });

  group('modifierFromJson', () {
    test('an unknown kind is null, not a refusal', () {
      expect(modifierFromJson(<String, Object?>{'kind': 'future'}), isNull);
    });

    test('not a map at all is null', () {
      expect(modifierFromJson('array'), isNull);
    });
  });

  group('ArrayModifier', () {
    test(
      'four copies of a cube give 32 vertices and four times the volume',
      () {
        final base = EditMesh.cuboid();
        final modifier = ArrayModifier(count: 4, offset: Vector3(2, 0, 0));

        final result = modifier.apply(base, ModifierContext());
        result.validate();

        // Mutation: reuse one vertex list across every copy instead of adding
        // fresh vertices per copy — every copy then lands on the same eight
        // points and the vertex count stops moving with `count`.
        expect(result.vertexCount, 32);
        expect(result.faceCount, 24);
        final double baseVolume = base.signedVolume.abs();
        // Overlapping copies would still sum to four times the volume — the
        // divergence-theorem formula adds one closed shape's contribution
        // per copy regardless of where it sits — so volume alone cannot
        // catch a shift that never moved. The span across X can: a base
        // cube of side 1 copied four times two apart reaches from -0.5 to
        // 6.5, seven units wide, only if every copy actually landed at its
        // own `offset * copy`.
        expect(result.signedVolume.abs(), closeTo(baseVolume * 4, 1e-9));
        var maxX = double.negativeInfinity;
        for (var v = 0; v < result.vertexSlotCount; v++) {
          if (result.isVertexAlive(v)) {
            maxX = maxX > result.positionOf(v).x
                ? maxX
                : result.positionOf(v).x;
          }
        }
        // Mutation: apply `shift` to only the first copy, or forget `copy` in
        // `offset.clone()..scale(copy.toDouble())` — either leaves every copy
        // sitting on top of the one before it, and the widest point stays at
        // 0.5 no matter how many copies `count` asks for.
        expect(maxX, closeTo(6.5, 1e-9));
      },
    );

    test('count: 1 is the identity — the same shape, freshly built', () {
      final base = EditMesh.cuboid();
      final modifier = ArrayModifier(count: 1, offset: Vector3(5, 0, 0));

      final result = modifier.apply(base, ModifierContext());
      result.validate();

      expect(result.vertexCount, base.vertexCount);
      expect(result.faceCount, base.faceCount);
      expect(result.signedVolume, closeTo(base.signedVolume, 1e-9));
    });

    test('count below 1 is refused rather than building nothing', () {
      final modifier = ArrayModifier(count: 0, offset: Vector3(1, 0, 0));
      expect(
        () => modifier.apply(EditMesh.cuboid(), ModifierContext()),
        throwsArgumentError,
      );
    });

    test('a mergeDistance welds copies placed to touch, not merely near', () {
      final base = EditMesh.cuboid(size: Vector3(2, 2, 2));
      // Two cubes of side 2 offset by exactly 2 on X sit face to face with no
      // gap: every vertex on the shared face has an exact twin to weld.
      final modifier = ArrayModifier(
        count: 2,
        offset: Vector3(2, 0, 0),
        mergeDistance: 1e-6,
      );

      final result = modifier.apply(base, ModifierContext());
      result.validate();

      // 8 + 8 vertices minus the 4 pairs welded on the shared face.
      // Mutation: skip the `mergeByDistance` pass when `mergeDistance` is
      // given — the count stays 16 instead of dropping to 12, and the two
      // cubes read back as two solids sharing a face they never welded.
      expect(result.vertexCount, 12);
    });

    test('round-trips through JSON, mergeDistance included', () {
      final modifier = ArrayModifier(
        count: 3,
        offset: Vector3(1.5, 0.5, -2),
        mergeDistance: 0.01,
      );
      final restored = modifierFromJson(modifier.toJson());

      expect(restored, isA<ArrayModifier>());
      final again = restored! as ArrayModifier;
      expect(again.count, 3);
      expect(again.offset, Vector3(1.5, 0.5, -2));
      expect(again.mergeDistance, 0.01);
    });

    test('a null mergeDistance round-trips as null, not zero', () {
      final modifier = ArrayModifier(count: 2, offset: Vector3(1, 0, 0));
      final restored = modifierFromJson(modifier.toJson())! as ArrayModifier;

      // Mutation: default a missing `mergeDistance` to `0.0` in `fromJson`
      // instead of leaving it null — a modifier that was never meant to weld
      // its copies would silently start doing it on the very first save and
      // reopen.
      expect(restored.mergeDistance, isNull);
    });

    test('a modifier missing a required field is refused, not guessed', () {
      expect(
        modifierFromJson(<String, Object?>{'kind': 'array', 'count': 2}),
        isNull,
      );
    });

    test('each face keeps its own copy\'s material slot', () {
      final base = EditMesh.cuboid();
      base.beginStep();
      for (var f = 0; f < base.faceSlotCount; f++) {
        if (base.isFaceAlive(f)) base.setMaterialSlot(f, 2);
      }
      base.endStep();

      final modifier = ArrayModifier(count: 2, offset: Vector3(2, 0, 0));
      final result = modifier.apply(base, ModifierContext());
      result.validate();

      // Mutation: leave every copy's face at the default slot 0 instead of
      // carrying the base's own slot across — a painted array would come
      // back unpainted the moment it round-trips through this modifier.
      for (var f = 0; f < result.faceSlotCount; f++) {
        if (result.isFaceAlive(f)) expect(result.materialSlotOf(f), 2);
      }
    });
  });

  group('MirrorModifier', () {
    test('round-trips through JSON, every field included', () {
      final modifier = MirrorModifier(
        normal: Vector3(1, 0, 0),
        mergeDistance: 0.01,
        bisect: true,
        flipUv: true,
      );
      final restored = modifierFromJson(modifier.toJson());

      expect(restored, isA<MirrorModifier>());
      final again = restored! as MirrorModifier;
      expect(again.normal, Vector3(1, 0, 0));
      expect(again.mergeDistance, 0.01);
      expect(again.bisect, isTrue);
      expect(again.flipUv, isTrue);
    });

    test('a null mergeDistance round-trips as null, not zero', () {
      final modifier = MirrorModifier(normal: Vector3(0, 1, 0));
      final restored = modifierFromJson(modifier.toJson())! as MirrorModifier;

      expect(restored.mergeDistance, isNull);
      // Mutation: default `bisect`/`flipUv` to `true` when absent instead of
      // reading them — every mirror saved before this test would come back
      // asking for a refusal (`bisect`) or a UV flip it never asked for.
      expect(restored.bisect, isFalse);
      expect(restored.flipUv, isFalse);
    });

    test('a modifier missing a required field is refused, not guessed', () {
      expect(modifierFromJson(<String, Object?>{'kind': 'mirror'}), isNull);
    });

    test('apply defers to the mirror function with its own parameters', () {
      final modifier = MirrorModifier(
        normal: Vector3(1, 0, 0),
        mergeDistance: 1e-6,
      );
      final base = EditMesh.fromFaces(
        <Vector3>[
          Vector3(0, -0.5, -0.5),
          Vector3(1, -0.5, -0.5),
          Vector3(1, 0.5, -0.5),
          Vector3(0, 0.5, -0.5),
          Vector3(0, -0.5, 0.5),
          Vector3(1, -0.5, 0.5),
          Vector3(1, 0.5, 0.5),
          Vector3(0, 0.5, 0.5),
        ],
        <List<int>>[
          <int>[4, 5, 6, 7],
          <int>[1, 0, 3, 2],
          <int>[5, 1, 2, 6],
          <int>[0, 4, 7, 3],
          <int>[3, 7, 6, 2],
          <int>[0, 1, 5, 4],
        ],
      );

      final direct = mirror(
        base,
        normal: Vector3(1, 0, 0),
        mergeDistance: 1e-6,
      );
      final throughModifier = modifier.apply(base, ModifierContext());

      // Mutation: hard-code `bisect: true` (or drop `mergeDistance`) inside
      // `apply` instead of passing this modifier's own fields through — the
      // wrapper would then behave the same for every instance regardless of
      // what it was constructed with.
      expect(throughModifier.vertexCount, direct.vertexCount);
      expect(throughModifier.faceCount, direct.faceCount);
      expect(throughModifier.signedVolume, closeTo(direct.signedVolume, 1e-9));
    });
  });

  group('SmoothModifier', () {
    test('never mutates its own base', () {
      final base = const ParametricSphere(segments: 8, rings: 4).toEditMesh();
      final before = <Vector3>[
        for (var v = 0; v < base.vertexSlotCount; v++)
          if (base.isVertexAlive(v)) base.positionOf(v),
      ];

      const modifier = SmoothModifier(iterations: 5, preserveVolume: true);
      modifier.apply(base, ModifierContext());

      // Mutation: run `smoothVertices` on `base` itself instead of a
      // `fromBytes(toBytes())` copy — a stack evaluated twice from the same
      // base would then find it already smoothed the second time.
      final after = <Vector3>[
        for (var v = 0; v < base.vertexSlotCount; v++)
          if (base.isVertexAlive(v)) base.positionOf(v),
      ];
      expect(after, before);
    });

    test('the result is a genuinely different, smoothed mesh', () {
      final base = const ParametricSphere(segments: 8, rings: 4).toEditMesh();
      const modifier = SmoothModifier(iterations: 5, preserveVolume: true);

      final result = modifier.apply(base, ModifierContext());
      result.validate();

      expect(result.vertexCount, base.vertexCount);
      expect(identical(result, base), isFalse);
    });

    test('round-trips through JSON', () {
      const modifier = SmoothModifier(
        iterations: 12,
        lambda: 0.3,
        preserveVolume: true,
      );
      final restored = modifierFromJson(modifier.toJson());

      expect(restored, isA<SmoothModifier>());
      final again = restored! as SmoothModifier;
      expect(again.iterations, 12);
      expect(again.lambda, 0.3);
      expect(again.preserveVolume, isTrue);
    });

    test('a modifier missing a required field is refused, not guessed', () {
      expect(
        modifierFromJson(<String, Object?>{'kind': 'smooth', 'lambda': 0.5}),
        isNull,
      );
    });

    test('lambda and preserveVolume default the way the constructor does '
        'when a caller omits them', () {
      final restored =
          modifierFromJson(<String, Object?>{
                'kind': 'smooth',
                'iterations': 7,
              })!
              as SmoothModifier;

      // Mutation: require `lambda`/`preserveVolume` in the same pattern as
      // `iterations` instead of defaulting them — an MCP tool call naming
      // only `iterations`, which this tool's own schema advertises as
      // enough on its own, would then be refused rather than answered.
      expect(restored.iterations, 7);
      expect(restored.lambda, 0.5);
      expect(restored.preserveVolume, isFalse);
    });
  });

  group('SubdivisionModifier', () {
    test('apply folds levels Catmull-Clark passes into the result', () {
      const modifier = SubdivisionModifier(levels: 2);
      final result = modifier.apply(EditMesh.cuboid(), ModifierContext());
      result.validate();

      // Mutation: call `catmullClark` with `levels: 1` regardless of the
      // field, or `subdivideSimple` instead of the smoothing one — either
      // way this stops matching two real Catmull-Clark levels of a cube.
      expect(
        result.vertexCount,
        catmullClark(EditMesh.cuboid(), levels: 2).vertexCount,
      );
    });

    test('never mutates its own base', () {
      final base = EditMesh.cuboid();
      final before = base.toBytes();

      const modifier = SubdivisionModifier(levels: 1);
      modifier.apply(base, ModifierContext());

      expect(base.toBytes(), before);
    });

    test('round-trips through JSON, viewLevels included', () {
      const modifier = SubdivisionModifier(levels: 3, viewLevels: 1);
      final restored = modifierFromJson(modifier.toJson());

      expect(restored, isA<SubdivisionModifier>());
      final again = restored! as SubdivisionModifier;
      expect(again.levels, 3);
      expect(again.viewLevels, 1);
    });

    test('a modifier missing levels is refused, not guessed', () {
      expect(
        modifierFromJson(<String, Object?>{
          'kind': 'subdivision',
          'viewLevels': 1,
        }),
        isNull,
      );
    });

    test('viewLevels defaults to levels when a caller omits it', () {
      const modifier = SubdivisionModifier(levels: 4);
      expect(modifier.viewLevels, 4);

      final restored =
          modifierFromJson(<String, Object?>{
                'kind': 'subdivision',
                'levels': 5,
              })!
              as SubdivisionModifier;

      // Mutation: leave `viewLevels` at some fixed default (0, say) instead
      // of mirroring `levels` — a caller that has never heard of the split,
      // which is every caller until a viewport actually reads this field,
      // would then see a viewport number that means nothing next to the
      // one it asked for.
      expect(restored.viewLevels, 5);
    });
  });

  group('BooleanModifier', () {
    test('apply combines the base with the resolved operand', () {
      final base = EditMesh.cuboid();
      final operand = EditMesh.cuboid();
      operand.beginStep();
      for (var v = 0; v < operand.vertexSlotCount; v++) {
        if (!operand.isVertexAlive(v)) continue;
        operand.moveVertex(v, operand.positionOf(v) + Vector3(0.5, 0.3, 0.2));
      }
      operand.endStep();

      final modifier = BooleanModifier(
        operation: CsgOperation.union,
        operandId: 7,
        operandTransform: Matrix4.identity(),
      );
      final result = modifier.apply(
        base,
        ModifierContext(operands: <int, EditMesh>{7: operand}),
      );

      // The same 1.72 `bsp_test.dart`'s own union test works out
      // analytically for this exact offset.
      expect(result.signedVolume, closeTo(1.72, 1e-6));
    });

    test('a missing operand passes the base through unchanged', () {
      final base = EditMesh.cuboid();
      final modifier = BooleanModifier(
        operation: CsgOperation.union,
        operandId: 7,
        operandTransform: Matrix4.identity(),
      );

      // Mutation: throw or build an empty mesh instead of passing `base`
      // through — this is the same answer a cycle a caller broke by
      // leaving the cyclic operand's own entry out gets.
      final result = modifier.apply(base, const ModifierContext());
      expect(identical(result, base), isTrue);
    });

    test('operandTransform is applied before combining, not after', () {
      final base = EditMesh.cuboid();
      // An operand cube still at the origin — the modifier's own
      // `operandTransform`, not the mesh's own position, has to carry it
      // to (0.5, 0.3, 0.2) for the same 1.72 union volume as the test
      // above, which moved the mesh directly instead.
      final operand = EditMesh.cuboid();

      final modifier = BooleanModifier(
        operation: CsgOperation.union,
        operandId: 3,
        operandTransform: Matrix4.translationValues(0.5, 0.3, 0.2),
      );
      final result = modifier.apply(
        base,
        ModifierContext(operands: <int, EditMesh>{3: operand}),
      );

      expect(result.signedVolume, closeTo(1.72, 1e-6));
    });

    test('never mutates its own base or the operand it was given', () {
      final base = EditMesh.cuboid();
      final beforeBase = base.toBytes();
      final operand = EditMesh.cuboid();
      final beforeOperand = operand.toBytes();

      BooleanModifier(
        operation: CsgOperation.subtract,
        operandId: 1,
        operandTransform: Matrix4.translationValues(0.1, 0, 0),
      ).apply(base, ModifierContext(operands: <int, EditMesh>{1: operand}));

      expect(base.toBytes(), beforeBase);
      expect(operand.toBytes(), beforeOperand);
    });

    test('round-trips through JSON, the matrix included', () {
      final modifier = BooleanModifier(
        operation: CsgOperation.intersect,
        operandId: 12,
        operandTransform: Matrix4.translationValues(1, 2, 3),
      );
      final restored = modifierFromJson(modifier.toJson());

      expect(restored, isA<BooleanModifier>());
      final again = restored! as BooleanModifier;
      expect(again.operation, CsgOperation.intersect);
      expect(again.operandId, 12);
      expect(again.operandTransform.storage, modifier.operandTransform.storage);
    });

    test('a modifier missing a required field is refused, not guessed', () {
      expect(
        modifierFromJson(<String, Object?>{
          'kind': 'boolean',
          'operation': 'union',
          'operandId': 1,
        }),
        isNull,
      );
    });

    test('an operation name this build does not have is refused', () {
      expect(
        modifierFromJson(<String, Object?>{
          'kind': 'boolean',
          'operation': 'xor',
          'operandId': 1,
          'operandTransform': Matrix4.identity().storage.toList(),
        }),
        isNull,
      );
    });

    test('a matrix that is not 16 numbers is refused', () {
      expect(
        modifierFromJson(<String, Object?>{
          'kind': 'boolean',
          'operation': 'union',
          'operandId': 1,
          'operandTransform': <double>[1, 2, 3],
        }),
        isNull,
      );
    });
  });
}
