/// The simulation's model: entities, the components on them, resources, and
/// how each is written down.
///
/// Item 27 of `tasks/1.0-scope-additions.md`: the simulation is an ECS run by
/// `EngineLoop` systems, and a plugin reaches it through `LoopContext.world`.
/// Item 30: every component has a versioned codec, the one way it is written
/// for a snapshot, the network, a prefab or the editor.
///
/// **Here, in the contract, over the foundation alone**, because a plugin's systems
/// are written against these types and must not depend on the engine's
/// packages. `flutter3d_sim` implements [SimWorld] (`EcsWorld`),
/// [ComponentRegistry] and [SnapshotRegistry].
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'registration.dart';

/// A handle to something in the world, not the thing itself.
///
/// ## Why it carries a generation
///
/// An entity id that is only an index is a use-after-free waiting to happen:
/// despawn the monster you were holding, spawn a pickup, and the handle you
/// kept now points at the pickup. So an index is reused and a generation is
/// not. The pair is one integer, and a stale handle answers `false` to
/// [SimWorld.isAlive] instead of quietly working.
///
/// ## Why it is an extension type
///
/// It is an `int` at runtime with no allocation, and it crosses an isolate
/// boundary as one: a [SimWorld] in another isolate hands out the same
/// numbers.
extension type const Entity._(int packed) {
  /// Index below 16 million, generation above — which leaves room for 16
  /// million live entities and 500 million recycles of each before either
  /// wraps, and keeps the whole thing inside the 53 bits a web `int` really
  /// has.
  ///
  /// **Packed by arithmetic, not by shifting.** `generation << 24` reaches
  /// those 53 bits only on the VM: on the web a bitwise operation is done in
  /// 32 bits, so the generation would overflow once it passed 255. A product
  /// and a division are exact to 2^53 on both.
  static const int _indexBits = 24;
  static const int _indexSpan = 1 << _indexBits;

  /// The handle for slot [index] in its [generation].
  const Entity.of(int index, int generation)
    : packed = generation * _indexSpan + index % _indexSpan;

  /// Reads back a handle written as [packed], for a codec or a message.
  const Entity.fromPacked(this.packed);

  /// The handle that refers to nothing. Distinct from every real entity.
  static const Entity none = Entity._(-1);

  /// The slot this entity lives in, reused after a despawn.
  int get index => packed % _indexSpan;

  /// How many times [index] has been reused before this entity.
  int get generation => packed ~/ _indexSpan;

  /// Whether this is [none].
  bool get isNone => packed == -1;
}

/// How one component type is written down, and read back.
///
/// **Versioned.** [version] grows when the encoded shape changes meaning; a
/// [decode] is handed the version the data was written at, so a codec reads
/// every older shape it ever wrote. A snapshot, a network packet, a prefab and
/// the editor all go through the same codec, so there is one place a field is
/// added.
///
/// **[id] is the component's name in every file**, stable across builds and
/// platforms: `'shooter.health'`, prefixed with the plugin's id. Not the
/// Dart type's name, which is minified on the web.
///
/// **Components are data.** A component holds values, not behaviour or live
/// handles; whatever cannot be rebuilt from [encode]'s output — a body in a
/// collision world — is written back into the component already there by an
/// [InPlaceCodec], and anything that need not be saved at all is excluded
/// with a reason ([ComponentRegistry.exclude]).
///
/// [encode] answers plain values only: numbers, strings, booleans, null, and
/// lists and maps of those. That is what a JSON file and an isolate message
/// both carry.
///
/// `base`, so a member added later arrives with a default: extend this, or
/// use [ComponentCodec.of].
abstract base class ComponentCodec<T extends Object> {
  const ComponentCodec();

  /// A codec made of two functions.
  const factory ComponentCodec.of({
    required String id,
    required Object? Function(T value) encode,
    required T? Function(Object? data, int version) decode,
    int version,
  }) = _FunctionCodec<T>;

  /// The component's stable name in files and messages.
  String get id;

  /// The shape [encode] writes now. 1 for a codec that never changed.
  int get version => 1;

  /// [value] as plain values.
  Object? encode(T value);

  /// A component built from [data], written at [version]. Null when the row
  /// cannot be read — the component is then not restored, as a component this
  /// build does not know is not.
  T? decode(Object? data, int version);

  /// The component type this codec writes, for a registry that files codecs
  /// by type.
  Type get type => T;
}

