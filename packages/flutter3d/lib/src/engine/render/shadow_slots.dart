/// Deciding which lights get a row of the cube shadow atlas.
///
/// Split out of the renderer and free of any GPU type on purpose: who deserves
/// a shadow is a question about relevance and hysteresis, both of which have
/// edge cases worth testing, and none of which needs a device to answer.
library;

// Re-exported so an existing import of this file keeps seeing
// `ShadowFaceScheduler`: it moved to its own file because deciding which
// atlas *rows* lights hold and deciding which *faces* of an occupied row get
// redrawn are two different questions with no shared state between them, not
// because a user of either should now import two files instead of one.
export 'shadow_face_scheduler.dart';

/// A light asking for a row this frame.
final class ShadowCandidate {
  const ShadowCandidate({
    required this.light,
    required this.priority,
    required this.bakeKey,
  });

  /// Identity, compared by `identical`. The renderer passes the `LightNode`.
  ///
  /// Identity rather than an index, because an index is a position in a list
  /// that is rebuilt every frame: a light that vanishes renumbers every light
  /// behind it, and a cache keyed on the number would quietly hand one light's
  /// baked walls to another.
  final Object light;

  /// How much this light deserves a row. Higher wins; zero or less never gets
  /// one.
  ///
  /// The renderer supplies screen-space size, which is PlayCanvas's rule and a
  /// good one: a torch filling the view matters more than a brighter one two
  /// rooms away.
  final double priority;

  /// What a static bake of this light would capture — its position and range,
  /// quantised.
  ///
  /// Compared, never interpreted. When it changes, the walls baked for this
  /// light are walls seen from somewhere it no longer is.
  final int bakeKey;
}

/// Who owns which row, and whether the static atlas is stale.
final class ShadowAssignment {
  const ShadowAssignment({required this.owners, required this.staticDirty});

  /// Per slot: the light holding it, or null when the row is unused. Ordered by
  /// slot, so `owners[2]` is atlas row two.
  final List<Object?> owners;

  /// Whether the static atlas no longer matches [owners].
  ///
  /// True when a row changed hands or its owner moved. The renderer must then
  /// re-bake **every** occupied row, not just the changed one: a pass clears
  /// its whole colour attachment, so a pass that redraws one row erases the
  /// others. That is the bug this whole subsystem was built out of.
  final bool staticDirty;

  int get occupied {
    var n = 0;
    for (final owner in owners) {
      if (owner != null) n++;
    }
    return n;
  }
}

/// Hands out atlas rows, and tries hard not to move them.
///
/// Two properties matter more than picking the very best four lights:
///
/// * **A light keeps its row.** Every change of ownership costs a full static
///   re-bake — six views of the level's static geometry per occupied row —
///   because rows cannot be redrawn individually.
/// * **Changes are rare and bounded.** One swap per frame at most, and only for
///   a challenger that clearly beats the weakest incumbent. Without both, a
///   player turning on the spot makes two lights trade a row every frame and
///   the bake runs for ever, which is worse than having no bake at all.
final class ShadowSlotAllocator {
  ShadowSlotAllocator({required this.slotCount, this.hysteresis = 1.25})
      : assert(slotCount >= 0),
        assert(hysteresis >= 1.0,
            'a hysteresis below one would evict an incumbent for a challenger '
            'that is worse than it, which is the thrash this exists to stop'),
        _owners = List<Object?>.filled(slotCount, null),
        _priorities = List<double>.filled(slotCount, 0.0),
        _bakeKeys = List<int?>.filled(slotCount, null),
        _bakedOwners = List<Object?>.filled(slotCount, null),
        _bakedKeys = List<int?>.filled(slotCount, null);

  /// Rows in the atlas.
  final int slotCount;

  /// How much better a challenger must be before it takes an incumbent's row.
  ///
  /// A ratio, not a difference, because priority is a screen-space size and its
  /// scale changes with the scene. At 1.25 a light must look a quarter larger
  /// than the one it displaces.
  final double hysteresis;

  final List<Object?> _owners;
  final List<double> _priorities;
  final List<int?> _bakeKeys;

  // What the static atlas actually holds, which is only the same as _owners
  // once the renderer says it has baked.
  final List<Object?> _bakedOwners;
  final List<int?> _bakedKeys;

  /// The row [light] holds, or null.
  int? slotOf(Object light) {
    for (var i = 0; i < slotCount; i++) {
      if (identical(_owners[i], light)) return i;
    }
    return null;
  }

