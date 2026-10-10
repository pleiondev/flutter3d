part of 'engine_loop.dart';

/// What one step published on the step channel, digested.
final class StepEventSummary {
  const StepEventSummary({
    required this.step,
    required this.count,
    required this.digest,
    required this.resimulated,
    this.events = const <BusEvent>[],
  });

  final int step;

  /// How many events the step published.
  final int count;

  /// The events the step published on the step channel, in publishing
  /// order, after every step subscriber has had them: what a game reads at
  /// the end of a step (`EngineLoop.onStepEnd`) to answer the step as a
  /// whole — a camera cut on the step the runner died, every coin of one
  /// sweep in one sound.
  final List<BusEvent> events;

  /// The events' digest: each event's name and the fields it writes, in
  /// publishing order, through `StateDigest`. The same for two runs that
  /// published the same events, and different the moment one differs. Zero
  /// for a step that published nothing.
  final int digest;

  final bool resimulated;
}

/// The engine's event bus: typed, with a step channel and a frame channel.
///
/// ## The step channel
///
/// Events published during a fixed step are collected and handed out at the
/// step's end, before the next step starts, to every step subscriber in a
/// fixed order — registration order, the application's own first, then each
/// plugin's in install order. A subscriber that publishes in turn has its
/// event appended to the same step and delivered after. **On the same turn
/// of the loop, and not through a `Stream`**: a stream delivers on a later
/// microtask, and an event arriving between two steps would let a listener
/// change the world in a gap no replay reproduces.
///
/// Each step's events are digested ([StepEventSummary]), so a run file can
/// carry the digest and a replay say at which step, and so at which event,
/// it parted. **A step event is declared with its codec**: the digest folds
/// in what the codec writes, and the view reads the step's events encoded
/// (`PublishedState.events`). Publishing an undeclared one on the step
/// channel fails an assertion, naming it.
///
/// ## The frame channel
///
/// Once a frame, after the frame's steps, every step's events are handed to
/// the frame subscribers — sound, particles, interface — followed by what
/// was published on the frame channel directly.
///
/// **A step run again is reconciled, not shown twice.** A rollback re-steps
/// and the step channel delivers again, marked `resimulated`, because the
/// world needs it. The frame channel keeps what it showed for each step, by
/// step and sequence number and the event's digest, and of a resimulated
/// step hands out only what it had not shown: the same landing at the same
/// place is not a second thud. An event shown before and not produced again
/// goes to [onRetracted] subscribers, who may take it back.
///
/// Made by the [EngineLoop] that drives it, which is the only thing that
/// opens and closes its steps.
final class EventBus extends EventRegistry {
  EventBus._({required this.reconcileWindow, required this.stepEventLimit})
    : assert(reconcileWindow > 0),
      assert(stepEventLimit > 0);

  /// How many steps back the frame channel remembers what it showed. A
  /// rollback deeper than this shows its events again. Ten seconds at 60 Hz.
  final int reconcileWindow;

  /// The most events one step may publish. A subscriber that republishes
  /// what it receives would otherwise loop for ever inside the step.
  final int stepEventLimit;

  final List<_Subscriber> _stepSubscribers = <_Subscriber>[];
  final List<_Subscriber> _frameSubscribers = <_Subscriber>[];
  final List<_Subscriber> _retractSubscribers = <_Subscriber>[];
  final List<_Declared> _declared = <_Declared>[];
  int _registered = 0;
  bool _ordered = true;

  int _step = 0;
  bool _inStep = false;
  bool _resimulated = false;
  final List<BusEvent> _stepEvents = <BusEvent>[];

  final List<_QueuedStep> _queued = <_QueuedStep>[];

  // The step channel's events since the loop last published, encoded, for
  // the view.
  bool _collecting = false;
  final List<PublishedEvent> _collected = <PublishedEvent>[];

  List<PublishedEvent> _takeCollected() {
    final taken = List<PublishedEvent>.of(_collected);
    _collected.clear();
    return taken;
  }

  final List<(BusEvent, int)> _framePublished = <(BusEvent, int)>[];
  final Map<int, List<_Shown>> _shown = <int, List<_Shown>>{};

  @override
  List<EventDeclaration> get declared => <EventDeclaration>[
    for (final d in _declared) d.declaration,
  ];