final class _FunctionCodec<T extends Object> extends ComponentCodec<T> {
  const _FunctionCodec({
    required this.id,
    required this._encode,
    required this._decode,
    this.version = 1,
  });

  @override
  final String id;

  @override
  final int version;

  final Object? Function(T value) _encode;
  final T? Function(Object? data, int version) _decode;

  @override
  Object? encode(T value) => _encode(value);

  @override
  T? decode(Object? data, int version) => _decode(data, version);
}

/// A codec for a component that owns something live — a body in a collision
/// world, a brain that is code as much as data — and so is not rebuilt from
/// its data but has the data written back into it.
///
/// **A snapshot restores a world that already exists.** An entity whose
/// component of this type is not there is skipped on restore, which is the
/// documented edge of what a snapshot restores.
abstract base class InPlaceCodec<T extends Object> extends ComponentCodec<T> {
  const InPlaceCodec();

  /// A codec of this kind made of two functions.
  const factory InPlaceCodec.of({
    required String id,
    required Object? Function(T value) encode,
    required void Function(T value, Object? data, int version) restore,
    int version,
  }) = _FunctionInPlaceCodec<T>;

  /// Writes [data], encoded at [version], into [value].
  void restoreInto(T value, Object? data, int version);

  /// Null: a component of this kind is never built from data alone.
  @override
  T? decode(Object? data, int version) => null;
}

final class _FunctionInPlaceCodec<T extends Object> extends InPlaceCodec<T> {
  const _FunctionInPlaceCodec({
    required this.id,
    required this._encode,
    required this._restore,
    this.version = 1,
  });

  @override
  final String id;

  @override
  final int version;

  final Object? Function(T value) _encode;
  final void Function(T value, Object? data, int version) _restore;

  @override
  Object? encode(T value) => _encode(value);

  @override
  void restoreInto(T value, Object? data, int version) =>
      _restore(value, data, version);
}

/// One registered component type, as a tool lists it.
final class ComponentInfo {
  const ComponentInfo({
    required this.type,
    required this.id,
    required this.version,
    required this.published,
    required this.declaredBy,
    this.excludedBecause,
  });

  /// The Dart type, for this process only.
  final Type type;

  /// The codec's id, or the type's description for an excluded type.
  final String id;

  /// The codec's version; 0 for an excluded type.
  final int version;

  /// Whether the view sees it in published state.
  final bool published;

  /// The plugin id that registered it, or `'app'`.
  final String declaredBy;

  /// Why it is not saved, when it is excluded.
  final String? excludedBecause;
}

/// The component types a world knows how to write, and which of them the
/// view may read.
///
/// **Every component type on an entity is registered or excluded.** A world
/// refuses to save a component it has no codec for and no reason not to
/// save, naming the type: a field missing from a save file is a bug found
/// hours later, and the moment to hear about it is while writing the save.
///
/// **[register]'s `published` flag is the boundary between simulation and
/// view** (item 19). Published components are copied, through their codec,
/// into the `PublishedState` built in the `publish` phase; the view reads
/// nothing else of the world.
///
/// **The one way to register a component.** A codec carries its id and its
/// version, and an [InPlaceCodec] is the form for a component restored into
/// the instance already there; `EcsWorld`'s own shorthands from before 1.0
/// (`register(name, encode:, decode:)`, `registerInPlace`, `exclude`) are
/// gone, and the migration guide shows each caller its codec.
abstract base class ComponentRegistry extends PluginRegistry {
  const ComponentRegistry();

  /// Says how components of type [T] are written down. Throws an
  /// [ArgumentError] when [codec]'s id is taken by another type.
  Registration register<T extends Object>(
    ComponentCodec<T> codec, {
    bool published = false,
  });

  /// Says that components of type [T] are deliberately not saved, and why:
  /// a renderer handle, a cache, anything rebuilt from what is saved.
  Registration exclude<T extends Object>(String because);

  /// The codec registered for [T]; null when there is none (absent).
  ComponentCodec<T>? codecOf<T extends Object>();

  /// The codec registered under [id]; null when there is none (absent).
  ComponentCodec<Object>? codecNamed(String id);

  /// Whether [T] is registered with `published: true`.
  bool isPublished<T extends Object>();

  /// Every registered and excluded type, in registration order.
  List<ComponentInfo> get registered;

  @override
  ComponentRegistry forPlugin(PluginScope scope);
}

