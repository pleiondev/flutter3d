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
/// Since 1.0 it is also **the simulation's model** (item 27): the world every
/// `EngineLoop` system is handed as `LoopContext.world`, implementing the
/// plugin API's [SimWorld], with every component written through a versioned
/// [ComponentCodec] (item 30).
///
/// Cache locality is not claimed: this stores components in maps keyed by
/// entity index, which is the simple thing. Archetype storage buys contiguous
/// iteration and matters at a hundred thousand entities; **the condition to
/// revisit is written here so it is not a matter of taste later** — when a
/// query walks more than a few thousand entities per step and shows up in a
/// profile. It can arrive in a minor: nothing here promises a layout.
///
/// ## One way to say how a component is written
///
/// `components.register(codec)`, with a [ComponentCodec] that carries its id
/// and version, or an [InPlaceCodec] for a component written back into the
/// instance already there; `components.exclude` for one deliberately not
/// saved. The world's own shorthands from before 1.0 (`register(name,
/// encode:, decode:)`, `registerInPlace`, `exclude`) were a second door to
/// the same registry without a version, and are gone.
///
/// ## Nothing is dropped quietly
///
/// A component type that is neither registered nor deliberately excluded makes
/// [save] throw, naming the type. A save file missing a field is a bug that
/// appears on load, hours later, as a game that is subtly wrong. The moment to
/// hear about it is while writing the save.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'component_store.dart';

/// The simulation's world. See the library doc.
final class EcsWorld extends SimWorld {
  EcsWorld() {
    _components = _Components(this, null);
  }

  final List<int> _generations = <int>[];

  /// Freed indices, waiting to be handed out again.
  ///
  /// A set and not a list, because [isAlive] asks whether an index is in it and
  /// a linear scan there would make every component read cost the length of
  /// the free list. Dart's default set keeps insertion order, so which index
  /// is reused next is the same on two runs of the same game — which matters
  /// for a snapshot that has to compare byte for byte.
  final Set<int> _free = <int>{};
  final Map<Type, ComponentStore> _stores = <Type, ComponentStore>{};
  final Map<String, Type> _byName = <String, Type>{};
  final Map<Type, Object> _resources = <Type, Object>{};
  final List<void Function()> _commands = <void Function()>[];

  late final _Components _components;
  late final _Commands _commandQueue = _Commands(this);

  int _live = 0;
  int _changeStep = 0;

  /// How many entities exist right now.
  @override
  int get length => _live;

  @override
  ComponentRegistry get components => _components;

  @override
  SimCommands get commands => _commandQueue;

  @override
  int get changeStep => _changeStep;

  /// Moves the step changes are marked with. Called by `EngineLoop` at the
  /// start of every step; a world stepped by hand calls it the same way.
  void beginStep(int step) => _changeStep = step;

  /// Runs the commands queued since the last call, in the order they were
  /// queued, including any a command queues in turn. `EngineLoop` calls it
  /// after every phase.
  void applyCommands() {
    var i = 0;
    while (i < _commands.length) {
      _commands[i]();
      i++;
    }
    _commands.clear();
  }

  /// Whether the world holds nothing at all: no entity and no resource.
  bool get isEmpty => _live == 0 && _resources.isEmpty;

  @override
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

  /// Whether [entity] is alive by the allocation and carries nothing restored
  /// in place — a slot a [restore] put back that nobody has built yet.
  ///
  /// Components with a decoder do not count: [restore] has already made those
  /// from the file, and building the entity again replaces them until the
  /// second [restore] makes them again.
  ///
  /// **For what arrives during play.** A snapshot restores into a world that
  /// already exists, and a component registered in place — a body in a
  /// collision world, a brain — is filled in rather than rebuilt, so an entity
  /// spawned after the level loaded has nothing to fill when the save is
  /// loaded afresh, or after a rollback past its birth. A game that spawns
  /// things builds them again: [restore] puts the allocation back, the game
  /// builds each entity the save recorded *under that entity* (see
  /// `ActorSystem.spawn`'s `entity`, which asks this first), and a second
  /// [restore] pours the numbers into what was just built.
  bool vacant(Entity entity) {
    if (!isAlive(entity)) return false;
    final index = entity.index;
    for (final store in _stores.values) {
      if (!store.inPlace) continue;
      if (store.values.containsKey(index)) return false;
    }
    return true;
  }

  /// Removes an entity and everything on it.
  ///
  /// The generation moves on, which is what makes every handle anybody still
  /// holds answer `false` to [isAlive] rather than pointing at whoever gets the
  /// index next.
  @override
  void despawn(Entity entity) {
    if (!isAlive(entity)) return;
    final index = entity.index;
    for (final store in _stores.values) {
      store.values.remove(index);
      store.changedAt.remove(index);
    }
    _generations[index]++;
    _free.add(index);
    _live--;
  }

