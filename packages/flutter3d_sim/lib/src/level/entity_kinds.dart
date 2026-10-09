import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'entity_kind.dart';

/// The entities a level may name: the slot [EntityKinds] fills, whose
/// `registry()` is the `EntityRegistry` a level is validated and spawned
/// against.
///
/// **Declared by the package that fills it.** It was a marker in
/// `flutter3d_plugin_api` until 1.0.0-rc.1, which named a slot nothing in
/// the contract used.
abstract base class EntityKindRegistry extends PluginRegistry {
  const EntityKindRegistry();
}

/// The entity kinds one engine knows, filled by the plugins installed in it:
/// the level format's half of the plugin host.
///
/// **The slot `EntityKindRegistry` names, filled.** A genre plugin adds the
/// kinds its levels may name in `install` — a spawn point, a coin, a car's
/// start — and they go again when the plugin is switched off. [registry] is
/// what a level is validated and spawned against: the kinds as they stand,
/// in the order they were added, the application's own first.
///
/// ## Two plugins and one type name
///
/// A type name means one thing in one engine, so a second claim on it is
/// settled by what is claimed:
///
/// * **The same kind is shared.** Two genres that both speak the format's
///   `door` hand in the same `const DoorKind()`, which is one object however
///   often it is written; the second [add] holds it beside the first rather
///   than throwing, and the type stays until the last holder lets go. "The
///   same" is `==`, identity unless a kind says otherwise, so a kind built at
///   run time (a `LightFixtureKind` with its size) is shared only when the
///   very same object is handed in twice.
/// * **A different kind is refused** with an [ArgumentError] naming both
///   claimants — two genres whose `key` spawns different things cannot both
///   be what a level's `key` means — unless the second one is added with
///   [replace]: then it stands over the first for as long as it is held, and
///   the first is back when it goes. That is `GenrePlugin.replaceKinds`.
///
/// One per engine, handed to the loop among its registries:
/// `EngineLoop(registries: [kinds], plugins: [...])`. Nothing here is
/// global; two engines in one process have two of these.
final class EntityKinds extends EntityKindRegistry {
  /// A registry holding [kinds], added by the application.
  EntityKinds([Iterable<EntityKind> kinds = const <EntityKind>[]]) {
    kinds.forEach(add);
  }

  final List<_Added> _kinds = <_Added>[];

  /// Every type name known, in the order it was added.
  List<String> get types => <String>[for (final k in _kinds) k.kind.type];

  /// Whether a kind is registered under [type].
  bool knows(String type) => _kinds.any((k) => k.kind.type == type);

  /// The kind registered under [type], or null.
  EntityKind? operator [](String type) => _at(type)?.kind;

  /// Which plugin added [type], `'app'` for the application, or null when
  /// nothing did. Of a shared kind, the first holder still holding it.
  String? ownerOf(String type) => _at(type)?.owners.first;

  /// Every holder of [type], first to last: one for a kind nobody shares.
  List<String> holdersOf(String type) =>
      List<String>.unmodifiable(_at(type)?.owners ?? const <String>[]);

  /// Adds [kind] for the application, or shares it when the same kind is
  /// already there. Throws an [ArgumentError] naming who holds its type when
  /// a different kind does.
  Registration add(EntityKind kind) => _add(kind, null);

  /// Adds every one of [kinds]; one registration takes them all out again.
  Registration addAll(Iterable<EntityKind> kinds) => _addAll(kinds, null);

  /// Puts [kind] over whatever holds its type, for as long as the returned
  /// registration is held; cancelling it brings back what it replaced. With
  /// nothing under the type it is an [add].
  Registration replace(EntityKind kind) => _replace(kind, null);

  /// [replace] for every one of [kinds]; one registration restores them all.
  Registration replaceAll(Iterable<EntityKind> kinds) =>
      _replaceAll(kinds, null);

  _Added? _at(String type) =>
      _kinds.where((k) => k.kind.type == type).firstOrNull;

  Registration _addAll(Iterable<EntityKind> kinds, PluginScope? scope) =>
      _all(<Registration>[for (final kind in kinds) _add(kind, scope)]);

  Registration _replaceAll(Iterable<EntityKind> kinds, PluginScope? scope) =>
      _all(<Registration>[for (final kind in kinds) _replace(kind, scope)]);

