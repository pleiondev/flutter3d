/// Watching an authoritative simulation from elsewhere: [ObserverFeed] on
/// the machine that runs it, [SimulationObserver] on each that watches.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show InputFrame, Snapshot;

import 'peer_wire.dart';

/// What a [SimulationObserver] is sent, step by step: the run's tape, to
/// replay into a simulation of its own, or the published state, to draw.
///
/// **An open set by wire name**: a later protocol minor may add a mode
/// (fields only, a reduced level of detail).
final class ObserverMode {
  const ObserverMode._(this.name);

  /// The step's input — the players' frame and the telemetry fed in — which
  /// an observer on the same simulation replays into its own copy, bit for
  /// bit. Only for a simulation whose profile is bit-exact, and an
  /// observer whose simulation version is the feed's.
  static const ObserverMode tape = ObserverMode._('tape');

  /// The step's published state — the poses, the published components,
  /// the events and the probe readings — which an observer draws as it
  /// comes. What a simulation under the accurate profile sends, and what
  /// an observer on another build is sent instead of a tape it would not
  /// replay.
  static const ObserverMode poses = ObserverMode._('poses');

  static const List<ObserverMode> values = <ObserverMode>[tape, poses];

  /// The mode [name] names; null for one this build does not know.
  static ObserverMode? byName(String name) =>
      values.where((m) => m.name == name).firstOrNull;

  final String name;

  @override
  String toString() => name;
}

/// Whether a snapshot an observer is sent is the whole state or the change
/// since the last one it was sent.
///
/// **Named on the wire from 1.0, though 1.0 sends only [full].** A later
/// protocol minor sends deltas to observers that say they read them; a
/// 1.0 observer reads the name and asks for a full one where it cannot.
final class ObserverSnapshot {
  const ObserverSnapshot._(this.name);

  static const ObserverSnapshot full = ObserverSnapshot._('full');
  static const ObserverSnapshot delta = ObserverSnapshot._('delta');

  static const List<ObserverSnapshot> values = <ObserverSnapshot>[full, delta];

  /// The kind [name] names; null for one this build does not know.
  static ObserverSnapshot? byName(String name) =>
      values.where((s) => s.name == name).firstOrNull;

  final String name;

  @override
  String toString() => name;
}

/// What one observer wants sent: which probes' readings, by id. Null for
/// every probe.
///
/// **Per observer**, so a dashboard that charts one gauge is not sent a
/// plant's thousand; the feed addresses each its own message.
final class ObserverFilter {
  const ObserverFilter({this.probes});

  /// The probes whose readings to send, or null for all of them.
  final Set<String>? probes;

  /// Every reading, none filtered out.
  static const ObserverFilter everything = ObserverFilter();

  /// The readings of [readings] this filter lets through.
  List<ProbeReading> pass(List<ProbeReading> readings) => switch (probes) {
    null => readings,
    final ids => <ProbeReading>[
      for (final reading in readings)
        if (ids.contains(reading.probe)) reading,
    ],
  };

  Map<String, Object?> toJson() => <String, Object?>{
    if (probes case final ids?) 'probes': (ids.toList()..sort()),
  };

  factory ObserverFilter.fromJson(Object? json) => switch (json) {
    {'probes': final List<Object?> ids} => ObserverFilter(
      probes: <String>{for (final id in ids) '$id'},
    ),
    _ => everything,
  };
}

/// The engine's observer messages: under [PeerWire.engineKey], so a game's
/// own messages on the same wire never collide with them.
abstract final class ObserverMessages {
  /// An observer arriving, with its simulation and its filter.
  static const String join = 'observe.join';

  /// The feed's answer: the mode it will send, its simulation, and a
  /// snapshot to start from.
  static const String start = 'observe.start';

  /// One step.
  static const String step = 'observe.step';
}

