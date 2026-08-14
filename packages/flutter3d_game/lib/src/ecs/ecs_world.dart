/// Entities, the components on them, and the one thing that makes it worth
/// having: everything in here can be written down without anybody enumerating
/// what "everything" is.
///
/// ## Why this exists, stated honestly
///
/// Not because the actor count demanded it — it is in the dozens. The
/// specification records the reason: **replication**. A snapshot with delta
/// compression needs state enumerable in one place, and until now it was
/// spread across systems that each had to be asked, by hand, in a method that
/// grew a line per subsystem and would silently miss the next one.
///
/// That is the payoff and it is the only payoff claimed. Cache locality is not
/// claimed: this stores components in maps keyed by entity index, which is the
/// simple thing. Archetype storage buys contiguous iteration and matters at a
/// hundred thousand entities; **the condition to revisit is written here so it
/// is not a matter of taste later** — when a query walks more than a few
/// thousand entities per step and shows up in a profile.
///
/// ## Nothing is dropped quietly
///
/// A component type that is neither registered nor deliberately excluded makes
/// [save] throw, naming the type. A save file missing a field is a bug that
/// appears on load, hours later, as a game that is subtly wrong — and this
/// repository has already spent a session finding one of those. The moment to
/// hear about it is while writing the save.
library;

import 'entity.dart';

/// One component type: where its values live and how they are written down.
final class _Store {
  _Store();

  /// Entity index to component. The generation is checked against the world's
  /// table rather than stored here, so a despawned entity's leftovers are
  /// unreachable even before they are cleaned up.
  final Map<int, Object> values = <int, Object>{};

  String? name;
  Object? Function(Object value)? encode;

  /// Builds the component from data. For components that are values.
  Object Function(Object? data)? decode;

  /// Writes data back into the component that is already there. For components
  /// that own something live — a body in a collision world, a brain that is
  /// code as much as data.
  void Function(Object value, Object? data)? restoreInPlace;

  /// Why this type is deliberately not saved, when it is not.
  String? excludedBecause;

  bool get isRegistered => name != null || excludedBecause != null;
}

final class EcsWorld {
  final List<int> _generations = <int>[];

  /// Freed indices, waiting to be handed out again.
  ///
  /// A set and not a list, because [alive] asks whether an index is in it and
  /// a linear scan there would make every component read cost the length of
  /// the free list. Dart's default set keeps insertion order, so which index
  /// is reused next is the same on two runs of the same game — which matters
  /// for a snapshot that has to compare byte for byte.
  final Set<int> _free = <int>{};
  final Map<Type, _Store> _stores = <Type, _Store>{};
  final Map<String, Type> _byName = <String, Type>{};

  int _live = 0;

  /// How many entities exist right now.
  int get length => _live;

  /// Says how a component type is written down.
  ///
  /// [decode] receives whatever [encode] produced, after a round trip through
  /// JSON if one happened — so it must accept the JSON forms of what it wrote:
  /// a `List<double>` comes back as a `List<dynamic>`.
  void register<T extends Object>(
    String name, {
    required Object? Function(T value) encode,
    required T Function(Object? data) decode,
  }) {
    final existing = _byName[name];
    if (existing != null && existing != T) {
      throw StateError(
        'component name "$name" is already used by $existing; two components '
        'sharing a name would overwrite each other in every save file',
      );
    }
    final store = _storeOf<T>();
    store
      ..name = name
      // A block body, not an arrow. A cascade written after `=> expr` binds to
      // *expr* rather than to the cascade target, so `..decode` below would
      // have been an assignment on the result of calling `encode`.
      ..encode = ((Object value) {
        return encode(value as T);
      })
      ..decode = decode;
    _byName[name] = T;
  }

  /// Says how a component type is written down when it cannot be *rebuilt*
  /// from what was written.
  ///
  /// A `CharacterController` owns a collider in a live collision world; a brain
  /// is code as much as data. Neither can be constructed from a save file, and
  /// neither needs to be: **a snapshot restores a world that already exists**,
  /// which is the boundary the whole mechanism is drawn around. So this form
  /// writes the numbers back into the component that is already on the entity,
  /// and an entity that does not have one is skipped.
  ///
  /// The alternative was to declare such components unsaved and write their
  /// state by hand somewhere else — which is exactly the hand-written save this
  /// was built to remove, wearing a different hat.
  void registerInPlace<T extends Object>(
    String name, {
    required Object? Function(T value) encode,
    required void Function(T value, Object? data) restore,
  }) {
    final existing = _byName[name];
    if (existing != null && existing != T) {
      throw StateError(
        'component name "$name" is already used by $existing; two components '
        'sharing a name would overwrite each other in every save file',
      );
    }
    final store = _storeOf<T>();
    store
      ..name = name
      ..encode = ((Object value) {
        return encode(value as T);
      })
      ..restoreInPlace = ((Object value, Object? data) {
        restore(value as T, data);
      });
    _byName[name] = T;
  }

  /// Says that a component type is deliberately not saved, and why.
  ///
  /// A renderer handle, a cache, anything rebuilt from what is saved. The
  /// reason is required because the alternative — a type that is simply absent
  /// from the format — is indistinguishable from one somebody forgot.
  void exclude<T extends Object>(String because) {
    _storeOf<T>().excludedBecause = because;
  }