  /// Decides this frame's rows.
  ///
  /// [candidates] may be in any order and longer than [slotCount]. Ties are
  /// broken by position in the list rather than left to the sort, because
  /// `List.sort` is not stable in Dart and two lights of equal size would
  /// otherwise swap rows between frames on nothing but sort order — a re-bake
  /// per frame, caused entirely by an implementation detail.
  ShadowAssignment assign(List<ShadowCandidate> candidates) {
    final ranked = <_Ranked>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      if (candidate.priority <= 0.0) continue;
      ranked.add(_Ranked(candidate, i));
    }
    ranked.sort((a, b) {
      final byPriority = b.candidate.priority.compareTo(a.candidate.priority);
      return byPriority != 0 ? byPriority : a.order.compareTo(b.order);
    });

    // Incumbents first: anything still asking keeps the row it had.
    final held = <int>{};
    final placed = <Object>{};
    for (final entry in ranked) {
      final slot = slotOf(entry.candidate.light);
      if (slot == null) continue;
      held.add(slot);
      placed.add(entry.candidate.light);
      _priorities[slot] = entry.candidate.priority;
      _bakeKeys[slot] = entry.candidate.bakeKey;
    }

    // Anything that stopped asking loses its row. Free, because an empty row
    // costs nothing to leave stale — the shader reads it only through a slot
    // table that no longer points at it.
    for (var i = 0; i < slotCount; i++) {
      if (_owners[i] != null && !held.contains(i)) {
        _owners[i] = null;
        _priorities[i] = 0.0;
        _bakeKeys[i] = null;
      }
    }

    // Free rows go to the best of the rest.
    for (final entry in ranked) {
      if (placed.contains(entry.candidate.light)) continue;
      final free = _firstFreeSlot();
      if (free == null) break;
      _owners[free] = entry.candidate.light;
      _priorities[free] = entry.candidate.priority;
      _bakeKeys[free] = entry.candidate.bakeKey;
      placed.add(entry.candidate.light);
    }

    // At most one eviction, and only for a challenger that clearly wins. One,
    // because each costs a full re-bake and a frame that swapped two rows would
    // pay twice for a difference nobody can see.
    for (final entry in ranked) {
      if (placed.contains(entry.candidate.light)) continue;
      final weakest = _weakestSlot();
      if (weakest == null) break;
      if (entry.candidate.priority <= _priorities[weakest] * hysteresis) break;
      _owners[weakest] = entry.candidate.light;
      _priorities[weakest] = entry.candidate.priority;
      _bakeKeys[weakest] = entry.candidate.bakeKey;
      break;
    }

    return ShadowAssignment(
      owners: List<Object?>.unmodifiable(_owners),
      staticDirty: _isStaticDirty(),
    );
  }

  /// Records that the static atlas has just been drawn for the current rows.
  ///
  /// Separate from [assign] because the bake can be skipped — shadows switched
  /// off, no device, an early return — and a dirty flag cleared by deciding
  /// rather than by drawing is a flag that lies. It stays set until something
  /// actually draws.
  void recordStaticBake() {
    for (var i = 0; i < slotCount; i++) {
      _bakedOwners[i] = _owners[i];
      _bakedKeys[i] = _bakeKeys[i];
    }
  }

  /// Drops every row and forgets what was baked.
  ///
  /// For a new level or a reallocated atlas: the texture that held those rows
  /// is gone, so claiming anything about its contents would be a guess.
  void reset() {
    for (var i = 0; i < slotCount; i++) {
      _owners[i] = null;
      _priorities[i] = 0.0;
      _bakeKeys[i] = null;
      _bakedOwners[i] = null;
      _bakedKeys[i] = null;
    }
  }

  bool _isStaticDirty() {
    for (var i = 0; i < slotCount; i++) {
      if (!identical(_bakedOwners[i], _owners[i])) return true;
      if (_owners[i] != null && _bakedKeys[i] != _bakeKeys[i]) return true;
    }
    return false;
  }

  int? _firstFreeSlot() {
    for (var i = 0; i < slotCount; i++) {
      if (_owners[i] == null) return i;
    }
    return null;
  }

  int? _weakestSlot() {
    int? weakest;
    for (var i = 0; i < slotCount; i++) {
      if (_owners[i] == null) continue;
      if (weakest == null || _priorities[i] < _priorities[weakest]) weakest = i;
    }
    return weakest;
  }
}

final class _Ranked {
  const _Ranked(this.candidate, this.order);
  final ShadowCandidate candidate;
  final int order;
}