/// Changes to a world made later, at the end of the phase that asked for
/// them, in the order they were asked.
///
/// **For a system that walks a query and changes what it walks.** Despawning
/// the entity a loop is standing on, or spawning one the same query would
/// then find, makes the walk depend on the storage; queued here, it happens
/// after the phase, the same way on every run.
abstract base class SimCommands {
  const SimCommands();

  /// Spawns an entity at the end of the phase and hands it to [build].
  void spawn(void Function(SimWorld world, Entity entity) build);

  /// Despawns [entity] at the end of the phase.
  void despawn(Entity entity);

  /// Sets [component] on [entity] at the end of the phase.
  void set<T extends Object>(Entity entity, T component);

  /// Takes the [T] off [entity] at the end of the phase.
  void remove<T extends Object>(Entity entity);

  /// Runs [change] at the end of the phase.
  void run(void Function(SimWorld world) change);

  /// How many changes are waiting.
  int get pending;
}

/// A query being built: the component types an entity must carry, must not
/// carry, and must have had set recently.
///
/// ```dart
/// for (final e in world.query().having<Health>().without<Dead>().entities) {
///   ...
/// }
/// ```
///
/// `having` rather than `with`, which is a word Dart keeps for itself.
abstract base class SimQuery {
  const SimQuery();

  /// Only entities carrying a [T].
  SimQuery having<T extends Object>();

  /// Only entities not carrying a [T].
  SimQuery without<T extends Object>();

  /// Only entities whose [T] was set or added at step [since] or later —
  /// by default the step running now, so a system sees what the systems
  /// before it in this step changed. Pass the previous step to see a whole
  /// step's changes.
  SimQuery changed<T extends Object>({int? since});

  /// The matching live entities, in ascending index order: the same order
  /// on every run of the same game.
  Iterable<Entity> get entities;

  /// How many entities match.
  int get length => entities.length;
}

/// The world a simulation's systems read and write: entities, components on
/// them, and resources that belong to no entity.
///
/// Handed to every system as `LoopContext.world`. Made by the engine:
/// `base`, so a member added later arrives with a default.
///
/// **Deterministic by construction.** Iteration is by entity index, never by
/// a hash map's order; spawn reuses indices in the order they were freed; a
/// deferred command runs in the order it was asked.
abstract base class SimWorld {
  const SimWorld();

  /// How many entities exist right now.
  int get length;

  /// A new entity with no components.
  Entity spawn();

  /// Removes [entity] and everything on it. A handle anybody still holds
  /// answers `false` to [isAlive] from then on.
  void despawn(Entity entity);

  /// Whether [entity] still exists.
  bool isAlive(Entity entity);

  /// The [T] on [entity]; null when it has none or is not alive (absent,
  /// not an error).
  T? get<T extends Object>(Entity entity);

  /// Puts [component] on [entity], replacing any [T] already there, and marks
  /// it changed at the current step. Does nothing for a dead entity.
  void set<T extends Object>(Entity entity, T component);

  /// Whether [entity] is alive and carries a [T].
  bool has<T extends Object>(Entity entity);

  /// Takes the [T] off [entity].
  void remove<T extends Object>(Entity entity);

  /// A query over every live entity, narrowed by the builder.
  SimQuery query();

  /// The resource of type [R]; null when none was set (absent).
  R? resource<R extends Object>();

  /// Sets the world's one [R]. Resources are saved with the world when [R]
  /// has a codec in [components].
  void setResource<R extends Object>(R value);

  /// Takes the resource of type [R] away.
  void removeResource<R extends Object>();

  /// Changes queued for the end of the running phase.
  SimCommands get commands;

  /// The component types this world writes, and which it publishes.
  ComponentRegistry get components;

  /// The step the world is at, which [SimQuery.changed] counts from.
  int get changeStep;
}

