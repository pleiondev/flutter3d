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
final class ModifierEvaluationCache {
  final Map<int, _CacheEntry> _byObjectId = <int, _CacheEntry>{};

  /// The mesh [object]'s modifier stack produces over its own base geometry,
  /// or null when [object] has no [EditedGeometry] to run one over.
  EditMesh? evaluatedMesh(ModelObject object) {
    final EditMesh? base = switch (object.geometry) {
      final EditedGeometry g => g.mesh,
      _ => null,
    };
    if (base == null) return null;

    final int hash = _hashOf(object.modifiers);
    _CacheEntry? entry = _byObjectId[object.id];
    if (entry == null || entry.modifiersHash != hash) {
      entry = _CacheEntry(
        modifiersHash: hash,
        stack: ModifierStack(<Modifier>[
          for (final ModifierSlot slot in object.modifiers)
            if (slot.enabled) slot.modifier,
        ]),
      );
      _byObjectId[object.id] = entry;
    }
    return entry.stack.evaluate(base, const ModifierContext());
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
