/// What an object's modifier stack actually produces, cached across calls.
///
///     dart test test/modifier_evaluation_cache_test.dart
///
/// `mat-18`'s own acceptance, checked directly: a mirror welds; toggling a
/// modifier off leaves the hash — and so the cache — alone if nothing else
/// about the stack changed; and repainting an object never invalidates its
/// evaluated mesh, since material is not part of what this is keyed on.
/// `mesh-48`'s own acceptance is checked here too, not only in
/// `flutter3d_mesh`'s own `modifier_test.dart`: a `BooleanModifier`'s operand
/// is a *project* concept (another object, found by id), so the cache path
/// that actually resolves one only exists at this layer.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelObject editedCube(
  int id, {
  List<ModifierSlot> modifiers = const <ModifierSlot>[],
  Vector3? offset,
}) => ModelObject(
  id: id,
  name: 'cube $id',
  geometry: EditedGeometry(_translatedCuboid(offset ?? Vector3.zero())),
  transform: Matrix4.identity(),
  modifiers: modifiers,
);

EditMesh _translatedCuboid(Vector3 offset) {
  final mesh = EditMesh.cuboid();
  mesh.beginStep();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (mesh.isVertexAlive(v)) mesh.moveVertex(v, mesh.positionOf(v) + offset);
  }
  mesh.endStep();
  return mesh;
}

ModelProject projectOf(List<ModelObject> objects) =>
    ModelProject(objects: objects, nextId: objects.length + 1);