  @override
  bool isAlive(Entity entity) {
    if (entity.isNone) return false;
    final index = entity.index;
    if (index < 0 || index >= _generations.length) return false;
    if (_generations[index] != entity.generation) return false;
    return !_free.contains(index);
  }

  @override
  void set<T extends Object>(Entity entity, T component) {
    if (!isAlive(entity)) return;
    final store = _storeOf<T>();
    store.values[entity.index] = component;
    store.changedAt[entity.index] = _changeStep;
  }

  @override
  T? get<T extends Object>(Entity entity) {
    if (!isAlive(entity)) return null;
    return _stores[T]?.values[entity.index] as T?;
  }

  @override
  bool has<T extends Object>(Entity entity) =>
      isAlive(entity) &&
      (_stores[T]?.values.containsKey(entity.index) ?? false);

  @override
  void remove<T extends Object>(Entity entity) {
    if (!isAlive(entity)) return;
    _stores[T]?.values.remove(entity.index);
    _stores[T]?.changedAt.remove(entity.index);
  }

  /// Every live entity carrying an [A], in the order the component was first
  /// put on each.
  ///
  /// **Not a second [query].** It is the order every game written before
  /// [SimQuery] steps by, and a recorded run's checkpoints depend on it: an
  /// actor stepped before another lands first. So it stays, for the systems
  /// whose order is already on tape; a new system walks [query], whose index
  /// order is the one the plugin API promises.
  Iterable<Entity> queryOf<A extends Object>() sync* {
    final store = _stores[A];
    if (store == null) return;
    for (final index in store.values.keys.toList(growable: false)) {
      final entity = Entity.of(index, _generations[index]);
      if (isAlive(entity)) yield entity;
    }
  }

  /// Every live entity carrying both, in the order [A]'s or [B]'s store holds
  /// them — the smaller of the two.
  ///
  /// Walks the smaller store, which is the whole of this storage's
  /// cleverness and is enough at this scale.
  Iterable<Entity> query2<A extends Object, B extends Object>() sync* {
    final a = _stores[A];
    final b = _stores[B];
    if (a == null || b == null) return;
    final smaller = a.values.length <= b.values.length ? a : b;
    final larger = identical(smaller, a) ? b : a;
    for (final index in smaller.values.keys.toList(growable: false)) {
      if (!larger.values.containsKey(index)) continue;
      final entity = Entity.of(index, _generations[index]);
      if (isAlive(entity)) yield entity;
    }
  }

  @override
  SimQuery query() => _Query(this);

  @override
  R? resource<R extends Object>() => _resources[R] as R?;

  @override
  void setResource<R extends Object>(R value) => _resources[R] = value;

  @override
  void removeResource<R extends Object>() => _resources.remove(R);

  /// The published components of every live entity, encoded by their
  /// codecs, by codec id: what `PublishedState.components` holds. Positions
  /// ([WorldPosition] components) are read separately by [publishedPositions].
  Map<String, Map<Entity, Object?>> publishedComponents() {
    final out = <String, Map<Entity, Object?>>{};
    for (final store in _stores.values) {
      final codec = store.codec;
      if (!store.published || codec == null) continue;
      if (store.type == WorldPosition) continue;
      final rows = <Entity, Object?>{};
      for (final MapEntry(:key, :value) in store.values.entries) {
        final entity = Entity.of(key, _generations[key]);
        if (isAlive(entity)) rows[entity] = codec.encode(value);
      }
      out[codec.id] = rows;
    }
    return out;
  }

  /// Every live entity with a [WorldPosition] component, where it is.
  Map<Entity, WorldPosition> publishedPositions() {
    final store = _stores[WorldPosition];
    if (store == null) return const <Entity, WorldPosition>{};
    return <Entity, WorldPosition>{
      for (final MapEntry(:key, :value) in store.values.entries)
        if (isAlive(Entity.of(key, _generations[key])))
          Entity.of(key, _generations[key]): value as WorldPosition,
    };
  }

