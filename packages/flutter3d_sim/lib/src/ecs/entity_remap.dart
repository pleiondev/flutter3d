/// `rp-03`'s second half: an [EcsWorld] save, carried from the entity
/// indices a run had when it was recorded to the indices a *reloaded* level
/// hands out — by name, dropping what the new level does not have, rather
/// than misattributing one entity's state to whichever other one now
/// happens to sit at its old index.
///
/// **Why [EcsWorld] itself does not need to change for this.** Its own
/// `restore` already accepts any document shaped like one of its own
/// `save()`s; nothing about the class cares whether that document was
/// produced by *this* call to `save()` or assembled by hand from an older
/// one. So the remap is a document transform that sits in front of
/// `restore`, not a change to what `restore` does — the same reason
/// `flutter3d_sim` has stayed a plain-Dart package this whole plan: state
/// that is *just JSON* can be reshaped by code that never has to touch the
/// class that reads it.
///
/// **Why a name, and not the index [EcsWorld] already assigns.** The index
/// is `EcsWorld`'s own allocation — the next free slot when [ActorSystem]
/// or a game's own spawn code called `spawn()` — and a level edited to add,
/// remove or reorder an entity changes which slot every actor after the
/// edit gets, even though nothing about *them* changed. A name is the one
/// thing that survives the edit: `EntityDef.name` in the level document, and
/// whatever the caller attached the same name to when it spawned the actor
/// that index became.
///
/// **What this does not do.** It does not discover names on its own —
/// `EcsWorld` has never carried one, and a caller here is one that already
/// knows, for each save, which index went with which name. Wiring an actual
/// game's `MonsterKind.spawn()` to record that association is `rp-03`'s
/// remaining work; what is here is the transform that association makes
/// possible once it exists, proven against the shapes `EcsWorld.save` and
/// `EcsWorld.restore` actually use.
library;

/// The result of [remapEntitySave]: a document [EcsWorld.restore] can read,
/// and the names it could not place.
typedef EntityRemap = ({Map<String, Object?> save, List<String> dropped});

/// Rewrites [saved] — an [EcsWorld.save] document — from the entity indices
/// it was written at to the ones [newNames] hands out, matching by name.
///
/// [oldNames] and [newNames] both say "the entity at this index was called
/// this", index by position, with a null for an entity nobody named. An
/// entity in [saved] whose old index has no name, or whose name is not in
/// [newNames], is left out of the result and reported in [EntityRemap.dropped]
/// — a monster the edited level no longer has, or a component saved against
/// an index this transform was never told the name of, are the same kind of
/// gap and are reported the same way. [newGenerations] and [newFree] are
/// carried through unchanged: they describe the *new* world's own entities,
/// which this transform does not create or destroy, only relabel.
EntityRemap remapEntitySave(
  Map<String, Object?> saved, {
  required List<String?> oldNames,
  required List<String?> newNames,
  required List<int> newGenerations,
  required List<int> newFree,
}) {
  final nameToNewIndex = <String, int>{};
  for (var i = 0; i < newNames.length; i++) {
    final name = newNames[i];
    if (name != null) nameToNewIndex[name] = i;
  }

  // A `Set`, not a `List`: an entity is one row per component type it has,
  // and a monster with health, a facing and a brain would otherwise be
  // reported dropped three times over — once per type that lost its row,
  // rather than once for the entity a person actually wants named.
  final dropped = <String>{};
  final remappedComponents = <String, Object?>{};
  final components = saved['components'];
  if (components is Map) {
    for (final entry in components.entries) {
      final type = entry.key;
      final rows = entry.value;
      if (type is! String || rows is! Map) continue;
      final newRows = <String, Object?>{};
      for (final row in rows.entries) {
        final oldIndex = int.tryParse('${row.key}');
        final name = (oldIndex != null && oldIndex >= 0 && oldIndex < oldNames.length)
            ? oldNames[oldIndex]
            : null;
        if (name == null) {
          dropped.add('$type#${row.key} (no name recorded for it)');
          continue;
        }
        final newIndex = nameToNewIndex[name];
        if (newIndex == null) {
          dropped.add(name);
          continue;
        }
        newRows['$newIndex'] = row.value;
      }
      if (newRows.isNotEmpty) remappedComponents[type] = newRows;
    }
  }

  return (
    save: <String, Object?>{
      'generations': List<int>.of(newGenerations),
      'free': List<int>.of(newFree),
      'components': remappedComponents,
    },
    dropped: List<String>.unmodifiable(dropped),
  );
}
