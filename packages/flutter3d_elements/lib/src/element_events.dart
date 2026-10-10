/// What the elements say, as events on the engine's bus: the world's own
/// events by kind, and what `ElementsListener` used to be the only way to
/// hear.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show PlacedEvent;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:vector_math/vector_math.dart';

import 'simulation.dart' show ElementsListener, TrackedBody;

/// Something that happened to a body in the elements' world, on the bus:
/// the core's own events — a body ignited, wetted, put out — and a plugin
/// element's, which name a [NativeEventKind.plugin] kind.
///
/// **One type for every kind**, told apart by [kind], so a subscriber that
/// wants every fire event subscribes once and a tool lists one declaration.
/// Its digest is the kind's code and the bodies' handles: a replay that
/// lights a different crate, or the same one a step later, differs here.
final class ElementEvent extends BusEvent {
  const ElementEvent({required this.kind, required this.body, this.other});

  /// The name it is declared under.
  static const String declaredName = 'elements.event';

  /// How it is written: the kind's code and name, then the bodies' handles.
  /// The name travels so a plugin element's kind reads back as itself.
  static final EventCodec<ElementEvent> codec = EventCodec<ElementEvent>.of(
    encode: (event) => <Object?>[
      event.kind.code,
      event.kind.name,
      event.body.raw,
      event.other?.raw,
    ],
    decode: (data, _) => switch (data) {
      [final int code, final String name, final int body, final int? other] =>
        ElementEvent(
          kind: code >= NativeEventKind.firstPluginCode
              ? NativeEventKind.plugin(code, name)
              : NativeEventKind.of(code),
          body: NativeBody(body),
          other: other == null ? null : NativeBody(other),
        ),
      _ => null,
    },
  );

  final NativeEventKind kind;
  final NativeBody body;

  /// The second body of an event between two; null for the rest.
  final NativeBody? other;

  @override
  String get name => declaredName;

  @override
  void digestInto(EventDigestSink sink) {
    sink
      ..add(kind.code)
      ..add(body.raw)
      ..add(other?.raw);
  }

  @override
  String toString() => 'elements.${kind.name}';
}

/// The element event kinds one engine knows: the core's, and those plugin
/// elements add.
///
/// **A registry so two plugins cannot speak with one voice.** A plugin
/// element registers each kind it raises, at a code from
/// [NativeEventKind.firstPluginCode] up; a second claim on the code or the
/// name is refused with both claimants named, as an event name on the bus
/// is. The core's kinds are in it from the start, owned by `'core'`, and
/// closed: nothing below the plugin range may be added.
///
/// One per engine, handed to the loop among its registries; nothing global.
final class ElementEventKinds extends PluginRegistry {
  /// A registry holding the core's kinds.
  ElementEventKinds() {
    for (final kind in coreKinds) {
      _kinds.add((kind: kind, owner: 'core'));
    }
  }

  /// The kinds the core raises, which every registry starts with.
  static const List<NativeEventKind> coreKinds = <NativeEventKind>[
    NativeEventKind.slept,
    NativeEventKind.woke,
    NativeEventKind.ignited,
    NativeEventKind.extinguished,
    NativeEventKind.burntOut,
    NativeEventKind.contactBegan,
    NativeEventKind.contactEnded,
    NativeEventKind.jointBroken,
    NativeEventKind.wetted,
    NativeEventKind.burnerOut,
  ];

  final List<({NativeEventKind kind, String owner})> _kinds =
      <({NativeEventKind kind, String owner})>[];

  /// Every kind known, the core's first, then in the order added.
  List<NativeEventKind> get kinds => <NativeEventKind>[
    for (final k in _kinds) k.kind,
  ];

  /// The kind at [code]: a registered one, or the core's reading of it.
  NativeEventKind of(int code) =>
      _kinds.where((k) => k.kind.code == code).firstOrNull?.kind ??
      NativeEventKind.of(code);

  /// The kind called [name], or null.
  NativeEventKind? named(String name) =>
      _kinds.where((k) => k.kind.name == name).firstOrNull?.kind;

  /// Who added [kind]: `'core'`, `'app'`, or a plugin's id.
  String? ownerOf(NativeEventKind kind) =>
      _kinds.where((k) => k.kind.code == kind.code).firstOrNull?.owner;

  /// Adds [kind] for the application. Throws an [ArgumentError] for a kind
  /// in the core's range, or one whose code or name is taken, naming who
  /// holds it.
  Registration add(NativeEventKind kind) => _add(kind, null);

