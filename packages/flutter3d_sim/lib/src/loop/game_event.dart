import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// Something a step did, told to whoever is watching.
///
/// The seam a game needs and a simulation kept refusing to give it: a shot was
/// fired, a runner landed, a tyre broke traction. Without it every game reads
/// the state twice a frame and reconstructs the moment by difference — was the
/// ammo count lower than last frame, is the runner on the ground now and was it
/// not before — which is slower, wrong at the edges, and impossible for
/// anything that happens and undoes itself inside one step. A shot fired and
/// resolved between two frames leaves no difference to find.
///
/// **Open, deliberately.** A game invents events the way it invents weapons,
/// and a closed list would mean a template deciding what can happen in a game
/// written on top of it. Subclass this, put whatever the moment carries on the
/// subclass, declare it on the engine's bus with a codec
/// (`EventRegistry.declare`) and publish it from your own step.
///
/// **It says what happened, not what to do about it.** No sound, no particle,
/// no screen shake — those are decisions, and they belong to the game. A
/// simulation that named a sound file would be a simulation that could not run
/// on a server, and running there is the whole reason this package has no
/// Flutter in it.
///
/// **`base`, so this can grow.** A game may `extends` this and may not
/// `implements` it. The difference is what happens the day a member is added
/// here: an `extends` inherits it, an `implements` stops compiling. Adding to
/// a type a published package invites you to subclass has to be free, and the
/// price is one keyword on the subclass — `final class MyEvent extends
/// GameEvent`.
///
/// **On the engine's bus, and only there.** A genre's simulation publishes
/// each event onto the bus it was handed (`publishTo`, which its
/// `GenrePlugin` calls) from inside the step that raised it, which puts it on
/// the step channel; a game subscribes with `onStep` or `onFrame`. Nothing is
/// buffered on the simulation, so there is nothing to drain and nothing lost
/// for want of draining. A simulation stepped by hand publishes onto a
/// [DirectBus].
///
/// **[name] is the name it is declared under**, `<genre>.<event>`, which is
/// how the bus finds its codec: a declared codec is what a run's event digest
/// folds in, so two runs that differ in an event's fields differ in their
/// digests at that step.
abstract base class GameEvent extends BusEvent {
  const GameEvent();

  /// The name the event is declared and published under, and its identity
  /// in a digest. Not an identity between two events: two of the same name
  /// are still two events.
  @override
  String get name;
}

/// The bus for a simulation stepped by hand, without an `EngineLoop`: a
/// test, a server, a tool that plays a level blind.
///
/// **Each event is handed out as it is published**, to the step subscribers
/// and then to the frame subscribers, in registration order, since nothing
/// here opens or closes a step. So a handler runs inside the step that
/// published the event: one that changes the world changes it mid-step, and
/// a run that has to replay belongs in an `EngineLoop`, whose bus delivers at
/// the step's end and digests what it delivered. Nothing is digested or
/// reconciled here.
///
/// [step] is what [Delivered.step] says, for a caller that counts its own
/// steps; [Delivered.sequence] counts the events published since [step] was
/// last set.
final class DirectBus extends EventRegistry {
  DirectBus();

  final List<EventDeclaration> _declared = <EventDeclaration>[];
  final List<void Function(BusEvent event, BusChannel channel)> _step =
      <void Function(BusEvent, BusChannel)>[];
  final List<void Function(BusEvent event, BusChannel channel)> _frame =
      <void Function(BusEvent, BusChannel)>[];

  int _stepNumber = 0;
  int _sequence = 0;

  /// The step [Delivered.step] reports. Setting it starts the count of
  /// [Delivered.sequence] again.
  int get step => _stepNumber;
  set step(int value) {
    _stepNumber = value;
    _sequence = 0;
  }

  @override
  List<EventDeclaration> get declared =>
      List<EventDeclaration>.unmodifiable(_declared);

  @override
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    String? description,
    EventCodec<T>? codec,
  }) {
    for (final d in _declared) {
      if (d.name == name) {
        throw ArgumentError.value(
          name,
          'name',
          'the event "$name" is declared by ${d.declaredBy} (${d.type}) and '
              'again ($T); an event name is unique on one bus',
        );
      }
    }
    final declaration = EventDeclaration(
      name: name,
      type: T,
      channel: channel,
      declaredBy: 'app',
      description: description,
      codec: codec,
    );
    _declared.add(declaration);
    return Registration(() => _declared.remove(declaration));
  }

  @override
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => _subscribe<T>(_step, handler);

  @override
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => _subscribe<T>(_frame, handler);

  Registration _subscribe<T extends BusEvent>(
    List<void Function(BusEvent event, BusChannel channel)> into,
    EventHandler<T> handler,
  ) {
    void deliver(BusEvent event, BusChannel channel) {
      if (event is! T) return;
      handler(
        Delivered<T>(
          event: event,
          channel: channel,
          step: _stepNumber,
          sequence: _sequence,
          resimulated: false,
        ),
      );
    }

    into.add(deliver);
    return Registration(() => into.remove(deliver));
  }

  @override
  void publish(BusEvent event) {
    for (final deliver in List.of(_step)) {
      deliver(event, BusChannel.step);
    }
    for (final deliver in List.of(_frame)) {
      deliver(event, BusChannel.frame);
    }
    _sequence++;
  }

  @override
  EventRegistry forPlugin(PluginScope scope) => this;
}