  /// The whole world, written down.
  ///
  /// Throws when a component type has values and has neither been registered
  /// nor excluded — see the note at the top of this file about what a silently
  /// missing field costs.
  ///
  /// **The shape is the one every save since 0.6 has**: `generations`,
  /// `free`, `components` by codec id. A codec at a version past 1 adds its
  /// number under `componentVersions`, and a resource with a codec is written
  /// under `resources`; a world with neither writes the same bytes it always
  /// did, so a recorded run's digests still hold.
  Map<String, Object?> save() {
    final components = <String, Object?>{};
    final versions = <String, Object?>{};
    for (final entry in _stores.entries) {
      final store = entry.value;
      if (store.values.isEmpty) continue;
      if (!store.isRegistered) {
        throw StateError(
          'component ${entry.key} is on ${store.values.length} entities and '
          'has no codec. Register a ComponentCodec<${entry.key}> to save it '
          '(components.register), or components.exclude<${entry.key}>() and '
          'say why it is not saved.',
        );
      }
      final codec = store.codec;
      if (store.excludedBecause != null || codec == null) continue;
      final rows = <String, Object?>{};
      for (final value in store.values.entries) {
        rows['${value.key}'] = codec.encode(value.value);
      }
      components[codec.id] = rows;
      if (codec.version != 1) versions[codec.id] = codec.version;
    }
    final resources = <String, Object?>{};
    for (final MapEntry(:key, :value) in _resources.entries) {
      final codec = _stores[key]?.codec;
      if (codec == null || codec is InPlaceCodec<Object>) continue;
      resources[codec.id] = codec.encode(value);
      if (codec.version != 1) versions[codec.id] = codec.version;
    }
    return <String, Object?>{
      'generations': List<int>.of(_generations),
      'free': List<int>.of(_free),
      'components': components,
      if (versions.isNotEmpty) 'componentVersions': versions,
      if (resources.isNotEmpty) 'resources': resources,
    };
  }

  /// The integers in [value], skipping anything that is not one.
  static List<int> _integers(Object? value) => <int>[
    if (value is List)
      for (final item in value)
        if (item is num) item.toInt(),
  ];

  /// Replaces everything with what [from] describes.
  ///
  /// **Lenient, because a save from another build is expected.** A row it
  /// cannot read, a component type it has never heard of and a component
  /// written by a newer codec version than this build's are all left
  /// unrestored rather than thrown about: a save from a newer build is refused
  /// by its version, and one from an older build simply has less in it.
  void restore(Map<String, Object?> from) {
    _generations
      ..clear()
      ..addAll(_integers(from['generations']));
    _free
      ..clear()
      ..addAll(_integers(from['free']));
    _live = _generations.length - _free.length;

    for (final store in _stores.values) {
      store.changedAt.clear();
      // In-place components keep their instances: a save file cannot rebuild a
      // body that is registered in a collision world, and clearing here would
      // throw away the only one there is.
      if (!store.inPlace) store.values.clear();
    }
    final versions = switch (from['componentVersions']) {
      final Map<Object?, Object?> map => map,
      _ => const <Object?, Object?>{},
    };
    int versionOf(String name) => switch (versions[name]) {
      final num n => n.toInt(),
      _ => 1,
    };
    final components = from['components'];
    if (components is Map) {
      for (final entry in components.entries) {
        final type = _byName[entry.key];
        final store = type == null ? null : _stores[type];
        final codec = store?.codec;
        if (store == null || codec == null) continue;
        final version = versionOf('${entry.key}');
        if (version > codec.version) continue;
        final rows = entry.value;
        if (rows is! Map) continue;
        for (final row in rows.entries) {
          final index = int.tryParse('${row.key}');
          if (index == null) continue;
          if (codec is InPlaceCodec<Object>) {
            // Whatever is there keeps its identity and takes the numbers.
            // Nothing there means this world does not have that actor, which
            // is the documented edge of what a snapshot restores.
            final present = store.values[index];
            if (present != null) codec.restoreInto(present, row.value, version);
            continue;
          }
          // Null means the decoder could not read this row, and the component
          // is simply not restored.
          final value = codec.decode(row.value, version);
          if (value != null) store.values[index] = value;
        }
      }
    }
    final resources = from['resources'];
    for (final store in _stores.values) {
      final codec = store.codec;
      if (codec == null || codec is InPlaceCodec<Object>) continue;
      if (!_resources.containsKey(store.type)) continue;
      if (resources is Map && resources.containsKey(codec.id)) {
        final version = versionOf(codec.id);
        if (version > codec.version) continue;
        final value = codec.decode(resources[codec.id], version);
        if (value != null) _resources[store.type] = value;
      }
    }
    if (resources is Map) {
      for (final entry in resources.entries) {
        final type = _byName[entry.key];
        if (type == null || _resources.containsKey(type)) continue;
        final codec = _stores[type]?.codec;
        if (codec == null || codec is InPlaceCodec<Object>) continue;
        final version = versionOf('${entry.key}');
        if (version > codec.version) continue;
        final value = codec.decode(entry.value, version);
        if (value != null) _resources[type] = value;
      }
    }
  }

  ComponentStore _storeOf<T extends Object>() =>
      _stores.putIfAbsent(T, () => ComponentStore(T));
}

/// The registry an [EcsWorld] files its codecs in, as the plugin API's
/// [ComponentRegistry].
final class _Components extends ComponentRegistry {
  _Components(this._world, this._scope);

  final EcsWorld _world;
  final PluginScope? _scope;

  String get _by => _scope?.manifest.id ?? 'app';

