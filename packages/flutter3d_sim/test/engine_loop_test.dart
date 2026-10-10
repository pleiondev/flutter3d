/// `EngineLoop`: phases and their order, time, lost time, and plugins
/// switched at a step boundary in a way a replay reproduces.
///
///     dart test test/engine_loop_test.dart
///
/// The timing tests step a 64 Hz world in frames of whole sixty-fourths, so
/// every sum is exact in binary and a step count is a fact rather than a
/// rounding. Each test was written by breaking what it covers first; the
/// mutation that would defeat it is named in the test.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

const LoopPhase _combat = LoopPhase.step('combat');
const WorldTiming _binary = WorldTiming(stepRate: 64.0);
const double _tick = 1.0 / 64.0;

/// A plugin that adds a system to [phase] writing its id into [log].
final class _Writes extends Flutter3dPlugin {
  _Writes(
    this.id,
    this.log, {
    this.phase = LoopPhase.rules,
    this.touches = PluginTouches.simulation,
    this.dependsOn = const <String>[],
  });

  final String id;
  final List<String> log;
  final LoopPhase phase;
  final PluginTouches touches;
  final List<String> dependsOn;

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: PluginApiVersion.current,
    touches: touches,
    dependsOn: dependsOn,
  );

  @override
  void install(PluginHost host) {
    host.loop.addSystem(id, phase, (c) => log.add('${c.step}:$id'));
  }
}

final class _Ping extends BusEvent {
  const _Ping(this.value);

  final int value;

  static final EventCodec<_Ping> codec = EventCodec<_Ping>.of(
    encode: (event) => event.value,
    decode: (data, _) => data is int ? _Ping(data) : null,
  );

  @override
  String get name => 'test.ping';

  @override
  void digestInto(EventDigestSink sink) => sink.add(value);
}

