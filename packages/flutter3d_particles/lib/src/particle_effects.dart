import 'package:flutter3d_core/flutter3d_core.dart' show Scene;
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show PlacedEvent;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:vector_math/vector_math.dart';

import 'effect_document.dart';
import 'particle_system.dart';

/// Where an effect goes off, and which way it leans.
typedef EffectPlace = ({Vector3 at, Vector3? direction});

/// Places [event] for an effect it triggers, or returns null to leave it to
/// [PlacedEvent] and the trigger.
typedef EffectPlacer = EffectPlace? Function(BusEvent event);

/// The effects an engine has read from documents, the pools they emit into,
/// and the bus subscriptions that start them.
///
/// **A registry, so a plugin's effects come and go with the plugin.** A
/// `.f3dplugin` that names effect documents installs them here; switching the
/// plugin off takes them out and unsubscribes their triggers, as it withdraws
/// everything else the plugin registered. A plugin's effects are named
/// `<plugin id>.<name>`, so two plugins' `embers` do not collide.
///
/// ```dart
/// final effects = ParticleEffects(particles);
/// effects.addDocument(
///   EffectDocument.parse(await rootBundle.loadString('fx/blast.f3dfx')),
///   events: loop.events,
/// );
/// effects.burst('embers', at);
/// EngineLoop(registries: [effects, ...], ...);
/// ```
///
/// **Triggers listen on the frame channel**, which is the one decision 12 of
/// `tasks/0.9-plugins.md` gives particles: an effect is something shown, a
/// step that is run again shows it once, and nothing in the simulation reads
/// what a particle did.
///
/// **One pool by default.** Every effect emits into [system] unless
/// `systemFor` was given, which picks a pool by an effect's [EffectRender] —
/// a pool is one draw, and a draw has one texture, one blend and one
/// softness. [looks] lists each look and its pool, which is what an
/// application builds its contributors from.
final class ParticleEffects extends PluginRegistry {
  ParticleEffects(
    ParticleSystem system, {
    ParticleSystem Function(EffectRender render)? systemFor,
  }) : _store = _EffectStore(system, systemFor),
       _scope = null;

  ParticleEffects._scoped(this._store, this._scope);

  final _EffectStore _store;
  final PluginScope? _scope;

  /// The pool every effect emits into unless `systemFor` picks another.
  ParticleSystem get system => _store.system;

  /// Every effect's name, in the order added.
  List<String> get names => List<String>.unmodifiable(_store.effects.keys);

  /// The effect called [name] — a plugin's as `<plugin id>.<name>` — or
  /// null.
  EffectDescription? operator [](String name) =>
      _store.effects[name]?.description;

  /// The pool [name] emits into, or null for an effect nobody added.
  ParticleSystem? systemOf(String name) => _store.effects[name]?.system;

  /// Each distinct look among the effects added, with its pool: what to
  /// build a `ParticleContributor` or a `MeshParticleContributor` for.
  List<({EffectRender render, ParticleSystem system})> get looks {
    final seen = <String>{};
    return <({EffectRender render, ParticleSystem system})>[
      for (final added in _store.effects.values)
        if (seen.add(added.description.render.key))
          (render: added.description.render, system: added.system),
    ];
  }

  /// What the effects added asked for and this build does not do, one
  /// sentence each, by effect name.
  Map<String, List<String>> get unsupported => <String, List<String>>{
    for (final MapEntry(key: name, value: added) in _store.effects.entries)
      if (added.description.unsupported.isNotEmpty)
        name: added.description.unsupported,
  };

  /// How many triggers have fired, and how many could not, for want of a
  /// place: the event was not a [PlacedEvent], no placer placed it and the
  /// trigger had no `at`.
  ({int fired, int unplaced}) get triggerCounts =>
      (fired: _store.fired, unplaced: _store.unplaced);

  /// Adds every effect of [document]. See [add].
  Registration addDocument(
    EffectDocument document, {
    EventRegistry? events,
    EffectPlacer? place,
    String Function(String event)? eventName,
  }) {
    final added = <Registration>[];
    try {
      for (final effect in document.effects) {
        added.add(
          add(effect, events: events, place: place, eventName: eventName),
        );
      }
    } on Object {
      for (final registration in added.reversed) {
        registration.cancel();
      }
      rethrow;
    }
    return Registration(() {
      for (final registration in added.reversed) {
        registration.cancel();
      }
    });
  }