  Registration _add(NativeEventKind kind, PluginScope? scope) {
    final owner = scope?.manifest.id ?? 'app';
    if (!kind.isPlugin) {
      throw ArgumentError.value(
        kind.code,
        'kind',
        '$owner adds "${kind.name}" at code ${kind.code}, which is the '
            'core\'s; a plugin\'s kind takes a code from '
            '${NativeEventKind.firstPluginCode} up',
      );
    }
    for (final existing in _kinds) {
      final k = existing.kind;
      if (k.code == kind.code || k.name == kind.name) {
        throw ArgumentError.value(
          kind.name,
          'kind',
          'the element event "${k.name}" (code ${k.code}) is added by '
              '${existing.owner}, and $owner claims '
              '"${kind.name}" (code ${kind.code}); a code and a name are '
              'unique in one engine',
        );
      }
    }
    final entry = (kind: kind, owner: owner);
    _kinds.add(entry);
    final registration = Registration(() => _kinds.remove(entry));
    scope?.track(registration);
    return registration;
  }

  @override
  ElementEventKinds forPlugin(PluginScope scope) => _ScopedKinds(this, scope);
}

final class _ScopedKinds extends ElementEventKinds {
  _ScopedKinds(this._of, this._scope);

  final ElementEventKinds _of;
  final PluginScope _scope;

  @override
  List<NativeEventKind> get kinds => _of.kinds;

  @override
  NativeEventKind of(int code) => _of.of(code);

  @override
  NativeEventKind? named(String name) => _of.named(name);

  @override
  String? ownerOf(NativeEventKind kind) => _of.ownerOf(kind);

  @override
  Registration add(NativeEventKind kind) => _of._add(kind, _scope);

  @override
  ElementEventKinds forPlugin(PluginScope scope) => _of.forPlugin(scope);
}

/// Declares the elements' events on [events], each one not already declared
/// there: [ElementEvent] and the five body events and [ElementExploded] with
/// their codecs on the step channel, where a game that steps its elements in
/// the fixed step publishes them; the drawing's three —
/// [ElementsOverBudget], [ElementFireSeen], [ElementFireLost] — on the frame
/// channel, about the picture and never the run.
///
/// Called by `ElementsSimulationPlugin` as it installs, by
/// `ElementsSimulation.publishTo` and by `ElementsListener.toBus`, so
/// whichever door a game hears the elements through, the step channel knows
/// how to write what comes through it.
void declareElementEvents(EventRegistry events) {
  bool declared(String name) => events.declared.any((d) => d.name == name);
  void step<T extends BusEvent>(
    String name,
    String description,
    EventCodec<T> codec,
  ) {
    if (!declared(name)) {
      events.declare<T>(name, description: description, codec: codec);
    }
  }

  void frame<T extends BusEvent>(String name, String description) {
    if (!declared(name)) {
      events.declare<T>(
        name,
        channel: BusChannel.frame,
        description: description,
      );
    }
  }

  step<ElementEvent>(
    ElementEvent.declaredName,
    "Something the elements' world did to a body, by kind.",
    ElementEvent.codec,
  );
  step<ElementCaught>(
    ElementCaught.eventName,
    'A body caught fire.',
    ElementBodyEvent.codecOf(ElementCaught.new),
  );
  step<ElementOut>(
    ElementOut.eventName,
    "A body's fire went out with fuel left.",
    ElementBodyEvent.codecOf(ElementOut.new),
  );
  step<ElementBurntOut>(
    ElementBurntOut.eventName,
    'A body burnt all its fuel.',
    ElementBodyEvent.codecOf(ElementBurntOut.new),
  );
  step<ElementWetted>(
    ElementWetted.eventName,
    'A body went into a liquid.',
    ElementBodyEvent.codecOf(ElementWetted.new),
  );
  step<ElementBurnerOut>(
    ElementBurnerOut.eventName,
    'A burner went out under a liquid.',
    ElementBodyEvent.codecOf(ElementBurnerOut.new),
  );
  step<ElementExploded>(
    ElementExploded.eventName,
    'A charge went off.',
    ElementExploded.codec,
  );
  frame<ElementsOverBudget>(
    ElementsOverBudget.eventName,
    'A step of the drawing wanted more than it holds this frame.',
  );
  frame<ElementFireSeen>(
    ElementFireSeen.eventName,
    "A fire came into the camera's picture.",
  );
  frame<ElementFireLost>(
    ElementFireLost.eventName,
    "A fire left the camera's picture.",
  );
}

// What `ElementsListener` tells, as events. Published by the listener
// `ElementsListener.toBus` makes, from wherever `Elements.update` is called:
// a game that steps its elements in the fixed step has the first six on the
// step channel, which is where something that changes the run belongs.