/// The machine that runs the authoritative simulation, sending it to
/// whoever observes: a twin's server to its dashboards, a laboratory's
/// bench to a class, a match to its spectators.
///
/// Call [stepped] after every step the simulation runs, with the input it
/// ran on and what it published. An observer that joins is sent where the
/// simulation is ([capture] in [ObserverMode.tape], the published state in
/// [ObserverMode.poses]) and then every step after it, each addressed to it
/// alone through the relay's observer path with its own [ObserverFilter].
final class ObserverFeed {
  ObserverFeed({
    required this.wire,
    required this.simulation,
    required this.capture,
  }) {
    _listening = wire.listenFrom(_hear);
  }

  final PeerWire wire;

  /// The simulation the feed runs: whether its profile is bit-exact decides
  /// whether a tape can be sent at all.
  final SimulationVersion simulation;

  /// The state now, as a snapshot an observer restores before replaying
  /// the steps after it: `EngineLoop.capture`.
  final Snapshot Function() capture;

  late final Registration _listening;

  final Map<int, ({ObserverMode mode, ObserverFilter filter})> _observers =
      <int, ({ObserverMode mode, ObserverFilter filter})>{};

  PublishedState? _last;
  int _step = 0;

  /// The observers being sent to, by slot.
  Iterable<int> get observers => _observers.keys;

  void _hear(int from, Map<String, Object?> message) {
    if (message[PeerWire.engineKey] != ObserverMessages.join) return;
    final theirs = switch (message['simulation']) {
      final Map<Object?, Object?> json => SimulationVersion.fromJson(
        json.cast<String, Object?>(),
      ),
      _ => null,
    };
    // A tape only to an observer that would replay it as it ran here.
    final wantsTape = message['mode'] != ObserverMode.poses.name;
    final mode =
        wantsTape &&
            simulation.profile.isBitExact &&
            theirs != null &&
            theirs.refusalOn(simulation) == null
        ? ObserverMode.tape
        : ObserverMode.poses;
    final filter = ObserverFilter.fromJson(message['filter']);
    _observers[from] = (mode: mode, filter: filter);
    wire.send(<String, Object?>{
      PeerWire.engineKey: ObserverMessages.start,
      'to': from,
      'mode': mode.name,
      'simulation': simulation.toJson(),
      'snapshot': ObserverSnapshot.full.name,
      'from': _step,
      'state': switch (mode) {
        ObserverMode.tape => capture().toJson(),
        _ => _filtered(_last, filter)?.toWire(),
      },
    });
  }

  /// Sends step [published].step to every observer: [input], the frame the
  /// step ran on, to those replaying the tape, and [published] to those
  /// drawing poses.
  void stepped(InputFrame input, PublishedState published) {
    _step = published.step;
    _last = published;
    for (final MapEntry(key: slot, value: (:mode, :filter))
        in _observers.entries) {
      wire.send(<String, Object?>{
        PeerWire.engineKey: ObserverMessages.step,
        'to': slot,
        'step': published.step,
        if (mode == ObserverMode.tape) ...<String, Object?>{
          'input': input.toJson(),
          if (input.external.isNotEmpty)
            'external': <Object?>[
              for (final reading in input.external) reading.toJson(),
            ],
          'probes': <Object?>[
            for (final reading in filter.pass(published.probes))
              reading.toJson(),
          ],
        } else
          'state': _filtered(published, filter)!.toWire(),
      });
    }
  }

  static PublishedState? _filtered(
    PublishedState? state,
    ObserverFilter filter,
  ) => state == null || filter.probes == null
      ? state
      : PublishedState(
          step: state.step,
          seconds: state.seconds,
          origin: state.origin,
          components: state.components,
          positions: state.positions,
          events: state.events,
          simulation: state.simulation,
          probes: filter.pass(state.probes),
        );

  /// Stops listening for observers.
  void close() => _listening.cancel();
}

/// A machine watching an authoritative simulation an [ObserverFeed] sends.
///
/// [join] says it is here, with the simulation it runs and what it wants;
/// the feed answers with a [mode]. In [ObserverMode.tape] it is handed a
/// snapshot to [restore] and every step's frame to [replay], its telemetry
/// and all, so its own copy runs the same steps; in [ObserverMode.poses] it
/// is handed each step's published state, to [show].
final class SimulationObserver {
  SimulationObserver({
    required this.wire,
    required this.simulation,
    this.filter = ObserverFilter.everything,
    this.restore,
    this.replay,
    this.show,
    this.readings,
    this.wantsTape = true,
  }) {
    _listening = wire.listenFrom(_hear);
  }