  /// Adds [effect] under its name — `<plugin id>.<name>` for a plugin — and
  /// subscribes its triggers on [events].
  ///
  /// [place] places an event the triggers hear; [eventName] turns a
  /// trigger's event into the name it is published under, which is how a
  /// plugin's document says `gust` for its own `<plugin id>.gust`. With no
  /// [events], the triggers are kept and never fire, and [burst] and [emit]
  /// are the way to start it.
  ///
  /// Throws an [ArgumentError] when the name is taken, naming who has it.
  Registration add(
    EffectDescription effect, {
    EventRegistry? events,
    EffectPlacer? place,
    String Function(String event)? eventName,
  }) {
    final scope = _scope;
    final owner = scope?.manifest.id ?? 'app';
    final name = scope == null
        ? effect.name
        : '${scope.manifest.id}.${effect.name}';
    final existing = _store.effects[name];
    if (existing != null) {
      throw ArgumentError.value(
        name,
        'effect',
        'the effect "$name" is added by ${existing.owner}, and $owner adds it '
            'again; an effect name is unique in one engine',
      );
    }
    final system = _store.systemFor?.call(effect.render) ?? _store.system;
    final installed = _Installed(effect, owner, system);
    _store.effects[name] = installed;

    final subscriptions = <Registration>[
      if (events != null)
        for (final (index, trigger) in effect.triggers.indexed)
          events.onFrame<BusEvent>(
            'particles.$name#$index',
            _handler(
              installed,
              trigger,
              eventName?.call(trigger.event) ?? trigger.event,
              place,
            ),
          ),
    ];
    final registration = Registration(() {
      for (final subscription in subscriptions.reversed) {
        subscription.cancel();
      }
      if (identical(_store.effects[name], installed)) {
        _store.effects.remove(name);
      }
    });
    scope?.track(registration);
    return registration;
  }

  EventHandler<BusEvent> _handler(
    _Installed installed,
    EffectTrigger trigger,
    String eventName,
    EffectPlacer? place,
  ) => (Delivered<BusEvent> delivered) {
    final event = delivered.event;
    if (event.name != eventName) return;
    final at = trigger.at;
    final EffectPlace? found = at != null
        ? (at: at, direction: null)
        : place?.call(event) ??
              switch (event) {
                final PlacedEvent placed => (
                  at: placed.at,
                  direction: placed.direction,
                ),
                _ => null,
              };
    if (found == null) {
      _store.unplaced++;
      return;
    }
    _store.fired++;
    final description = installed.description;
    final direction = trigger.direction ?? found.direction;
    switch (trigger.spawn) {
      case EffectSpawn.burst:
        installed.system.burst(
          description.effect,
          found.at,
          direction: direction,
        );
      case EffectSpawn.timed:
        // A key of its own each time, so a second event while the first is
        // still smoking adds a plume rather than restarting the first.
        installed.system.emitTimed(
          Object(),
          description.effect,
          found.at,
          perSecond: trigger.perSecond ?? description.rate!,
          seconds: trigger.seconds!,
          direction: direction,
        );
    }
  };

  /// One burst of [name] at [at], in scene space (relative to
  /// `Scene.origin`); how many particles were emitted. Throws an
  /// [ArgumentError] for an effect nobody added.
  int burst(String name, Vector3 at, {Vector3? direction, Object? source}) {
    final added = _named(name);
    return added.system.burst(
      added.description.effect,
      at,
      direction: direction,
      source: source,
    );
  }

  /// Keeps [name] emitting from [key] at [at], in scene space —
  /// `ParticleSystem.emit` — at [perSecond], or at the rate its document
  /// gives. Call it every frame the source burns, as `ParticleSystem.emit` is
  /// called.
  void emit(
    Object key,
    String name,
    Vector3 at, {
    double? perSecond,
    Vector3? direction,
  }) {
    final added = _named(name);
    final rate = perSecond ?? added.description.rate;
    if (rate == null) {
      throw ArgumentError.value(
        name,
        'name',
        'the effect "$name" gives no "rate", and none was passed',
      );
    }
    added.system.emit(
      key,
      added.description.effect,
      at,
      perSecond: rate,
      direction: direction,
    );
  }

  /// [burst] at a place in the world: [at] narrowed to [scene]'s space with
  /// `Scene.toScene`, the difference taken in doubles first.
  int burstInWorld(
    String name,
    WorldPosition at, {
    required Scene scene,
    Vector3? direction,
    Object? source,
  }) => burst(name, scene.toScene(at), direction: direction, source: source);

  /// [emit] from a place in the world: [at] narrowed to [scene]'s space with
  /// `Scene.toScene`.
  void emitInWorld(
    Object key,
    String name,
    WorldPosition at, {
    required Scene scene,
    double? perSecond,
    Vector3? direction,
  }) => emit(
    key,
    name,
    scene.toScene(at),
    perSecond: perSecond,
    direction: direction,
  );

  _Installed _named(String name) =>
      _store.effects[name] ??
      (throw ArgumentError.value(
        name,
        'name',
        'no effect is called "$name"; the effects are '
            '${_store.effects.keys.join(', ')}',
      ));

  @override
  ParticleEffects forPlugin(PluginScope scope) =>
      ParticleEffects._scoped(_store, scope);
}

final class _Installed {
  _Installed(this.description, this.owner, this.system);

  final EffectDescription description;
  final String owner;
  final ParticleSystem system;
}

final class _EffectStore {
  _EffectStore(this.system, this.systemFor);

  final ParticleSystem system;
  final ParticleSystem Function(EffectRender render)? systemFor;

  // Insertion order: a list of effects reads in the order they were added,
  // never by hash.
  final Map<String, _Installed> effects = <String, _Installed>{};
  int fired = 0;
  int unplaced = 0;
}