  Entity spawn() {
    _live++;
    if (_free.isNotEmpty) {
      final index = _free.first;
      _free.remove(index);
      return Entity.of(index, _generations[index]);
    }
    _generations.add(0);
    return Entity.of(_generations.length - 1, 0);
  }

  /// Removes an entity and everything on it.
  ///
  /// The generation moves on, which is what makes every handle anybody still
  /// holds answer `false` to [alive] rather than pointing at whoever gets the
  /// index next.
  void despawn(Entity entity) {
    if (!alive(entity)) return;
    final index = entity.index;
    for (final store in _stores.values) {
      store.values.remove(index);
    }
    _generations[index]++;
    _free.add(index);
    _live--;
  }

  bool alive(Entity entity) {
    if (entity.isNone) return false;
    final index = entity.index;
    if (index < 0 || index >= _generations.length) return false;
    if (_generations[index] != entity.generation) return false;
    return !_free.contains(index);
  }

  void set<T extends Object>(Entity entity, T component) {
    if (!alive(entity)) return;
    _storeOf<T>().values[entity.index] = component;
  }

  T? get<T extends Object>(Entity entity) {
    if (!alive(entity)) return null;
    return _stores[T]?.values[entity.index] as T?;
  }

  bool has<T extends Object>(Entity entity) =>
      alive(entity) && (_stores[T]?.values.containsKey(entity.index) ?? false);

  void remove<T extends Object>(Entity entity) {
    if (!alive(entity)) return;
    _stores[T]?.values.remove(entity.index);
  }

  /// Every live entity carrying an [A].
  Iterable<Entity> query<A extends Object>() sync* {
    final store = _stores[A];
    if (store == null) return;
    for (final index in store.values.keys.toList(growable: false)) {
      final entity = Entity.of(index, _generations[index]);
      if (alive(entity)) yield entity;
    }
  }

  /// Every live entity carrying both.
  ///
  /// Walks the smaller of the two, which is the whole of this storage's
  /// cleverness and is enough at this scale: a query for the four entities
  /// that have a `Door` does not touch the thousand that have a position.
  Iterable<Entity> query2<A extends Object, B extends Object>() sync* {
    final a = _stores[A];
    final b = _stores[B];
    if (a == null || b == null) return;
    final smaller = a.values.length <= b.values.length ? a : b;
    final larger = identical(smaller, a) ? b : a;
    for (final index in smaller.values.keys.toList(growable: false)) {
      if (!larger.values.containsKey(index)) continue;
      final entity = Entity.of(index, _generations[index]);
      if (alive(entity)) yield entity;
    }
  }

  /// The whole world, written down.
  ///
  /// Throws when a component type has values and has neither been registered
  /// nor excluded — see the note at the top of this file about what a silently
  /// missing field costs.
  Map<String, Object?> save() {
    final components = <String, Object?>{};
    for (final entry in _stores.entries) {
      final store = entry.value;
      if (store.values.isEmpty) continue;
      if (!store.isRegistered) {
        throw StateError(
          'component ${entry.key} is on ${store.values.length} entities and '
          'has no codec. Call register<${entry.key}>() to save it, or '
          'exclude<${entry.key}>() and say why it is not saved.',
        );
      }
      if (store.excludedBecause != null) continue;
      final encode = store.encode!;
      final rows = <String, Object?>{};
      for (final value in store.values.entries) {
        rows['${value.key}'] = encode(value.value);
      }
      components[store.name!] = rows;
    }
    return <String, Object?>{
      'generations': List<int>.of(_generations),
      'free': List<int>.of(_free),
      'components': components,
    };
  }

  /// Replaces everything with what [from] describes.
  void restore(Map<String, Object?> from) {
    _generations
      ..clear()
      ..addAll(<int>[
        for (final value in from['generations'] as List? ?? const <Object?>[])
          (value as num).toInt(),
      ]);
    _free
      ..clear()
      ..addAll(<int>[
        for (final value in from['free'] as List? ?? const <Object?>[])
          (value as num).toInt(),
      ]);
    _live = _generations.length - _free.length;

    for (final store in _stores.values) {
      // In-place components keep their instances: a save file cannot rebuild a
      // body that is registered in a collision world, and clearing here would
      // throw away the only one there is.
      if (store.restoreInPlace == null) store.values.clear();
    }
    final components = from['components'];
    if (components is! Map) return;
    for (final entry in components.entries) {
      final type = _byName[entry.key];
      final store = type == null ? null : _stores[type];
      // A component this build does not know is skipped rather than fatal: a
      // save from a newer build is refused by its version, and one from an
      // older build simply has less in it.
      if (store == null) continue;
      final decode = store.decode;
      final inPlace = store.restoreInPlace;
      if (decode == null && inPlace == null) continue;
      final rows = entry.value;
      if (rows is! Map) continue;
      for (final row in rows.entries) {
        final index = int.tryParse('${row.key}');
        if (index == null) continue;
        if (decode != null) {
          store.values[index] = decode(row.value);
          continue;
        }
        // In place: whatever is there keeps its identity and takes the numbers.
        // Nothing there means this world does not have that actor, which is
        // the documented edge of what a snapshot restores.
        final present = store.values[index];
        if (present != null) inPlace!(present, row.value);
      }
    }
  }

  _Store _storeOf<T extends Object>() =>
      _stores.putIfAbsent(T, () => _Store());
}
