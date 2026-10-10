/// The bus: two channels, a fixed order, rollbacks reconciled, and a digest
/// per step.
///
///     dart test test/event_bus_test.dart
///
/// Each test was written by breaking what it covers first; the mutation
/// that would defeat it is named in the test.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

final class _Landed extends BusEvent {
  const _Landed(this.x);

  final int x;

  static final EventCodec<_Landed> codec = EventCodec<_Landed>.of(
    encode: (event) => event.x,
    decode: (data, _) => data is int ? _Landed(data) : null,
  );

  @override
  String get name => 'test.landed';

  @override
  void digestInto(EventDigestSink sink) => sink.add(x);
}

final class _Echo extends BusEvent {
  const _Echo();

  static final EventCodec<_Echo> codec = EventCodec<_Echo>.of(
    encode: (_) => null,
    decode: (_, _) => const _Echo(),
  );

  @override
  String get name => 'test.echo';
}

final class _Coin extends GameEvent {
  const _Coin();

  static final EventCodec<_Coin> codec = EventCodec<_Coin>.of(
    encode: (_) => null,
    decode: (_, _) => const _Coin(),
  );

  @override
  String get name => 'test.coin';
}

/// A run that publishes a coin each step onto the bus it was handed.
final class _Run {
  EventRegistry? _bus;

  Registration publishTo(EventRegistry bus) {
    _bus = bus;
    return Registration(() {
      if (identical(_bus, bus)) _bus = null;
    });
  }

  void step() => _bus?.publish(const _Coin());
}

final class _Genre extends GenrePlugin<_Run> {
  @override
  PluginManifest get manifest => PluginManifest(
    id: 'test.genre',
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.simulation,
  );

  @override
  String get systemName => 'test.step';

  @override
  void stepSimulation(_Run simulation, LoopContext context) =>
      simulation.step();

  @override
  Registration? publishEvents(_Run simulation, EventRegistry bus) =>
      simulation.publishTo(bus);

  @override
  void declareEvents(EventRegistry events) =>
      events.declare<_Coin>('test.coin', codec: _Coin.codec);

  @override
  Snapshot captureSimulation(_Run simulation) =>
      const Snapshot(<String, Object?>{});

  @override
  void restoreSimulation(_Run simulation, Snapshot state) {}
}

/// A second genre in the same engine, with no events of its own.
final class _Second extends GenrePlugin<_Run> {
  @override
  PluginManifest get manifest => PluginManifest(
    id: 'test.second',
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.simulation,
  );

  @override
  String get systemName => 'test.second.step';

  @override
  void stepSimulation(_Run simulation, LoopContext context) {}

  @override
  Snapshot captureSimulation(_Run simulation) =>
      const Snapshot(<String, Object?>{});

  @override
  void restoreSimulation(_Run simulation, Snapshot state) {}
}

/// A plugin that subscribes [label] to the step channel.
final class _Listens extends Flutter3dPlugin {
  _Listens(this.id, this.log);

  final String id;
  final List<String> log;

  @override
  PluginManifest get manifest =>
      PluginManifest(id: id, apiVersion: PluginApiVersion.current);

  @override
  void install(PluginHost host) {
    host.events.onStep<_Landed>(id, (d) => log.add('$id:${d.event.x}'));
  }
}

/// A loop whose `rules` phase lands at each x [script] gives for the step.
EngineLoop _loop(
  List<int> Function(int step) script, {
  List<Flutter3dPlugin> plugins = const <Flutter3dPlugin>[],
}) => EngineLoop(input: InputState(), plugins: plugins)
  // A step event is declared with its codec, or the bus refuses it.
  ..events.declare<_Landed>('test.landed', codec: _Landed.codec)
  ..events.declare<_Echo>('test.echo', codec: _Echo.codec)
  ..addSystem('land', LoopPhase.rules, (c) {
    for (final x in script(c.step)) {
      c.publish(_Landed(x));
    }
  });

