/// What [ModelObject.modifiers] actually produces, cached across calls.
library;

import 'dart:convert';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

import 'modifier_slot.dart';
import 'project.dart';

final class _CacheEntry {
  _CacheEntry({required this.modifiersHash, required this.stack});

  final int modifiersHash;
  final ModifierStack stack;
}

/// [evaluatedMesh] for whichever objects have asked, kept across calls so
/// that asking twice about an object nothing has touched costs one fold, not
/// two.
///
/// **Keyed on the *identity* of [ModelObject.geometry], not on
/// [ModelObject.version].** `version` is bumped by every edit — a rename, a
/// repaint, a moved transform — and this cache exists precisely so that none
/// of those force a re-fold. `geometry`'s own identity is the narrower
/// signal: every mesh-editing command already hands back `object.copyWith(
/// geometry: EditedGeometry(target.mesh))` — a *new* wrapper round the same,
/// in-place-mutated `EditMesh` — so `identical(a.geometry, b.geometry)` is
/// true exactly when nothing about the shape changed, and false exactly when
/// something did. A command that only repaints or renames never touches
/// `.geometry` at all, so it never invalidates this.
///
/// **The hash counts only the modifiers that are actually enabled.** A
/// disabled modifier does not run — see `ModifierSlot`'s own doc comment for
/// why `enabled` lives there rather than on `Modifier` — so editing one
/// while it is off changes nothing about what this cache would compute, and
/// the hash agrees: two stacks that differ only in a disabled slot's own
/// fields hash the same.
///
/// **Not every [Geometry] is supported yet.** Only [EditedGeometry] has an
/// [EditMesh] a [Modifier] can run over; [evaluatedMesh] answers null for a
/// parametric or imported object rather than guessing at a conversion
/// nothing has asked for.
///
/// **[BooleanModifier]'s own operand is resolved here, recursively, from
/// [project] — this is the "caller" its own doc comment in `flutter3d_mesh`
/// points at.** Resolving an operand means evaluating *that* object's own
/// modifier stack too, through this same cache, so an operand with its own
/// modifiers (including its own `BooleanModifier`) is combined already
/// folded, not as its raw base. A cycle — two objects each naming the other,
/// directly or through a longer chain, including an object naming itself —
/// is broken rather than refused loudly: the object already being resolved
/// when its own id comes back around simply has no entry in
/// [ModifierContext.operands] for that link, which every [BooleanModifier]
/// already treats as nothing to combine with (see its own doc comment). The
/// object that closes the loop still evaluates — with that one modifier
/// inert — rather than the whole recursion refusing to answer at all.
final class ModifierEvaluationCache {
  final Map<int, _CacheEntry> _byObjectId = <int, _CacheEntry>{};

  /// The mesh [object]'s modifier stack produces over its own base geometry,
  /// resolving any [BooleanModifier] operand against [project], or null when
  /// [object] has no [EditedGeometry] to run one over.
  EditMesh? evaluatedMesh(ModelProject project, ModelObject object) =>
      _evaluatedMesh(project, object, const <int>{});

  EditMesh? _evaluatedMesh(
    ModelProject project,
    ModelObject object,
    Set<int> resolving,
  ) {
    final EditMesh? base = switch (object.geometry) {
      final EditedGeometry g => g.mesh,
      _ => null,
    };
    if (base == null) return null;

    final enabled = <Modifier>[
      for (final ModifierSlot slot in object.modifiers)
        if (slot.enabled) slot.modifier,
    ];

    final int hash = _hashOf(object.modifiers);
    _CacheEntry? entry = _byObjectId[object.id];
    if (entry == null || entry.modifiersHash != hash) {
      entry = _CacheEntry(modifiersHash: hash, stack: ModifierStack(enabled));
      _byObjectId[object.id] = entry;
    }

    final stillResolving = <int>{...resolving, object.id};
    final operands = <int, EditMesh>{};
    for (final Modifier modifier in enabled) {
      if (modifier is! BooleanModifier) continue;
      if (stillResolving.contains(modifier.operandId)) {
        continue; // A cycle closing here: leave this link unresolved.
      }
      final ModelObject? operandObject = project[modifier.operandId];
      if (operandObject == null) continue;
      final EditMesh? operandMesh = _evaluatedMesh(
        project,
        operandObject,
        stillResolving,
      );
      if (operandMesh != null) operands[modifier.operandId] = operandMesh;
    }

    return entry.stack.evaluate(base, ModifierContext(operands: operands));
  }

  /// Drops whatever this remembers about [objectId], so a project that
  /// deletes an object with a heavy modifier stack does not keep its last
  /// evaluated mesh alive for nothing.
  void forget(int objectId) => _byObjectId.remove(objectId);

  int _hashOf(List<ModifierSlot> modifiers) => Object.hashAll(<String>[
    for (final ModifierSlot slot in modifiers)
      if (slot.enabled) jsonEncode(slot.modifier.toJson()),
  ]);
}