  @override
  Registration register<T extends Object>(
    ComponentCodec<T> codec, {
    bool published = false,
  }) {
    final name = codec.id;
    final existing = _world._byName[name];
    if (existing != null && existing != T) {
      throw ArgumentError.value(
        name,
        'codec.id',
        'component name "$name" is already used by $existing; two components '
            'sharing a name would overwrite each other in every save file',
      );
    }
    final store = _world._storeOf<T>();
    final previous = store.codec;
    if (previous != null && previous.id != name) {
      _world._byName.remove(previous.id);
    }
    store
      ..codec = codec
      ..published = published
      ..declaredBy = _by
      ..excludedBecause = null;
    _world._byName[name] = T;
    final registration = Registration(() {
      if (!identical(store.codec, codec)) return;
      store
        ..codec = null
        ..published = false;
      _world._byName.remove(name);
    });
    _scope?.track(registration);
    return registration;
  }

  @override
  Registration exclude<T extends Object>(String because) {
    final store = _world._storeOf<T>()
      ..excludedBecause = because
      ..declaredBy = _by;
    final registration = Registration(() {
      if (store.excludedBecause == because) store.excludedBecause = null;
    });
    _scope?.track(registration);
    return registration;
  }

  @override
  ComponentCodec<T>? codecOf<T extends Object>() {
    final codec = _world._stores[T]?.codec;
    return codec is ComponentCodec<T> ? codec : null;
  }

  @override
  ComponentCodec<Object>? codecNamed(String id) {
    final type = _world._byName[id];
    return type == null ? null : _world._stores[type]?.codec;
  }

  @override
  bool isPublished<T extends Object>() => _world._stores[T]?.published ?? false;

  @override
  List<ComponentInfo> get registered => <ComponentInfo>[
    for (final store in _world._stores.values)
      if (store.isRegistered)
        ComponentInfo(
          type: store.type,
          id: store.codec?.id ?? '${store.type}',
          version: store.codec?.version ?? 0,
          published: store.published,
          declaredBy: store.declaredBy,
          excludedBecause: store.excludedBecause,
        ),
  ];

  @override
  ComponentRegistry forPlugin(PluginScope scope) => _Components(_world, scope);
}

final class _Commands extends SimCommands {
  _Commands(this._world);

  final EcsWorld _world;

  @override
  int get pending => _world._commands.length;

  @override
  void spawn(void Function(SimWorld world, Entity entity) build) =>
      _world._commands.add(() => build(_world, _world.spawn()));

  @override
  void despawn(Entity entity) =>
      _world._commands.add(() => _world.despawn(entity));

  @override
  void set<T extends Object>(Entity entity, T component) =>
      _world._commands.add(() => _world.set<T>(entity, component));

  @override
  void remove<T extends Object>(Entity entity) =>
      _world._commands.add(() => _world.remove<T>(entity));

  @override
  void run(void Function(SimWorld world) change) =>
      _world._commands.add(() => change(_world));
}

final class _Query extends SimQuery {
  _Query(this._world);

  final EcsWorld _world;
  final List<Type> _having = <Type>[];
  final List<Type> _without = <Type>[];
  final List<(Type, int?)> _changed = <(Type, int?)>[];

  @override
  SimQuery having<T extends Object>() {
    _having.add(T);
    return this;
  }

  @override
  SimQuery without<T extends Object>() {
    _without.add(T);
    return this;
  }

  @override
  SimQuery changed<T extends Object>({int? since}) {
    _changed.add((T, since));
    return this;
  }

  @override
  Iterable<Entity> get entities {
    final world = _world;
    final required = <Type>{..._having, for (final (type, _) in _changed) type};
    final List<int> candidates;
    if (required.isEmpty) {
      candidates = <int>[
        for (var i = 0; i < world._generations.length; i++)
          if (!world._free.contains(i)) i,
      ];
    } else {
      ComponentStore? smallest;
      for (final type in required) {
        final store = world._stores[type];
        if (store == null) return const <Entity>[];
        if (smallest == null || store.values.length < smallest.values.length) {
          smallest = store;
        }
      }
      candidates = smallest!.values.keys.toList()..sort();
    }
    final out = <Entity>[];
    for (final index in candidates) {
      final entity = Entity.of(index, world._generations[index]);
      if (!world.isAlive(entity)) continue;
      if (!required.every(
        (type) => world._stores[type]!.values.containsKey(index),
      )) {
        continue;
      }
      if (_without.any(
        (type) => world._stores[type]?.values.containsKey(index) ?? false,
      )) {
        continue;
      }
      if (!_changed.every((entry) {
        final (type, since) = entry;
        final at = world._stores[type]!.changedAt[index];
        return at != null && at >= (since ?? world._changeStep);
      })) {
        continue;
      }
      out.add(entity);
    }
    return out;
  }
}
