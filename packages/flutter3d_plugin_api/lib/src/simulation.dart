/// The boundary between the simulation and the view: what a step publishes,
/// the handle the view holds, and the world origin both agree on.
///
/// Items 18 and 19 of `tasks/1.0-scope-additions.md`. **The view reads the
/// simulation only through [PublishedState]**, built in the `publish` phase,
/// so the simulation can move into another isolate without the view
/// changing: `SimulationHandle`, which `flutter3d_sim` declares beside the
/// loop that fills it, has one shape whether the world is in this isolate
/// (`LocalSimulation`) or another (`IsolateSimulation`).
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'ecs.dart';
import 'events.dart';
import 'plugin_version.dart' show PluginFormatException;
import 'simulation_version.dart';

/// How a [WorldPosition] component is written: three doubles, in metres.
///
/// **The position the view draws an entity at.** A simulation sets a
/// [WorldPosition] on every entity the view shows; registered published,
/// it reaches [PublishedState.positions] in double precision, and the view
/// subtracts its camera's position before narrowing to float32.
final class WorldPositionCodec extends ComponentCodec<WorldPosition> {
  const WorldPositionCodec();

  /// The id positions are written under.
  static const String name = 'flutter3d.position';

  @override
  String get id => name;

  @override
  Object? encode(WorldPosition value) => <double>[value.x, value.y, value.z];

  @override
  WorldPosition? decode(Object? data, int version) => switch (data) {
    [final num x, final num y, final num z] => WorldPosition(
      x.toDouble(),
      y.toDouble(),
      z.toDouble(),
    ),
    _ => null,
  };
}

/// One step-channel event as the view receives it: encoded by its declared
/// [EventCodec], so it crosses an isolate boundary as plain values and
/// nothing the view holds is an object the simulation still owns.
///
/// [decode] reads it back with the codec the event was declared with — the
/// genre's `codec` beside the event class.
final class PublishedEvent {
  const PublishedEvent({
    required this.name,
    required this.version,
    required this.data,
    required this.step,
    required this.sequence,
    required this.resimulated,
  });

  /// The event's stable name: [BusEvent.name].
  final String name;

  /// The version its codec wrote [data] at; 0 for an event published with
  /// no codec declared, whose [data] is null.
  final int version;

  /// The event as its codec encoded it: plain values only.
  final Object? data;

  /// The step that published it.
  final int step;

  /// Its place among the events of [step], from 0.
  final int sequence;

  /// Whether [step] was being run again when it was published.
  final bool resimulated;

  /// The event, read back through [codec]; null when [codec] cannot read it
  /// or it carried no data (absent).
  T? decode<T extends BusEvent>(EventCodec<T> codec) =>
      version == 0 ? null : codec.decode(data, version);

  @override
  String toString() => '$name at step $step #$sequence';
}

/// What one step left for the view to read: immutable, built in the
/// `publish` phase.
///
/// **Encoded, not shared.** Each published component is held as its codec
/// wrote it, and each event as its declared codec wrote it, so nothing the
/// view holds can be changed by the next step, and the same state crosses an
/// isolate boundary as plain values. [read] decodes a component on demand;
/// [positions] are decoded once, since the view reads every one of them
/// every frame; [PublishedEvent.decode] reads an event back.
///
/// **Positions in double precision.** [positions] are [WorldPosition]s;
/// [origin] is the floating origin the simulation's float32 work is
/// relative to (see [OriginShifted]).
final class PublishedState {
  PublishedState({
    required this.step,
    required this.seconds,
    this.origin = WorldPosition.origin,
    Map<String, Map<Entity, Object?>> components =
        const <String, Map<Entity, Object?>>{},
    Map<Entity, WorldPosition> positions = const <Entity, WorldPosition>{},
    List<PublishedEvent> events = const <PublishedEvent>[],
    this.simulation = SimulationVersion.engineOnly,
  }) : components = Map<String, Map<Entity, Object?>>.unmodifiable(
         <String, Map<Entity, Object?>>{
           for (final MapEntry(:key, :value) in components.entries)
             key: Map<Entity, Object?>.unmodifiable(value),
         },
       ),
       positions = Map<Entity, WorldPosition>.unmodifiable(positions),
       events = List<PublishedEvent>.unmodifiable(events);