/// One part of the state a snapshot covers: the world, a plugin's own fields,
/// a Wasm module's memory.
///
/// **The one path for every use of a snapshot**: `EngineLoop.rewindTo`, the
/// debug double-step check, a rollback, a replay's checkpoints, the rewind
/// buffer and the editor's scrub all capture and restore through the
/// [SnapshotRegistry], part by part. A plugin that keeps state outside the
/// world registers a part for it — a genre registers its run, under its
/// plugin id — and every one of those uses covers it.
///
/// **Versioned like a codec.** [restore] is handed the version [capture]
/// wrote at; the registry refuses data from a newer version than this part
/// reads, naming the part.
abstract base class SnapshotPart {
  const SnapshotPart();

  /// A part made of functions.
  const factory SnapshotPart.of({
    required String id,
    required Object? Function() capture,
    required void Function(Object? data, int version) restore,
    int version,
    int? Function()? digest,
  }) = _FunctionPart;

  /// The part's stable name in a snapshot: a plugin's id, or `'world'`.
  String get id;

  /// The shape [capture] writes now.
  int get version => 1;

  /// The part's state as plain values.
  Object? capture();

  /// Puts back what [capture] wrote, at [version].
  void restore(Object? data, int version);

  /// A number that differs when this part's state does; null lets the
  /// registry digest [capture]'s output, which is always right and sometimes
  /// slow.
  int? digest() => null;

  /// Whether this part is put back before the others: a frame the others'
  /// numbers are relative to, such as a physics world's floating origin,
  /// which has to be where it was before a body's position is written into
  /// it. False by default; the parts restored first keep their registration
  /// order among themselves.
  bool get restoresFirst => false;
}

final class _FunctionPart extends SnapshotPart {
  const _FunctionPart({
    required this.id,
    required this._capture,
    required this._restore,
    this.version = 1,
    this._digest,
  });

  @override
  final String id;

  @override
  final int version;

  final Object? Function() _capture;
  final void Function(Object? data, int version) _restore;
  final int? Function()? _digest;

  @override
  Object? capture() => _capture();

  @override
  void restore(Object? data, int version) => _restore(data, version);

  @override
  int? digest() => _digest?.call();
}

/// Every [SnapshotPart] of one engine, in registration order, and the one
/// way their state is captured, restored and digested.
///
/// Filled by `flutter3d_sim`'s `Snapshots`, which `EngineLoop` owns and
/// hands to plugins: `host.registry<SnapshotRegistry>()`. The world is the
/// first part, under `'world'`, and each genre adds its run under its
/// plugin id.
///
/// **What a tool that rewinds, replays or checks a run is handed**, rather
/// than a pair of functions of its own: [capture], [restore] and [digest]
/// cover every part anybody registered, so a part added later is covered by
/// every use at once.
abstract base class SnapshotRegistry extends PluginRegistry {
  const SnapshotRegistry();

  /// Adds [part]. Throws an [ArgumentError] when its id is taken.
  Registration add(SnapshotPart part);

  /// The ids of the parts, in the order they are captured and restored.
  List<String> get parts;

  /// Every part's state, in registration order, as one value [restore]
  /// takes back: `flutter3d_sim`'s `Snapshot`, whose data holds plain
  /// values only.
  Object capture();

  /// Puts every part back to what [state], a [capture] of this registry,
  /// holds.
  ///
  /// Throws a [StateError] when [state] holds no part this registry has:
  /// a restore that restored nothing is a rewind that silently stayed where
  /// it was, which is the failure this registry exists to rule out.
  void restore(Object state);

  /// A number that differs when any part's state does.
  int digest();

  @override
  SnapshotRegistry forPlugin(PluginScope scope);
}