/// A body the elements hold caught fire, went out, burnt out, was wetted or
/// had its burner drowned: one of [ElementsListener]'s body callbacks.
///
/// [made] is the elements' own handle when they made the body, for a game
/// that keeps its look; it is not part of the digest.
abstract base class ElementBodyEvent extends BusEvent {
  const ElementBodyEvent(this.body, this.made);

  final NativeBody body;

  /// The body as `Elements.addBody` made it; null for one the game made.
  final TrackedBody? made;

  /// The codec of a body event made by [make]: the body's handle, which is
  /// what identifies it. [made] does not travel — it is a live handle — so
  /// an event read back has none.
  static EventCodec<T> codecOf<T extends ElementBodyEvent>(
    T Function(NativeBody body, TrackedBody? made) make,
  ) => EventCodec<T>.of(
    encode: (event) => event.body.raw,
    decode: (data, _) => data is int ? make(NativeBody(data), null) : null,
  );

  @override
  void digestInto(EventDigestSink sink) => sink.add(body.raw);
}

/// A body caught fire: [ElementsListener.caught].
final class ElementCaught extends ElementBodyEvent {
  const ElementCaught(super.body, super.made);

  /// The name it is published and declared under.
  static const String eventName = 'elements.caught';

  @override
  String get name => eventName;
}

/// A body's fire went out with fuel left: [ElementsListener.out].
final class ElementOut extends ElementBodyEvent {
  const ElementOut(super.body, super.made);

  /// The name it is published and declared under.
  static const String eventName = 'elements.out';

  @override
  String get name => eventName;
}

/// A body burnt all its fuel: [ElementsListener.burntOut].
final class ElementBurntOut extends ElementBodyEvent {
  const ElementBurntOut(super.body, super.made);

  /// The name it is published and declared under.
  static const String eventName = 'elements.burntOut';

  @override
  String get name => eventName;
}

/// A body went into a liquid: [ElementsListener.wetted].
final class ElementWetted extends ElementBodyEvent {
  const ElementWetted(super.body, super.made);

  /// The name it is published and declared under.
  static const String eventName = 'elements.wetted';

  @override
  String get name => eventName;
}

/// A burner went out under a liquid: [ElementsListener.burnerOut].
final class ElementBurnerOut extends ElementBodyEvent {
  const ElementBurnerOut(super.body, super.made);

  /// The name it is published and declared under.
  static const String eventName = 'elements.burnerOut';

  @override
  String get name => eventName;
}

/// A charge went off at [at], pushing [pushed] bodies:
/// [ElementsListener.exploded].
///
/// A [PlacedEvent], so an effect document triggered by `elements.exploded`
/// goes off where the charge did with no code in between.
final class ElementExploded extends BusEvent implements PlacedEvent {
  ElementExploded(Vector3 at, this.pushed) : at = at.clone();

  @override
  final Vector3 at;
  final int pushed;

  /// How it is written: where, then how many bodies it pushed.
  static final EventCodec<ElementExploded> codec =
      EventCodec<ElementExploded>.of(
        encode: (event) => <Object?>[
          event.at.x,
          event.at.y,
          event.at.z,
          event.pushed,
        ],
        decode: (data, _) => switch (data) {
          [final num x, final num y, final num z, final int pushed] =>
            ElementExploded(
              Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
              pushed,
            ),
          _ => null,
        },
      );

  /// None: a blast leans no way, and an effect's emitter keeps its own
  /// shape — a trigger that wants one says its `direction`.
  @override
  Vector3? get direction => null;

  /// The name it is published and declared under.
  static const String eventName = 'elements.exploded';

  @override
  String get name => eventName;

  @override
  void digestInto(EventDigestSink sink) => sink
    ..add(at.x)
    ..add(at.y)
    ..add(at.z)
    ..add(pushed);
}

/// A step of the drawing wanted more than it holds this frame:
/// [ElementsListener.budget]. About the picture, never the run.
final class ElementsOverBudget extends BusEvent {
  const ElementsOverBudget(this.step, this.wanted, this.holds);

  /// 'flames', 'smoke', 'embers', 'drops' or 'bubbles'.
  final String step;
  final int wanted;
  final int holds;

  /// The name it is published and declared under.
  static const String eventName = 'elements.overBudget';

  @override
  String get name => eventName;
}

/// A fire came into the camera's picture: [ElementsListener.seen]. About
/// the picture, never the run.
final class ElementFireSeen extends BusEvent {
  const ElementFireSeen(this.fire);

  final NativeFire fire;

  /// The name it is published and declared under.
  static const String eventName = 'elements.fireSeen';

  @override
  String get name => eventName;
}

/// A fire left the camera's picture: [ElementsListener.lost]. About the
/// picture, never the run.
final class ElementFireLost extends BusEvent {
  const ElementFireLost(this.body);

  final NativeBody body;

  /// The name it is published and declared under.
  static const String eventName = 'elements.fireLost';

  @override
  String get name => eventName;
}