  /// Before the first step: nothing published.
  static final PublishedState empty = PublishedState(step: 0, seconds: 0);

  /// The number of steps run when this was published.
  final int step;

  /// Simulated seconds when this was published.
  final double seconds;

  /// The world origin the simulation's local frame was at.
  final WorldPosition origin;

  /// Every published component, by codec id, then by entity, as its codec
  /// encoded it.
  final Map<String, Map<Entity, Object?>> components;

  /// Every entity with a published [WorldPosition], where it is.
  final Map<Entity, WorldPosition> positions;

  /// The step channel's events of the steps since the last publication, in
  /// order and encoded: what the view plays sounds and particles for.
  final List<PublishedEvent> events;

  /// The events named [name], in order: what a view that answers one kind
  /// of event walks.
  Iterable<PublishedEvent> eventsNamed(String name) =>
      events.where((event) => event.name == name);

  /// The simulation that produced this.
  final SimulationVersion simulation;

  /// Where [entity] is; null when it publishes no position (absent).
  WorldPosition? positionOf(Entity entity) => positions[entity];

  /// The entities carrying the published component [codec] writes, in
  /// ascending index order: what a view plugin or a tool walks to draw or
  /// list one kind of thing.
  Iterable<Entity> entitiesWith(ComponentCodec<Object> codec) {
    final rows = components[codec.id];
    if (rows == null) return const <Entity>[];
    return rows.keys.toList()..sort((a, b) => a.index.compareTo(b.index));
  }

  /// The component [codec] writes, on [entity], decoded; null when the
  /// entity has none published (absent).
  T? read<T extends Object>(ComponentCodec<T> codec, Entity entity) {
    final rows = components[codec.id];
    if (rows == null || !rows.containsKey(entity)) return null;
    return codec.decode(rows[entity], codec.version);
  }

  /// This state as plain values — lists, maps of strings, numbers, strings,
  /// booleans and null — which is what crosses an isolate's port or a
  /// socket: `IsolateSimulation` in `flutter3d_sim` sends every published
  /// state this way. [PublishedState.fromWire] reads it back.
  ///
  /// The components and events are already their codecs' output, so nothing
  /// is encoded twice; an entity travels as its packed number.
  Map<String, Object?> toWire() => <String, Object?>{
    'step': step,
    'seconds': seconds,
    'origin': <double>[origin.x, origin.y, origin.z],
    'components': <String, Object?>{
      for (final MapEntry(:key, :value) in components.entries)
        key: <Object?>[
          for (final MapEntry(key: entity, value: data) in value.entries)
            <Object?>[entity.packed, data],
        ],
    },
    'positions': <Object?>[
      for (final MapEntry(key: entity, value: at) in positions.entries)
        <Object?>[entity.packed, at.x, at.y, at.z],
    ],
    'events': <Object?>[
      for (final event in events)
        <Object?>[
          event.name,
          event.version,
          event.data,
          event.step,
          event.sequence,
          event.resimulated,
        ],
    ],
    'simulation': simulation.toJson(),
  };

