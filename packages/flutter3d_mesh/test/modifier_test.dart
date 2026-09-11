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
}