void main() {
  test(
    'step subscribers hear every event at the step end, in a fixed order',
    () {
      // The application's subscriber first, then the plugins' in install
      // order, each event to all of them before the next event.
      //
      // Mutation: deliver per subscriber rather than per event. The log
      // becomes a:1, a:2, b:1, b:2.
      final log = <String>[];
      final loop = _loop(
        (step) => switch (step) {
          0 => const <int>[1, 2],
          1 => const <int>[3],
          _ => const <int>[],
        },
        plugins: <Flutter3dPlugin>[_Listens('a', log), _Listens('b', log)],
      );
      loop.events.onStep<_Landed>('app', (d) => log.add('app:${d.event.x}'));
      var deliveredInStep = false;
      loop.addSystem(
        'check',
        LoopPhase.publish,
        (_) => deliveredInStep = log.isNotEmpty,
      );
      loop.frame(1.0 / 60.0);
      expect(
        deliveredInStep,
        isFalse,
        reason: 'collected, handed out at the end',
      );
      expect(log, <String>['app:1', 'a:1', 'b:1', 'app:2', 'a:2', 'b:2']);

      // Reordered, the plugins' subscribers swap places; the app stays first.
      log.clear();
      loop.plugins.reorder(const <String>['b', 'a']);
      loop.runSteps(1);
      expect(log, <String>['app:3', 'b:3', 'a:3']);
    },
  );

  test(
    'what a step subscriber publishes is delivered within the same step',
    () {
      final seen = <String>[];
      final loop = _loop((step) => step == 0 ? const <int>[7] : const <int>[]);
      loop.events
        ..onStep<_Landed>('echoes', (d) => loop.events.publish(const _Echo()))
        ..onStep<_Echo>('hears', (d) => seen.add('${d.step}#${d.sequence}'));
      final summaries = <StepEventSummary>[];
      loop.onStepEnd(summaries.add);
      loop.frame(1.0 / 60.0);
      expect(seen, <String>['0#1']);
      expect(summaries.single.count, 2);
    },
  );

  test('a view plugin cannot subscribe to the step channel', () {
    expect(
      () => EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[_ViewListens()],
      ),
      throwsA(isA<PluginException>()),
    );
  });

  group('a rollback', () {
    test('re-delivers on the step channel and not on the frame channel', () {
      // Mutation: drop the `seen.digest == now.digest` skip. Every landing
      // of the re-run steps is heard a second time.
      final stepHeard = <String>[];
      final frameHeard = <String>[];
      final retracted = <String>[];
      var landAt = 5;
      // Captures kept, so a rewind has a state to go back to.
      final loop = _loop((step) => step == 2 ? <int>[landAt] : const <int>[])
        ..keep(window: 10);
      loop.events
        ..onStep<_Landed>(
          'world',
          (d) => stepHeard.add('${d.event.x}${d.resimulated ? ' again' : ''}'),
        )
        ..onFrame<_Landed>(
          'sound',
          (d) => frameHeard.add('${d.event.x}${d.resimulated ? ' late' : ''}'),
        )
        ..onRetracted<_Landed>('unsound', (d) => retracted.add('${d.event.x}'));
      for (var i = 0; i < 4; i++) {
        loop.frame(1.0 / 60.0);
      }
      expect(frameHeard, <String>['5']);

      // Back to step 1 and the same steps again: the world hears them, the
      // speakers do not.
      loop
        ..rewindTo(1)
        ..runSteps(3, resimulated: true)
        ..frame(0.0);
      expect(stepHeard, <String>['5', '5 again']);
      expect(frameHeard, <String>['5']);
      expect(retracted, isEmpty);

      // Again, with the correction landing elsewhere: the new landing is
      // shown, marked, and the old one is taken back.
      landAt = 6;
      loop
        ..rewindTo(1)
        ..runSteps(3, resimulated: true)
        ..frame(0.0);
      expect(frameHeard, <String>['5', '6 late']);
      expect(retracted, <String>['5']);
    });

    test('a resimulated step says so to its systems and is not recorded', () {
      final flags = <bool>[];
      final loop = EngineLoop(input: InputState())
        ..keep(window: 10)
        ..addSystem('flag', LoopPhase.input, (c) => flags.add(c.isResimulated));
      final recorder = InputTapeRecorder(seed: 0);
      loop.recorders.add(recorder);
      loop.frame(1.0 / 60.0);
      loop
        ..rewindTo(0)
        ..runSteps(1, resimulated: true);
      expect(flags, <bool>[false, true]);
      expect(recorder.tape.steps, 1, reason: 'written the first time only');
    });
  });

  group('the digest', () {
    List<StepEventSummary> run(List<int> Function(int step) script) {
      final loop = _loop(script);
      final summaries = <StepEventSummary>[];
      loop.onStepEnd(summaries.add);
      loop.runSteps(10);
      return summaries;
    }

    List<int> busy(int step) =>
        step.isEven ? <int>[step, step + 1] : const <int>[];

    test('two identical runs digest identically, step by step', () {
      final a = run(busy);
      final b = run(busy);
      expect(a.map((s) => s.digest), b.map((s) => s.digest));
      expect(a.where((s) => s.count == 0).map((s) => s.digest).toSet(), <int>{
        0,
      });
    });

    test('one differing field changes that step and no other', () {
      // Mutation: digest names only, not `digestInto`'s fields. Step 4's
      // digest would not move.
      final a = run(busy);
      final b = run((step) => step == 4 ? <int>[4, 99] : busy(step));
      for (var i = 0; i < a.length; i++) {
        expect(a[i].digest == b[i].digest, i != 4, reason: 'step $i');
      }
      final trace = EventTrace();
      final other = EventTrace();
      for (final s in a) {
        trace.observe(s.step, count: s.count, digest: s.digest);
      }
      for (final s in b) {
        other.observe(s.step, count: s.count, digest: s.digest);
      }
      expect(other.divergenceFrom(trace)?.step, 4);
      expect(trace.divergenceFrom(trace), isNull);
      expect(EventTrace.fromJson(trace.toJson()).divergenceFrom(trace), isNull);
    });

    test('an event moved a step later diverges at the earlier step', () {
      final a = run((step) => step == 3 ? <int>[1] : const <int>[]);
      final b = run((step) => step == 4 ? <int>[1] : const <int>[]);
      EventTrace traceOf(List<StepEventSummary> run) {
        final trace = EventTrace();
        for (final s in run) {
          trace.observe(s.step, count: s.count, digest: s.digest);
        }
        return trace;
      }

      final divergence = traceOf(b).divergenceFrom(traceOf(a));
      expect(divergence?.step, 3);
      expect(divergence?.foundDigest, isNull);
    });
  });

  test("a genre's run publishes onto the bus while it is the one stepped", () {
    // Mutation: leave `GenrePlugin.simulation`'s setter pointing the old run
    // at the bus. The run that was replaced still publishes, and the coin is
    // heard twice a step.
    final genre = _Genre();
    final heard = <String>[];
    final ends = <StepEventSummary>[];
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[genre],
    )..onStepEnd(ends.add);
    loop.events.onStep<GameEvent>('rules', (d) => heard.add(d.event.name));
    final first = _Run();
    genre.simulation = first;
    loop.frame(1.0 / 60.0);
    expect(heard, <String>['test.coin']);
    expect(ends.single.events.single, isA<_Coin>());
    genre.simulation = _Run();
    first.step();
    loop.frame(1.0 / 60.0);
    expect(heard, hasLength(2));
    expect(
      loop.events.declared.map((d) => d.name),
      containsAll(<String>[ActorHurt.eventName, SequenceSignal.eventName]),
    );
  });

  test("the events every genre shares are the engine's, not the first "
      "genre's", () {
    // Mutation: declare them through the genre's scoped bus, as before —
    // they carry the first genre's id, so a genre's own "every event I
    // declare is prefixed with me" fails on `actor.hurt`, and disabling that
    // genre takes them from the second one with it.
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[_Genre(), _Second()],
    );
    const shared = <String>[
      ActorHurt.eventName,
      ActorDied.eventName,
      SequenceSignal.eventName,
    ];
    expect(
      <String>[
        for (final d in loop.events.declared)
          if (shared.contains(d.name)) d.declaredBy,
      ],
      <String>['app', 'app', 'app'],
    );
    loop.plugins.disable('test.genre');
    expect(
      loop.events.declared.map((d) => d.name),
      containsAll(shared),
      reason: 'the second genre still publishes them',
    );
  });

  test('two plugins cannot declare one event name', () {
    final loop = EngineLoop(input: InputState());
    loop.events.declare<_Landed>('test.landed');
    expect(
      () => loop.events.declare<_Echo>('test.landed'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          allOf(contains('app'), contains('test.landed')),
        ),
      ),
    );
    expect(
      loop.events.declared.where((d) => d.name == 'test.landed').single.type,
      _Landed,
    );
  });
}

final class _ViewListens extends Flutter3dPlugin {
  @override
  PluginManifest get manifest => const PluginManifest(
    id: 'hud',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.view,
  );

  @override
  void install(PluginHost host) {
    host.events.onStep<_Landed>('hud', (_) {});
  }
}