  static Registration _all(List<Registration> added) => Registration(() {
    for (final registration in added.reversed) {
      registration.cancel();
    }
  });

  Registration _add(EntityKind kind, PluginScope? scope) {
    final owner = scope?.manifest.id ?? 'app';
    final existing = _at(kind.type);
    if (existing != null) {
      if (existing.kind != kind) {
        throw ArgumentError.value(
          kind.type,
          'kind',
          'the entity type "${kind.type}" is added by ${existing.owners.first} '
              '(${existing.kind.runtimeType}) and again by $owner '
              '(${kind.runtimeType}); a type name is one kind in one engine — '
              'hand in the same kind to share it, or replace it',
        );
      }
      // The same word, spoken by a second holder.
      existing.owners.add(owner);
      return _tracked(Registration(() => _release(existing, owner)), scope);
    }
    final entry = _Added(kind, owner);
    _kinds.add(entry);
    return _tracked(Registration(() => _release(entry, owner)), scope);
  }

  Registration _replace(EntityKind kind, PluginScope? scope) {
    final owner = scope?.manifest.id ?? 'app';
    final existing = _at(kind.type);
    if (existing == null) return _add(kind, scope);
    final entry = _Added(kind, owner)..shadowed = existing;
    _kinds[_kinds.indexOf(existing)] = entry;
    return _tracked(Registration(() => _release(entry, owner)), scope);
  }

  static Registration _tracked(Registration registration, PluginScope? scope) {
    scope?.track(registration);
    return registration;
  }

  /// [owner] lets go of [entry]; the last to let go takes it out, and what it
  /// had replaced comes back in its place.
  void _release(_Added entry, String owner) {
    entry.owners.remove(owner);
    if (entry.owners.isNotEmpty) return;
    final at = _kinds.indexOf(entry);
    if (at >= 0) {
      final under = entry.shadowed;
      if (under == null) {
        _kinds.removeAt(at);
      } else {
        _kinds[at] = under;
      }
      return;
    }
    // Replaced itself meanwhile: unthread it from under whoever stands on it.
    for (final visible in _kinds) {
      var above = visible;
      while (above.shadowed != null && !identical(above.shadowed, entry)) {
        above = above.shadowed!;
      }
      if (identical(above.shadowed, entry)) {
        above.shadowed = entry.shadowed;
        return;
      }
    }
  }

  /// The kinds as they stand, as the registry a level is validated and
  /// spawned against.
  EntityRegistry registry() =>
      EntityRegistry(<EntityKind>[for (final k in _kinds) k.kind]);

  @override
  EntityKinds forPlugin(PluginScope scope) => _ScopedKinds(this, scope);
}

final class _ScopedKinds extends EntityKinds {
  _ScopedKinds(this._kindsOf, this._scope);

  final EntityKinds _kindsOf;
  final PluginScope _scope;

  @override
  List<String> get types => _kindsOf.types;

  @override
  bool knows(String type) => _kindsOf.knows(type);

  @override
  EntityKind? operator [](String type) => _kindsOf[type];

  @override
  String? ownerOf(String type) => _kindsOf.ownerOf(type);

  @override
  List<String> holdersOf(String type) => _kindsOf.holdersOf(type);

  @override
  Registration add(EntityKind kind) => _kindsOf._add(kind, _scope);

  @override
  Registration addAll(Iterable<EntityKind> kinds) =>
      _kindsOf._addAll(kinds, _scope);

  @override
  Registration replace(EntityKind kind) => _kindsOf._replace(kind, _scope);

  @override
  Registration replaceAll(Iterable<EntityKind> kinds) =>
      _kindsOf._replaceAll(kinds, _scope);

  @override
  EntityRegistry registry() => _kindsOf.registry();

  @override
  EntityKinds forPlugin(PluginScope scope) => _kindsOf.forPlugin(scope);
}

final class _Added {
  _Added(this.kind, String owner) : owners = <String>[owner];

  final EntityKind kind;

  /// Who holds it, first to last; more than one for a shared kind.
  final List<String> owners;

  /// What it was put over by `replace`, which comes back when it goes.
  _Added? shadowed;
}