  final PeerWire wire;

  /// The simulation this machine runs, which decides whether it is sent the
  /// tape: a build on another one is sent poses.
  final SimulationVersion simulation;

  /// The probes it wants readings of.
  final ObserverFilter filter;

  /// Puts this machine's simulation where the feed's is, for the tape:
  /// [start] taken after [step] steps, as `EngineLoop.rewindTo(step, state:
  /// start)` takes it.
  final void Function(Snapshot start, int step)? restore;

  /// Runs one step on [input], for the tape.
  final void Function(InputFrame input)? replay;

  /// Draws one step's published state, for poses.
  final void Function(PublishedState state)? show;

  /// Hears each step's probe readings, whichever the mode.
  final void Function(List<ProbeReading> readings)? readings;

  /// Whether to ask for the tape where the feed can send it; false asks for
  /// poses whatever the simulation.
  final bool wantsTape;

  late final Registration _listening;

  /// What the feed sends, once it has answered; null before.
  ObserverMode? get mode => _mode;
  ObserverMode? _mode;

  /// The feed's simulation, once it has answered.
  SimulationVersion? get feeding => _feeding;
  SimulationVersion? _feeding;

  /// The step the next message carries, once started.
  int? get next => _next;
  int? _next;

  /// Says it is here: send again until [mode] is set, since the feed may
  /// not have heard it the first time.
  void join() => wire.send(<String, Object?>{
    PeerWire.engineKey: ObserverMessages.join,
    'simulation': simulation.toJson(),
    'mode': (wantsTape ? ObserverMode.tape : ObserverMode.poses).name,
    'filter': filter.toJson(),
  });

  void _hear(int from, Map<String, Object?> message) {
    final to = message['to'];
    if (to is int && to != wire.slot) return;
    switch (message[PeerWire.engineKey]) {
      case ObserverMessages.start when _mode == null:
        _start(message);
      case ObserverMessages.step when _mode != null:
        _step(message);
      default:
        break;
    }
  }

  void _start(Map<String, Object?> message) {
    final mode = ObserverMode.byName('${message['mode']}');
    final snapshot = ObserverSnapshot.byName('${message['snapshot']}');
    // A mode or a snapshot of a later minor: ask again for what this build
    // reads rather than draw a state it misreads.
    if (mode == null || snapshot != ObserverSnapshot.full) return;
    _mode = mode;
    _feeding = switch (message['simulation']) {
      final Map<Object?, Object?> json => SimulationVersion.fromJson(
        json.cast<String, Object?>(),
      ),
      _ => null,
    };
    _next = (message['from'] as int?) ?? 0;
    final state = message['state'];
    if (mode == ObserverMode.tape && state is Map) {
      restore?.call(Snapshot.fromJson(state.cast<String, Object?>()), _next!);
    } else if (state != null) {
      _show(PublishedState.fromWire(state));
    }
  }

  void _step(Map<String, Object?> message) {
    final step = message['step'];
    if (step is! int) return;
    _next = step;
    if (_mode == ObserverMode.tape) {
      final input = message['input'];
      if (input is! Map) return;
      replay?.call(
        InputFrame.fromJson(
          input.cast<String, Object?>(),
        ).withExternal(<ExternalStateInput>[
          for (final reading
              in message['external'] as List<Object?>? ?? const <Object?>[])
            ExternalStateInput.fromJson(reading),
        ]),
      );
      readings?.call(<ProbeReading>[
        for (final reading
            in message['probes'] as List<Object?>? ?? const <Object?>[])
          ProbeReading.fromJson(reading),
      ]);
    } else if (message['state'] case final Object state) {
      _show(PublishedState.fromWire(state));
    }
  }

  void _show(PublishedState state) {
    show?.call(state);
    readings?.call(state.probes);
  }

  /// Stops listening.
  void close() => _listening.cancel();
}