  @override
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    String? description,
    EventCodec<T>? codec,
  }) => _declare<T>(name, channel, description, codec, null);

  Registration _declare<T extends BusEvent>(
    String name,
    BusChannel channel,
    String? description,
    EventCodec<T>? codec,
    PluginScope? scope,
  ) {
    final by = scope?.manifest.id ?? 'app';
    for (final d in _declared) {
      if (d.declaration.name == name) {
        throw ArgumentError.value(
          name,
          'name',
          'the event "$name" is declared by ${d.declaration.declaredBy} '
              '(${d.declaration.type}) and again by $by ($T); an event name '
              'is unique in one engine, so prefix it with the plugin id',
        );
      }
    }
    final declared = _Declared(
      EventDeclaration(
        name: name,
        type: T,
        channel: channel,
        declaredBy: by,
        description: description,
        codec: codec,
      ),
    );
    _declared.add(declared);
    if (codec != null) _codecs[name] = codec;
    return _tracked(
      scope,
      Registration(() {
        _declared.remove(declared);
        if (identical(_codecs[name], codec)) _codecs.remove(name);
      }),
    );
  }

  @override
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => _subscribe<T>(_stepSubscribers, label, handler, null);

  @override
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => _subscribe<T>(_frameSubscribers, label, handler, null);

  @override
  EventCodec<BusEvent>? codecFor(String name) => _codecs[name];

  final Map<String, EventCodec<BusEvent>> _codecs =
      <String, EventCodec<BusEvent>>{};

  @override
  Registration onRetracted<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => _subscribe<T>(_retractSubscribers, label, handler, null);

  Registration _subscribe<T extends BusEvent>(
    List<_Subscriber> into,
    String label,
    EventHandler<T> handler,
    PluginScope? scope,
  ) {
    final subscriber = _TypedSubscriber<T>(
      label,
      handler,
      scope,
      _registered++,
    );
    into.add(subscriber);
    _ordered = false;
    return _tracked(
      scope,
      Registration(() {
        into.remove(subscriber);
        // Removal keeps the order of the rest, so nothing is re-sorted.
      }),
    );
  }

  Registration _tracked(PluginScope? scope, Registration registration) {
    scope?.track(registration);
    return registration;
  }

  @override
  void publish(BusEvent event) =>
      _inStep ? _publishStep(event) : publishFrame(event);

  /// Publishes [event] onto the frame channel, whatever is running.
  void publishFrame(BusEvent event) => _framePublished.add((event, _step));

  void _publishStep(BusEvent event) {
    assert(
      _codecs.containsKey(event.name),
      'the step event "${event.name}" (${event.runtimeType}) was published '
      'with no codec declared for it. A step event is digested by a replay '
      'and read by the view encoded, so declare it with its codec: '
      'events.declare<${event.runtimeType}>(\'${event.name}\', codec: …). '
      'An event only the view hears goes on the frame channel instead',
    );
    if (_stepEvents.length >= stepEventLimit) {
      throw StateError(
        'step $_step published more than $stepEventLimit events; a step '
        'subscriber that publishes what it receives loops for ever. The '
        'last was ${event.name}',
      );
    }
    _stepEvents.add(event);
  }

  // Plugins were reordered or switched: subscribers are sorted again before
  // the next delivery, by their plugins' new ranks.
  void _markOrderChanged() => _ordered = false;

  // Opens step [step].
  void _beginStep(int step, {required bool resimulated}) {
    _step = step;
    _inStep = true;
    _resimulated = resimulated;
    _stepEvents.clear();
  }

  // Closes the step: hands its events to the step subscribers, digests
  // them, and queues them for the frame channel.
  StepEventSummary _endStep() {
    _sortIfNeeded();
    // By index, since a subscriber may append; still inside the step, so
    // what it publishes lands on the step channel.
    for (var i = 0; i < _stepEvents.length; i++) {
      final event = _stepEvents[i];
      for (final subscriber in List<_Subscriber>.of(_stepSubscribers)) {
        subscriber.deliver(event, BusChannel.step, _step, i, _resimulated);
      }
    }
    _inStep = false;
    if (_collecting) {
      for (var i = 0; i < _stepEvents.length; i++) {
        final event = _stepEvents[i];
        final codec = _codecs[event.name];
        _collected.add(
          PublishedEvent(
            name: event.name,
            version: codec?.version ?? 0,
            data: codec?.encodeAny(event),
            step: _step,
            sequence: i,
            resimulated: _resimulated,
          ),
        );
      }
    }
    final entries = <List<Object?>>[
      for (final event in _stepEvents) _entry(event),
    ];
    final digests = <int>[for (final entry in entries) StateDigest.of(entry)];
    _queued.add(
      _QueuedStep(_step, _resimulated, List<BusEvent>.of(_stepEvents), digests),
    );
    final summary = StepEventSummary(
      step: _step,
      count: entries.length,
      digest: entries.isEmpty ? 0 : StateDigest.of(entries),
      resimulated: _resimulated,
      events: _stepEvents.isEmpty
          ? const <BusEvent>[]
          : List<BusEvent>.unmodifiable(_stepEvents),
    );
    _stepEvents.clear();
    return summary;
  }

  // Closes the first of a checked step's two runs: hands its events to the
  // step subscribers as `_endStep` does, since what they change is part of
  // the step, and returns the events' digest — then forgets them. Nothing is
  // queued for the frame channel and nothing is summarised: the run that
  // counts is the second.
  int _discardStep() {
    _sortIfNeeded();
    for (var i = 0; i < _stepEvents.length; i++) {
      final event = _stepEvents[i];
      for (final subscriber in List<_Subscriber>.of(_stepSubscribers)) {
        subscriber.deliver(event, BusChannel.step, _step, i, _resimulated);
      }
    }
    _inStep = false;
    final digest = _stepEvents.isEmpty
        ? 0
        : StateDigest.of(<List<Object?>>[
            for (final event in _stepEvents) _entry(event),
          ]);
    _stepEvents.clear();
    return digest;
  }

  // Hands the frame subscribers what the steps since the last call
  // published, reconciled, then the frame's own events. Once a frame.
  void _deliverFrame() {
    _sortIfNeeded();
    final queued = List<_QueuedStep>.of(_queued);
    _queued.clear();
    for (final step in queued) {
      final before = _shown[step.step];
      final now = <_Shown>[
        for (var i = 0; i < step.events.length; i++)
          _Shown(step.events[i], step.digests[i]),
      ];
      for (var i = 0; i < now.length; i++) {
        final seen = step.resimulated && before != null && i < before.length
            ? before[i]
            : null;
        if (seen != null && seen.digest == now[i].digest) continue;
        _fan(_frameSubscribers, now[i].event, step.step, i, step.resimulated);
      }
      if (step.resimulated && before != null) {
        for (var i = 0; i < before.length; i++) {
          if (i < now.length && now[i].digest == before[i].digest) continue;
          _fan(_retractSubscribers, before[i].event, step.step, i, true);
        }
      }
      if (now.isEmpty) {
        _shown.remove(step.step);
      } else {
        _shown[step.step] = now;
      }
      _shown.removeWhere((at, _) => at < step.step - reconcileWindow);
    }
    final published = List<(BusEvent, int)>.of(_framePublished);
    _framePublished.clear();
    for (var i = 0; i < published.length; i++) {
      final (event, step) = published[i];
      _fan(_frameSubscribers, event, step, i, false);
    }
  }

  void _fan(
    List<_Subscriber> subscribers,
    BusEvent event,
    int step,
    int sequence,
    bool resimulated,
  ) {
    for (final subscriber in List<_Subscriber>.of(subscribers)) {
      subscriber.deliver(event, BusChannel.frame, step, sequence, resimulated);
    }
  }

  /// Forgets what is queued and what was shown: a level restarted, whose
  /// old events belong to a run that is over.
  void clear() {
    _stepEvents.clear();
    _queued.clear();
    _framePublished.clear();
    _shown.clear();
  }

  void _sortIfNeeded() {
    if (_ordered) return;
    for (final list in <List<_Subscriber>>[
      _stepSubscribers,
      _frameSubscribers,
      _retractSubscribers,
    ]) {
      list.sort(_Subscriber.compare);
    }
    _ordered = true;
  }

  // What a digest folds in for [event]: its declared codec's version and
  // encoding, or what it writes into a sink when it has no codec.
  List<Object?> _entry(BusEvent event) {
    final codec = _codecs[event.name];
    if (codec != null) {
      return <Object?>[event.name, codec.version, codec.encodeAny(event)];
    }
    final sink = _ListSink(<Object?>[event.name]);
    event.digestInto(sink);
    return sink.values;
  }

  @override
  EventRegistry forPlugin(PluginScope scope) => _ScopedBus(this, scope);
}

