import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'registration.dart';

/// Something that happened, published on the engine's bus.
///
/// **Typed, and subscribed to by type.** A subscriber names the class it
/// wants and is handed instances of it and its subclasses, so the compiler
/// says what a handler receives and a search finds who listens.
///
/// **[name] is its identity in a digest**, not its runtime type: type names
/// are minified on the web, and a digest written on a phone must be checked
/// on a server. Two event classes may not share a name in one engine, which
/// `EventRegistry.declare` holds.
///
/// **[digestInto] is what makes it checkable.** A replay compares the events
/// of each step with the ones the run recorded, so an event writes the
/// fields that make it this event — the body that landed, how hard — and a
/// run that lands somewhere else differs to the event. An event that writes
/// nothing is still counted, by name and position.
///
/// `base`, so this can grow: an `extends` inherits a member added here, an
/// `implements` would stop compiling.
abstract base class BusEvent {
  const BusEvent();

  /// A stable name: `'runner.landed'`, `'time.lost'`.
  String get name;

  /// Writes the fields that identify this event. Plain values only: numbers,
  /// strings, booleans, null, and lists and maps of those.
  void digestInto(EventDigestSink sink) {}

  @override
  String toString() => name;
}

/// Where an event writes its identifying fields. Made by the engine.
abstract base class EventDigestSink {
  const EventDigestSink();

  void add(Object? value);
}

/// The two ways an event reaches its subscribers.
///
/// An open value class rather than an enum (ARCHITECTURE.md §13.1).
final class BusChannel {
  const BusChannel._(this.name);

  /// Collected during a fixed step and handed to every step subscriber in a
  /// fixed order at the step's end, on the same turn. Part of the
  /// simulation: replayed, digested, run again on a rollback.
  static const BusChannel step = BusChannel._('step');

  /// Handed out once a frame, after the frame's steps: sound, particles,
  /// interface. A step's events reach the frame channel too, once — a step
  /// run again on a rollback is reconciled with what was already shown,
  /// not shown twice.
  static const BusChannel frame = BusChannel._('frame');

  final String name;

  @override
  String toString() => name;
}

/// One event as a subscriber receives it.
final class Delivered<T extends BusEvent> {
  const Delivered({
    required this.event,
    required this.channel,
    required this.step,
    required this.sequence,
    required this.resimulated,
  });

  final T event;
  final BusChannel channel;

  /// The step that published it. A frame-channel event published outside a
  /// step carries the number of steps run when it was published.
  final int step;

  /// Its place among the events of [step], from 0. With [step], the event's
  /// identity across a rollback: the same step run again publishes its
  /// events at the same sequence numbers if it does the same thing.
  final int sequence;

  /// Whether [step] was run again. On the step channel, the step's systems
  /// are being re-run; on the frame channel, this event was not shown the
  /// first time, or was different — it is a correction.
  final bool resimulated;

  @override
  String toString() =>
      '${event.name} at step $step #$sequence'
      '${resimulated ? ' (resimulated)' : ''}';
}

typedef EventHandler<T extends BusEvent> = void Function(Delivered<T> event);

/// How one event type is written down and read back: for a digest, a run
/// file's event trace, a network message, a tool that reads events without
/// playing.
///
/// **Versioned like a component's codec.** [decode] is handed the version the
/// data was written at. [encode] answers plain values only.
///
/// **A declared codec is what a digest folds in.** When an event's name was
/// declared with a codec, the bus digests `[name, version, encode(event)]`
/// rather than what [BusEvent.digestInto] writes, so the bytes a run file
/// carries and the bytes a digest is taken of are the same bytes.
///
/// `base`, so a member added later arrives with a default: extend this, or
/// use [EventCodec.of].
abstract base class EventCodec<T extends BusEvent> {
  const EventCodec();

  /// A codec made of two functions.
  const factory EventCodec.of({
    required Object? Function(T event) encode,
    required T? Function(Object? data, int version) decode,
    int version,
  }) = _FunctionEventCodec<T>;

  /// The shape [encode] writes now.
  int get version => 1;

  /// [event] as plain values.
  Object? encode(T event);

  /// The event [data] describes, written at [version]; null when it cannot
  /// be read.
  T? decode(Object? data, int version);

  /// [event] encoded, when it is a [T]: for a registry that holds codecs of
  /// many types under one name each.
  Object? encodeAny(BusEvent event) => encode(event as T);
}

final class _FunctionEventCodec<T extends BusEvent> extends EventCodec<T> {
  const _FunctionEventCodec({
    required this._encode,
    required this._decode,
    this.version = 1,
  });

  @override
  final int version;

  final Object? Function(T event) _encode;
  final T? Function(Object? data, int version) _decode;

  @override
  Object? encode(T event) => _encode(event);

  @override
  T? decode(Object? data, int version) => _decode(data, version);
}

/// An event type, declared so tools can list what a game says.
final class EventDeclaration {
  const EventDeclaration({
    required this.name,
    required this.type,
    required this.channel,
    required this.declaredBy,
    this.description,
    this.codec,
  });

  final String name;
  final Type type;
  final BusChannel channel;

  /// The plugin id that declared it, or `'app'`.
  final String declaredBy;
  final String? description;

  /// How it is written down; null for an event declared without one, which
  /// is digested through [BusEvent.digestInto] and cannot be read back.
  final EventCodec<BusEvent>? codec;
}

/// The event bus as plugins see it.
///
/// ## Order
///
/// Subscribers are called in registration order — the application's first,
/// then each plugin's in install order — and each event goes to every
/// matching subscriber before the next event is handed out. Nothing is
/// ordered by a hash map.
abstract base class EventRegistry extends PluginRegistry {
  const EventRegistry();

  /// Says that events of type [T] are published under [name], so a tool can
  /// list them and two plugins cannot claim one name.
  ///
  /// [codec], when given, is how the event is written for a run file, the
  /// network, a tool and the view's `PublishedState`, and what its digest is
  /// taken of (see [EventCodec]).
  ///
  /// **A step-channel event has one.** The view reads a step's events
  /// encoded, and a replay digests what the codec writes, so an event
  /// published on the step channel without a declared codec is a bug: the
  /// engine's bus asserts it in a debug build, naming the event. Only a
  /// frame-channel event, which no replay sees, may go without.
  ///
  /// Throws an [ArgumentError] naming both claimants when [name] is taken.
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    String? description,
    EventCodec<T>? codec,
  });

  /// The codec declared for events named [name]; null when the name was
  /// declared without one, or not declared (absent).
  EventCodec<BusEvent>? codecFor(String name) {
    for (final declaration in declared) {
      if (declaration.name == name) return declaration.codec;
    }
    return null;
  }

  /// Calls [handler] at the end of each step for every [T] the step
  /// published. Inside the step: a handler may change the world, and is run
  /// again on a rollback.
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  );

  /// Calls [handler] once a frame for every [T] published since the last,
  /// steps' events first in step order, then the frame's own.
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  );

  /// Calls [handler] on the frame channel for every [T] that was shown for
  /// a step and not produced when the step was run again — a rollback took
  /// it back. A frame subscriber that started something for it (a sound, a
  /// burst of particles) may stop it here.
  ///
  /// A registry that never runs a step again retracts nothing; the default
  /// registers nothing to call.
  Registration onRetracted<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  /// Publishes [event]: onto the step channel while a step is running,
  /// onto the frame channel otherwise.
  void publish(BusEvent event);

  /// Every declared event type, in declaration order.
  List<EventDeclaration> get declared;

  @override
  EventRegistry forPlugin(PluginScope scope);
}