void main() {
  group('ModifierEvaluationCache', () {
    test('a mirror modifier welds, through the cache the same as direct', () {
      final cache = ModifierEvaluationCache();
      final object = editedCube(
        1,
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: MirrorModifier(
              normal: Vector3(1, 0, 0),
              mergeDistance: 1e-6,
            ),
          ),
        ],
      );

      final result = cache.evaluatedMesh(
        projectOf(<ModelObject>[object]),
        object,
      );
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
      expect(
        cache.evaluatedMesh(projectOf(<ModelObject>[parametric]), parametric),
        isNull,
      );
    });

    test('an unchanged geometry answers the same mesh instance twice', () {
      final cache = ModifierEvaluationCache();
      final object = editedCube(
        1,
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
          ),
        ],
      );
      final project = projectOf(<ModelObject>[object]);

      final first = cache.evaluatedMesh(project, object);
      final second = cache.evaluatedMesh(project, object);

      // Mutation: rebuild a fresh `ModifierStack` on every call instead of
      // keeping one per object — `ModifierStack.evaluate`'s own memoization
      // then never gets a chance to fire, and two calls that changed
      // nothing still fold twice.
      expect(identical(first, second), isTrue);
    });

    test('repainting the object never invalidates its evaluated mesh', () {
      final cache = ModifierEvaluationCache();
      final object = editedCube(
        1,
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
          ),
        ],
      );
      final project = projectOf(<ModelObject>[object]);

      final before = cache.evaluatedMesh(project, object);
      final repainted = object.copyWith(materialSlots: <int>[0]);
      final after = cache.evaluatedMesh(
        projectOf(<ModelObject>[repainted]),
        repainted,
      );

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
          1,
          modifiers: <ModifierSlot>[
            enabledSlot,
            ModifierSlot(
              modifier: ArrayModifier(count: 5, offset: Vector3(9, 0, 0)),
              enabled: false,
            ),
          ],
        );

        final before = cache.evaluatedMesh(
          projectOf(<ModelObject>[object]),
          object,
        );
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
        final after = cache.evaluatedMesh(
          projectOf(<ModelObject>[edited]),
          edited,
        );

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
      final disabled = editedCube(1, modifiers: <ModifierSlot>[slot]);
      final withoutModifier = cache.evaluatedMesh(
        projectOf(<ModelObject>[disabled]),
        disabled,
      );

      final enabled = disabled.copyWith(
        geometry: EditedGeometry(EditMesh.cuboid()),
        modifiers: <ModifierSlot>[slot.copyWith(enabled: true)],
      );
      final withModifier = cache.evaluatedMesh(
        projectOf(<ModelObject>[enabled]),
        enabled,
      );

      expect(withoutModifier!.vertexCount, 8);
      expect(withModifier!.vertexCount, 16);
    });

    test('forget drops what the cache remembers about an object', () {
      final cache = ModifierEvaluationCache();
      final object = editedCube(
        1,
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: ArrayModifier(count: 2, offset: Vector3(2, 0, 0)),
          ),
        ],
      );
      final project = projectOf(<ModelObject>[object]);
      final before = cache.evaluatedMesh(project, object);
      cache.forget(object.id);
      final after = cache.evaluatedMesh(project, object);

      // A fresh `ModifierStack` after `forget` folds again — a new,
      // non-identical result, even though nothing about `object` changed.
      expect(identical(before, after), isFalse);
    });
  });

  group('BooleanModifier: the operand is another object, resolved here', () {
    test('combining two objects by id gives the analytically-known volume', () {
      final cache = ModifierEvaluationCache();
      final a = editedCube(1);
      final b = editedCube(2, offset: Vector3(0.5, 0.3, 0.2));
      final withBoolean = a.copyWith(
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: BooleanModifier(
              operation: CsgOperation.union,
              operandId: 2,
              operandTransform: Matrix4.identity(),
            ),
          ),
        ],
      );
      final project = projectOf(<ModelObject>[withBoolean, b]);

      final result = cache.evaluatedMesh(project, withBoolean);
      expect(result, isNotNull);
      // The same 1.72 `bsp_test.dart`'s own union test works out
      // analytically for this exact offset — resolved here from a real
      // project with two real objects, not handed in directly.
      expect(result!.signedVolume, closeTo(1.72, 1e-6));
    });

    test('the operand\'s own modifier stack runs before it is combined', () {
      final cache = ModifierEvaluationCache();
      final operand = editedCube(
        2,
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: ArrayModifier(count: 2, offset: Vector3(3, 0, 0)),
          ),
        ],
      );
      final base = editedCube(
        1,
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: BooleanModifier(
              operation: CsgOperation.union,
              operandId: 2,
              // Far enough away that the base and the (now two-cube-wide)
              // operand array do not overlap at all — the union is then
              // just the sum, which only matches if the operand really did
              // fold its own ArrayModifier before the union ran.
              operandTransform: Matrix4.translationValues(10, 0, 0),
            ),
          ),
        ],
      );
      final project = projectOf(<ModelObject>[base, operand]);

      final result = cache.evaluatedMesh(project, base);
      expect(result, isNotNull);
      // Mutation: pass the operand's own raw base mesh instead of its
      // evaluated one, and this reads 2.0 (1 + 1) instead of 3.0 (1 + 2)
      // — the operand's own array never ran.
      expect(result!.signedVolume, closeTo(3.0, 1e-6));
    });

    test('changing the operand\'s own geometry is seen without this '
        'object\'s own base moving at all', () {
      final cache = ModifierEvaluationCache();
      var operand = editedCube(2, offset: Vector3(10, 0, 0));
      final base = editedCube(
        1,
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: BooleanModifier(
              operation: CsgOperation.union,
              operandId: 2,
              operandTransform: Matrix4.identity(),
            ),
          ),
        ],
      );

      final before = cache.evaluatedMesh(
        projectOf(<ModelObject>[base, operand]),
        base,
      );
      expect(before!.signedVolume, closeTo(2.0, 1e-6));

      // The operand grows to a 2×2×2 cube, still centred where it was
      // (10, 0, 0), so the two stay disjoint and the volume is a plain sum
      // — a real edit to *that* object, with `base`'s own geometry never
      // touched.
      final biggerOperand = EditMesh.cuboid(size: Vector3(2, 2, 2));
      biggerOperand.beginStep();
      for (var v = 0; v < biggerOperand.vertexSlotCount; v++) {
        if (biggerOperand.isVertexAlive(v)) {
          biggerOperand.moveVertex(
            v,
            biggerOperand.positionOf(v) + Vector3(10, 0, 0),
          );
        }
      }
      biggerOperand.endStep();
      operand = operand.copyWith(geometry: EditedGeometry(biggerOperand));
      final after = cache.evaluatedMesh(
        projectOf(<ModelObject>[base, operand]),
        base,
      );

      // Mutation: cache `base`'s own combined result on `base.geometry`'s
      // identity alone (the pre-`mesh-48` behaviour) — `base.geometry`
      // never changed here, so this would still read 2.0, the stale answer,
      // instead of 9.0 (1 + 8).
      expect(after!.signedVolume, closeTo(9.0, 1e-6));
    });

    test('a direct cycle (A references B, B references A) breaks rather '
        'than hanging', () {
      final cache = ModifierEvaluationCache();
      final a = editedCube(
        1,
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: BooleanModifier(
              operation: CsgOperation.union,
              operandId: 2,
              operandTransform: Matrix4.translationValues(0.5, 0.3, 0.2),
            ),
          ),
        ],
      );
      final b = editedCube(
        2,
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: BooleanModifier(
              operation: CsgOperation.union,
              operandId: 1,
              operandTransform: Matrix4.translationValues(-0.5, -0.3, -0.2),
            ),
          ),
        ],
      );
      final project = projectOf(<ModelObject>[a, b]);

      // Mutation: drop the `resolving` guard entirely — this call would
      // recurse forever (A resolves B, B resolves A, A resolves B, …) and
      // the test itself would hang rather than fail cleanly.
      final result = cache.evaluatedMesh(project, a);
      expect(result, isNotNull);

      // A's own union with B still ran (B contributed its own base, since
      // the link back to A was the one broken) — this is not "a full
      // refusal," it is "the one link that would close the loop is inert."
      expect(result!.signedVolume, closeTo(1.72, 1e-6));
    });

    test('an object naming itself as its own operand does not hang either', () {
      final cache = ModifierEvaluationCache();
      final selfReferencing = editedCube(
        1,
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: BooleanModifier(
              operation: CsgOperation.union,
              operandId: 1,
              operandTransform: Matrix4.identity(),
            ),
          ),
        ],
      );
      final project = projectOf(<ModelObject>[selfReferencing]);

      final result = cache.evaluatedMesh(project, selfReferencing);
      expect(result, isNotNull);
      // The self-link is inert, same as a missing operand: the object
      // passes through unmodified.
      expect(result!.signedVolume, closeTo(1.0, 1e-6));
    });

    test('an operandId naming an object the project does not have is '
        'inert, not a crash', () {
      final cache = ModifierEvaluationCache();
      final object = editedCube(
        1,
        modifiers: <ModifierSlot>[
          ModifierSlot(
            modifier: BooleanModifier(
              operation: CsgOperation.union,
              operandId: 999,
              operandTransform: Matrix4.identity(),
            ),
          ),
        ],
      );
      final result = cache.evaluatedMesh(
        projectOf(<ModelObject>[object]),
        object,
      );
      expect(result!.signedVolume, closeTo(1.0, 1e-6));
    });
  });
}