/// Declares the events every genre shares, the engine's rather than any
/// one genre's — [ActorHurt], [ActorDied] and [SequenceSignal] — with their
/// codecs, each one not already declared on [events].
///
/// Called by every `GenrePlugin` as it is installed, so the first genre in
/// an engine declares them and a second finds them there. A game that steps
/// actors or a cutscene without a genre calls it itself.
///
/// **On the engine's bus even when handed a plugin's view of it**, and that
/// is why this lives beside the bus: declared through the first genre's
/// scope, they were named as that genre's (`actor.hurt` "declared by
/// shooter", against the rule that a genre's names carry its prefix) and
/// went with it when it was disabled, out from under the genre still
/// stepping actors.
void declareSimulationEvents(EventRegistry events) {
  final engine = events is _ScopedBus ? events._bus : events;
  bool declared(String name) => engine.declared.any((d) => d.name == name);
  if (!declared(ActorHurt.eventName)) {
    engine.declare<ActorHurt>(
      ActorHurt.eventName,
      description: 'An actor took damage and survived it.',
      codec: ActorHurt.codec,
    );
  }
  if (!declared(ActorDied.eventName)) {
    engine.declare<ActorDied>(
      ActorDied.eventName,
      description: "An actor's health reached zero.",
      codec: ActorDied.codec,
    );
  }
  if (!declared(SequenceSignal.eventName)) {
    engine.declare<SequenceSignal>(
      SequenceSignal.eventName,
      description: "A cutscene's signal fired.",
      codec: SequenceSignal.codec,
    );
  }
}