  /// Reads what [toWire] wrote. Throws a [PluginFormatException] for a value
  /// that is not one: a state read halfway would draw a world that never
  /// was.
  factory PublishedState.fromWire(Object? wire) {
    Never wrong(String what) => throw PluginFormatException(
      'a published state on the wire has $what',
      wire,
    );
    if (wire is! Map) wrong('no fields');
    final step = wire['step'];
    final seconds = wire['seconds'];
    if (step is! int || seconds is! num) wrong('no step or seconds');
    final origin = switch (wire['origin']) {
      [final num x, final num y, final num z] => WorldPosition(
        x.toDouble(),
        y.toDouble(),
        z.toDouble(),
      ),
      _ => wrong('no origin'),
    };
    final components = <String, Map<Entity, Object?>>{};
    final rows = wire['components'];
    if (rows is! Map) wrong('no components');
    for (final MapEntry(:key, :value) in rows.entries) {
      if (key is! String || value is! List) {
        wrong('a component that is not rows');
      }
      final read = components[key] = <Entity, Object?>{};
      for (final row in value) {
        switch (row) {
          case [final int packed, final Object? data]:
            read[Entity.fromPacked(packed)] = data;
          default:
            wrong('a component row that is not [entity, data]');
        }
      }
    }
    final positions = <Entity, WorldPosition>{};
    final placed = wire['positions'];
    if (placed is! List) wrong('no positions');
    for (final row in placed) {
      switch (row) {
        case [final int packed, final num x, final num y, final num z]:
          positions[Entity.fromPacked(packed)] = WorldPosition(
            x.toDouble(),
            y.toDouble(),
            z.toDouble(),
          );
        default:
          wrong('a position that is not [entity, x, y, z]');
      }
    }
    final events = <PublishedEvent>[];
    final heard = wire['events'];
    if (heard is! List) wrong('no events');
    for (final event in heard) {
      switch (event) {
        case [
          final String name,
          final int version,
          final Object? data,
          final int at,
          final int sequence,
          final bool resimulated,
        ]:
          events.add(
            PublishedEvent(
              name: name,
              version: version,
              data: data,
              step: at,
              sequence: sequence,
              resimulated: resimulated,
            ),
          );
        default:
          wrong(
            'an event that is not [name, version, data, step, sequence, '
            'resimulated]',
          );
      }
    }
    final simulation = wire['simulation'];
    return PublishedState(
      step: step,
      seconds: seconds.toDouble(),
      origin: origin,
      components: components,
      positions: positions,
      events: events,
      simulation: simulation is Map
          ? SimulationVersion.fromJson(simulation.cast<String, Object?>())
          : wrong('no simulation'),
    );
  }

  @override
  String toString() =>
      'PublishedState(step $step, ${positions.length} positions, '
      '${components.length} components, ${events.length} events)';
}

/// The world origin moved: everything the simulation holds in a float32
/// local frame was moved by the opposite of [offset] so it stays near zero.
///
/// **Published on the step channel by the loop when the origin is shifted**,
/// before the next system runs. Physics and particles subscribe and move
/// their bodies and particles; the view moves its lights and its camera's
/// local frame. A position held as a [WorldPosition] does not change.
final class OriginShifted extends BusEvent {
  const OriginShifted({required this.from, required this.to});

  /// The origin before.
  final WorldPosition from;

  /// The origin now.
  final WorldPosition to;

  /// How far the origin moved, in doubles: subtract it from a local
  /// position to keep it at the same place in the world.
  ({double x, double y, double z}) get offset => to.relativeTo(from);

  /// The name it is published under, which the engine's loop declares.
  static const String eventName = 'origin.shifted';

  /// How it is written: both origins, three doubles each.
  static final EventCodec<OriginShifted> codec = EventCodec<OriginShifted>.of(
    encode: (shift) => <Object?>[
      <double>[shift.from.x, shift.from.y, shift.from.z],
      <double>[shift.to.x, shift.to.y, shift.to.z],
    ],
    decode: (data, _) => switch (data) {
      [
        [final num fx, final num fy, final num fz],
        [final num tx, final num ty, final num tz],
      ] =>
        OriginShifted(
          from: WorldPosition(fx.toDouble(), fy.toDouble(), fz.toDouble()),
          to: WorldPosition(tx.toDouble(), ty.toDouble(), tz.toDouble()),
        ),
      _ => null,
    },
  );

  @override
  String get name => eventName;

  @override
  void digestInto(EventDigestSink sink) {
    sink
      ..add(<double>[from.x, from.y, from.z])
      ..add(<double>[to.x, to.y, to.z]);
  }
}