void main() {
  group('phases', () {
    test('the engine phases run in the order the decision lists', () {
      final loop = EngineLoop(input: InputState());
      expect(loop.phases(PhaseKind.step).map((p) => p.name), <String>[
        'input',
        'movers',
        'physics',
        'fields',
        'rules',
        'publish',
      ]);
      expect(loop.phases(PhaseKind.frame).map((p) => p.name), <String>[
        'animate',
        'audio',
        'camera',
        'render',
        'ui',
      ]);
    });

    test('a step runs every step phase in order, then the frame phases', () {
      // Mutation: run the frame phases before the post-step delivery. The
      // frame's "audio" would not yet have heard the step it follows.
      final seen = <String>[];
      final loop = EngineLoop(input: InputState())
        ..events.declare<_Ping>('test.ping', codec: _Ping.codec);
      for (final phase in <LoopPhase>[
        ...LoopPhase.stepPhases,
        ...LoopPhase.framePhases,
      ]) {
        loop.addSystem('log ${phase.name}', phase, (c) {
          seen.add(phase.name);
          if (phase == LoopPhase.rules) c.publish(const _Ping(1));
        });
      }
      loop.events.onFrame<_Ping>('heard', (_) => seen.add('ping'));
      expect(loop.frame(1.0 / 60.0), 1);
      expect(seen, <String>[
        ...LoopPhase.stepPhases.map((p) => p.name),
        'ping',
        ...LoopPhase.framePhases.map((p) => p.name),
      ]);
    });

    test('a frame phase reads published state, not the world', () {
      // Mutation: hand a frame phase the world as a step phase has it. A
      // view written that way stops working the day the simulation runs in
      // another isolate, and nothing said so.
      final loop = EngineLoop(input: InputState())
        ..events.declare<_Ping>('test.ping', codec: _Ping.codec)
        ..addSystem('ping', LoopPhase.rules, (c) => c.publish(_Ping(c.step)));
      final entity = loop.world.spawn();
      loop.world.set(entity, const WorldPosition(1.0, 2.0, 3.0));
      Object? worldRead;
      PublishedState? seen;
      loop.addSystem('view', LoopPhase.render, (c) {
        try {
          c.world;
        } on StateError catch (error) {
          worldRead = error;
        }
        seen = c.published;
      });
      loop
        ..frame(1.0 / 60.0)
        ..frame(1.0 / 60.0);
      expect(worldRead, isA<StateError>());
      expect(seen!.positionOf(entity), const WorldPosition(1.0, 2.0, 3.0));
      expect(
        seen!.eventsNamed('test.ping').single.decode(_Ping.codec)?.value,
        1,
        reason: "the second step's event, encoded and read back",
      );
    });

    test('a plugin phase named between two sits between them', () {
      final loop = EngineLoop(input: InputState())
        ..addPhase(
          _combat,
          after: const <String>['physics'],
          before: const <String>['fields'],
        );
      expect(loop.phases(PhaseKind.step).map((p) => p.name), <String>[
        'input',
        'movers',
        'physics',
        'combat',
        'fields',
        'rules',
        'publish',
      ]);
      expect(
        () => loop.addPhase(const LoopPhase.frame('combat')),
        throwsArgumentError,
        reason: 'a name is unique across both kinds',
      );
      expect(
        () => loop.addPhase(
          const LoopPhase.step('late'),
          after: const <String>['render'],
        ),
        throwsArgumentError,
        reason: 'a step phase is not ordered against a frame phase',
      );
    });

    test('systems sort by constraints, ties by registration', () {
      // Constraints move only what they name: "smoke" comes up to the place
      // of "wind", which waits for it, and "heat" to the place of "fire";
      // "weather" keeps its place between them.
      //
      // Mutation: take the earliest registered free system instead of the
      // one the earliest waiting system needs. "weather" leads.
      final loop = EngineLoop(input: InputState());
      void add(
        String name, {
        List<String> after = const <String>[],
        List<String> before = const <String>[],
      }) => loop.addSystem(
        name,
        LoopPhase.fields,
        (_) {},
        after: after,
        before: before,
      );
      add('wind');
      add('weather');
      add('fire', after: <String>['heat']);
      add('heat');
      add('smoke', before: <String>['wind']);
      expect(loop.systemsIn(LoopPhase.fields), <String>[
        'smoke',
        'wind',
        'weather',
        'heat',
        'fire',
      ]);
    });

    test('a cycle between systems is an error naming them', () {
      final loop = EngineLoop(input: InputState())
        ..addSystem('a', LoopPhase.rules, (_) {}, after: const <String>['b'])
        ..addSystem('b', LoopPhase.rules, (_) {}, after: const <String>['a'])
        ..addSystem('c', LoopPhase.rules, (_) {});
      expect(
        () => loop.frame(1.0 / 60.0),
        throwsA(
          isA<ConstraintCycleException>()
              .having((e) => e.cycle.toSet(), 'cycle', <String>{'a', 'b'})
              .having((e) => e.what, 'what', 'systems in rules'),
        ),
      );
    });

    test('a view plugin may not add to the step', () {
      // Mutation: drop the check in `_ScopedLoop.addSystem`. The view
      // plugin's system runs inside the step, and its toggle is journalled
      // as one a replay may ignore.
      expect(
        () => EngineLoop(
          input: InputState(),
          plugins: <Flutter3dPlugin>[
            _Writes('bloom', <String>[], touches: PluginTouches.view),
          ],
        ),
        throwsA(
          isA<PluginException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"bloom"'), contains('rules')),
          ),
        ),
      );
      final log = <String>[];
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[
          _Writes(
            'bloom',
            log,
            phase: LoopPhase.render,
            touches: PluginTouches.view,
          ),
        ],
      );
      loop.frame(1.0 / 60.0);
      expect(log, <String>['1:bloom']);
    });
  });

  group('time', () {
    test("the step rate is the world's, and dt is one step of it", () {
      // Mutation: hard-code 1/60 in `stepSeconds`. A 32 Hz world runs
      // almost twice the steps, each too small.
      final dts = <double>[];
      final loop = EngineLoop(
        input: InputState(),
        timing: const WorldTiming(stepRate: 32.0),
      )..addSystem('dt', LoopPhase.physics, (c) => dts.add(c.dt));
      var steps = 0;
      for (var i = 0; i < 64; i++) {
        steps += loop.frame(_tick);
      }
      expect(steps, 32);
      expect(dts.toSet(), <double>{1.0 / 32.0});
    });

    test('a changed world takes effect at the boundary and is journalled', () {
      final loop = EngineLoop(input: InputState());
      loop.frame(1.0 / 60.0);
      loop.changeTiming(const WorldTiming(stepRate: 120.0));
      expect(loop.stepSeconds, 1.0 / 60.0, reason: 'not before a step');
      loop.runSteps(1);
      expect(loop.stepSeconds, 1.0 / 120.0);
      expect(loop.journal.single, const LoopStepRate(step: 1, rate: 120.0));
      expect(loop.journal.single.affectsSimulation, isTrue);
    });

    test('time scale changes the steps per second, not dt', () {
      // Mutation: scale dt instead of the accumulated time. Half speed runs
      // every step at half a step, and a slowed run arrives elsewhere.
      final dts = <double>[];
      final loop = EngineLoop(input: InputState(), timing: _binary)
        ..addSystem('dt', LoopPhase.physics, (c) => dts.add(c.dt))
        ..timeScale = 0.5;
      var steps = 0;
      for (var i = 0; i < 64; i++) {
        steps += loop.frame(_tick);
      }
      expect(steps, 32);
      expect(dts.toSet(), <double>{_tick});
      expect(loop.journal.single, const LoopTimeScale(step: 0, scale: 0.5));
      expect(loop.journal.single.affectsSimulation, isFalse);

      loop.timeScale = 2.0;
      steps = 0;
      for (var i = 0; i < 64; i++) {
        steps += loop.frame(_tick);
      }
      expect(steps, 128);
    });

    test('announce drops past the cap and says so on the frame channel', () {
      // Mutation: drop the backlog without publishing. The machine that
      // cannot keep up runs slowly and says nothing.
      final lost = <TimeLost>[];
      final loop = EngineLoop(
        input: InputState(),
        timing: _binary,
        catchUp: const CatchUp.announce(maxStepsPerFrame: 3),
      );
      loop.events.onFrame<TimeLost>('pace', (d) => lost.add(d.event));
      expect(loop.frame(10 * _tick), 3);
      expect(lost.single.steps, 7);
      expect(lost.single.reason, TimeLostReason.overBudget);
      expect(loop.lostSteps, 7);
      expect(loop.frame(_tick), 1, reason: 'the debt was dropped');
    });

    test('within carries the debt to later frames, up to its cap', () {
      // Mutation: treat `within` as `announce`. The frames after the hitch
      // run nothing extra and the hitch is lost.
      final lost = <TimeLost>[];
      final loop = EngineLoop(
        input: InputState(),
        timing: _binary,
        catchUp: const CatchUp.within(maxStepsPerFrame: 3, backlog: 6 * _tick),
      );
      loop.events.onFrame<TimeLost>('pace', (d) => lost.add(d.event));
      // Ten steps owed: three run, six carried, one past the cap announced.
      expect(loop.frame(10 * _tick), 3);
      expect(lost.single.steps, 1);
      expect(loop.frame(0.0), 3, reason: 'the carried debt is run');
      expect(loop.frame(0.0), 3);
      expect(loop.frame(0.0), 0);
      expect(lost, hasLength(1));
    });

    test('a frame longer than the longest is announced, not stepped', () {
      final lost = <TimeLost>[];
      final loop = EngineLoop(
        input: InputState(),
        timing: _binary,
        longestFrame: 3 * _tick,
      );
      loop.events.onFrame<TimeLost>('pace', (d) => lost.add(d.event));
      expect(loop.frame(30.0), 3);
      expect(lost.single.reason, TimeLostReason.longFrame);
      expect(lost.single.seconds, 30.0 - 3 * _tick);
      expect(loop.lostSeconds, lost.single.seconds);
      expect(loop.lostSteps, 0, reason: 'a long frame loses no whole step');
    });

    test('a pause steps nothing and hands the clock nothing', () {
      final loop = EngineLoop(input: InputState())..isPaused = true;
      expect(loop.frame(1.0), 0);
      expect(loop.lastFrame, 0.0);
      loop.isPaused = false;
      expect(loop.frame(1.0 / 60.0), 1, reason: 'the pause was not owed');
      expect(loop.lostSteps, 0);
    });
  });

  group('plugins at run time', () {
    ({List<String> log, List<LoopChange> journal}) run({
      List<LoopChange>? replay,
    }) {
      final log = <String>[];
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[
          _Writes('heat', log),
          _Writes('fire', log, dependsOn: const <String>['heat']),
          _Writes('wind', log),
        ],
      );
      if (replay != null) loop.schedule(replay);
      for (var frame = 0; frame < 12; frame++) {
        if (replay == null && frame == 4) loop.plugins.disable('fire');
        if (replay == null && frame == 8) {
          loop.plugins
            ..enable('fire')
            ..reorder(const <String>['wind', 'heat', 'fire']);
        }
        loop.frame(1.0 / 60.0);
      }
      return (log: log, journal: loop.journal);
    }

    test('a switch waits for the boundary and a replay makes it there', () {
      // Mutation: install in `PluginManager.enable` rather than at the
      // boundary. The live run starts "fire" between frames; the replay,
      // from its journal, at the step — and their logs part.
      final live = run();
      expect(live.log, containsAll(<String>['3:fire', '4:heat', '8:fire']));
      expect(live.log, isNot(contains('4:fire')));
      // After the reorder "wind" ties ahead of "heat".
      final at9 = live.log.where((e) => e.startsWith('9:')).toList();
      expect(at9, <String>['9:wind', '9:heat', '9:fire']);
      expect(live.journal, hasLength(3));

      // Through JSON, as a run file carries it.
      final written = <LoopChange>[
        for (final change in live.journal) LoopChange.fromJson(change.toJson()),
      ];
      final replayed = run(replay: written);
      expect(replayed.log, live.log);
      expect(
        replayed.journal.map((c) => c.toJson()),
        live.journal.map((c) => c.toJson()),
      );
    });

    test('loop changes survive a trip through JSON', () {
      for (final change in <LoopChange>[
        const LoopTimeScale(step: 4, scale: 0.25),
        const LoopStepRate(step: 9, rate: 120.0),
        const LoopPluginChange(
          PluginEnabled(step: 2, plugin: 'fire', affectsSimulation: true),
        ),
      ]) {
        expect(LoopChange.fromJson(change.toJson()).toJson(), change.toJson());
      }
      expect(
        () => LoopChange.fromJson(<String, Object?>{'kind': 'warp', 'step': 0}),
        throwsA(isA<LoopChangeFormatException>()),
      );
    });
  });

  group('the origin', () {
    const far = WorldPosition(100, 0, 0);
    const dt = 1.0 / 60.0;

    test('a rewind across a shift moves back what the hooks hold, and says '
        'so', () {
      // Mutation: read the origin back without calling the hooks or
      // publishing — the loop is at the old origin, the particles and the
      // view are still at the new one.
      final loop = EngineLoop(input: InputState())..keep(window: 10);
      var particles = 0.0;
      loop.onOriginShift((shift) => particles -= shift.offset.x);
      final heard = <OriginShifted>[];
      loop.events.onFrame<OriginShifted>('view', (d) => heard.add(d.event));
      loop.addSystem('drift', LoopPhase.rules, (c) {
        if (c.step == 1) loop.shiftOrigin(far);
      });
      for (var i = 0; i < 3; i++) {
        loop.frame(dt);
      }
      expect(loop.origin, far);
      expect(particles, -100.0);
      expect(heard.map((e) => e.to), <WorldPosition>[far]);

      loop.rewindTo(0);
      loop.frame(0.0);
      expect(loop.origin, WorldPosition.origin);
      expect(particles, 0.0);
      expect(heard.map((e) => e.to), <WorldPosition>[
        far,
        WorldPosition.origin,
      ]);
    });

    test('a checked step that shifts moves the hooks once, and the view '
        'hears it once', () {
      // The double-step check restores between its two runs. Mutation: no
      // hooks on that restore — the particles move by the shift twice.
      final loop = EngineLoop(
        input: InputState(),
        determinismCheck: DeterminismCheck(),
      );
      loop.world.spawn();
      var particles = 0.0;
      loop.onOriginShift((shift) => particles -= shift.offset.x);
      final heard = <OriginShifted>[];
      loop.events.onFrame<OriginShifted>('view', (d) => heard.add(d.event));
      loop.addSystem('drift', LoopPhase.rules, (c) {
        if (c.step == 0) loop.shiftOrigin(far);
      });
      loop.frame(dt);
      expect(loop.checksDeterminism, isTrue);
      expect(particles, -100.0);
      expect(heard, hasLength(1));
    });
  });
}