final class _ScopedBus extends EventRegistry {
  _ScopedBus(this._bus, this._scope);

  final EventBus _bus;
  final PluginScope _scope;

  @override
  List<EventDeclaration> get declared => _bus.declared;

  @override
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    String? description,
    EventCodec<T>? codec,
  }) => _bus._declare<T>(name, channel, description, codec, _scope);

  @override
  EventCodec<BusEvent>? codecFor(String name) => _bus.codecFor(name);

  @override
  Registration onRetracted<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => _bus._subscribe<T>(_bus._retractSubscribers, label, handler, _scope);

  @override
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) {
    if (!_scope.manifest.touches.simulates) {
      throw PluginException(
        'plugin "${_scope.manifest.id}" declares that it touches only the '
        'view, and subscribed "$label" to the step channel, which runs '
        'inside the step. Subscribe with onFrame, or declare touches: '
        'PluginTouches.simulation',
      );
    }
    return _bus._subscribe<T>(_bus._stepSubscribers, label, handler, _scope);
  }

  @override
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => _bus._subscribe<T>(_bus._frameSubscribers, label, handler, _scope);

  @override
  void publish(BusEvent event) => _bus.publish(event);

  @override
  EventRegistry forPlugin(PluginScope scope) => _bus.forPlugin(scope);
}

final class _ListSink extends EventDigestSink {
  _ListSink(this.values);

  final List<Object?> values;

  @override
  void add(Object? value) => values.add(value);
}

final class _Declared {
  _Declared(this.declaration);

  final EventDeclaration declaration;
}

final class _QueuedStep {
  const _QueuedStep(this.step, this.resimulated, this.events, this.digests);

  final int step;
  final bool resimulated;
  final List<BusEvent> events;
  final List<int> digests;
}

final class _Shown {
  const _Shown(this.event, this.digest);

  final BusEvent event;
  final int digest;
}

abstract base class _Subscriber {
  _Subscriber(this.label, this.scope, this.sequence);

  final String label;
  final PluginScope? scope;
  final int sequence;

  int get rank => scope?.rank ?? -1;

  void deliver(
    BusEvent event,
    BusChannel channel,
    int step,
    int index,
    bool resimulated,
  );

  static int compare(_Subscriber a, _Subscriber b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.sequence.compareTo(b.sequence);
  }
}

final class _TypedSubscriber<T extends BusEvent> extends _Subscriber {
  _TypedSubscriber(super.label, this.handler, super.scope, super.sequence);

  final EventHandler<T> handler;

  @override
  void deliver(
    BusEvent event,
    BusChannel channel,
    int step,
    int index,
    bool resimulated,
  ) {
    if (event is! T) return;
    handler(
      Delivered<T>(
        event: event,
        channel: channel,
        step: step,
        sequence: index,
        resimulated: resimulated,
      ),
    );
  }
}
