/// What an object's modifier stack actually produces, cached across calls.
///
///     dart test test/modifier_evaluation_cache_test.dart
///
/// `mat-18`'s own acceptance, checked directly: a mirror welds; toggling a
/// modifier off leaves the hash — and so the cache — alone if nothing else
/// about the stack changed; and repainting an object never invalidates its
/// evaluated mesh, since material is not part of what this is keyed on.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelObject editedCube({
  List<ModifierSlot> modifiers = const <ModifierSlot>[],
}) => ModelObject(
  id: 1,
  name: 'cube',
  geometry: EditedGeometry(EditMesh.cuboid()),
  transform: Matrix4.identity(),
  modifiers: modifiers,
);

void main() {
  group('ModifierEvaluationCache', () {
    test('a mirror modifier welds, through the cache the same as direct', () {
      final cache = ModifierEvaluationCache();
      final object = editedCube(
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: MirrorModifier(
              normal: Vector3(1, 0, 0),
              mergeDistance: 1e-6,
            ),
          ),
        ],
      );

      final result = cache.evaluatedMesh(object);
      expect(result, isNotNull);
      result!.validate();

      // A cuboid centred on the origin already straddles the mirror plane —
      // mirroring it welds the geometry back onto itself rather than
      // producing two disjoint boxes.
      // Mutation: build the ModifierStack from every slot rather than only
      // the enabled ones — with none disabled here that would not show up,
      // which is exactly why the "disabled" test below exists separately.
      expect(result.vertexCount, lessThan(16));
    });

    test('an object with no EditedGeometry has no evaluated mesh', () {
      final cache = ModifierEvaluationCache();
      final parametric = ModelObject(
        id: 1,
        name: 'lathe',
        geometry: ParametricGeometry(const ParametricCylinder()),
        transform: Matrix4.identity(),
      );
      expect(cache.evaluatedMesh(parametric), isNull);
    });

    test('an unchanged geometry answers the same mesh instance twice', () {
      final cache = ModifierEvaluationCache();
      final object = editedCube(
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
          ),
        ],
      );

      final first = cache.evaluatedMesh(object);
      final second = cache.evaluatedMesh(object);

      // Mutation: rebuild a fresh `ModifierStack` on every call instead of
      // keeping one per object — `ModifierStack.evaluate`'s own memoization
      // then never gets a chance to fire, and two calls that changed
      // nothing still fold twice.
      expect(identical(first, second), isTrue);
    });

    test('repainting the object never invalidates its evaluated mesh', () {
      final cache = ModifierEvaluationCache();
      final object = editedCube(
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
          ),
        ],
      );

      final before = cache.evaluatedMesh(object);
      final repainted = object.copyWith(materialSlots: <int>[0]);
      final after = cache.evaluatedMesh(repainted);

      // Mutation: key the cache on `object.version` instead of on
      // `object.geometry`'s own identity — `copyWith` bumps `version` on
      // every change, a repaint included, and the cache would recompute a
      // mesh that never actually changed.
      expect(identical(before, after), isTrue);
    });

    test(
      'editing a disabled modifier leaves the hash, and the cache, alone',
      () {
        final cache = ModifierEvaluationCache();
        final enabledSlot = ModifierSlot(
          modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
        );
        final object = editedCube(
          modifiers: <ModifierSlot>[
            enabledSlot,
            ModifierSlot(
              modifier: ArrayModifier(count: 5, offset: Vector3(9, 0, 0)),
              enabled: false,
            ),
          ],
        );

        final before = cache.evaluatedMesh(object);
        // The same geometry, the same enabled modifier — only the disabled
        // one's own fields moved. If the hash correctly ignores it, this is
        // a cache hit: the object's own `ModifierStack` is reused rather
        // than rebuilt, and `evaluate` on the identical base answers its own
        // memoized result rather than folding again.
        final edited = object.copyWith(
          modifiers: <ModifierSlot>[
            enabledSlot,
            ModifierSlot(
              modifier: ArrayModifier(count: 99, offset: Vector3(-3, 0, 0)),
              enabled: false,
            ),
          ],
        );
        final after = cache.evaluatedMesh(edited);

        // Mutation: hash every slot regardless of `enabled` — editing a
        // disabled modifier's own parameters would then change the hash for
        // no visible reason, forcing a fresh `ModifierStack` and a real
        // re-fold, which hands back a new, non-identical `EditMesh` even
        // though nothing about what actually runs changed.
        expect(identical(before, after), isTrue);
      },
    );

    test('enabling a previously-disabled modifier does change the result', () {
      final cache = ModifierEvaluationCache();
      final slot = ModifierSlot(
        modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
        enabled: false,
      );
      final disabled = editedCube(modifiers: <ModifierSlot>[slot]);
      final withoutModifier = cache.evaluatedMesh(disabled);

      final enabled = disabled.copyWith(
        geometry: EditedGeometry(EditMesh.cuboid()),
        modifiers: <ModifierSlot>[slot.copyWith(enabled: true)],
      );
      final withModifier = cache.evaluatedMesh(enabled);

      expect(withoutModifier!.vertexCount, 8);
      expect(withModifier!.vertexCount, 16);
    });

    test('forget drops what the cache remembers about an object', () {
      final cache = ModifierEvaluationCache();
      final object = editedCube(
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
          ),
        ],
      );
      final before = cache.evaluatedMesh(object);
      cache.forget(object.id);
      final after = cache.evaluatedMesh(object);

      // A fresh `ModifierStack` after `forget` folds again — a new,
      // non-identical result, even though nothing about `object` changed.
      expect(identical(before, after), isFalse);
    });
  });
}
