/// `DeterminismCheck`: a debug build steps each checked step twice from a
/// snapshot and names the first system whose two runs differ.
///
///     dart test test/determinism_check_test.dart
///
/// The world here is a list of integers the systems advance, captured as a
/// copy and digested by `StateDigest`, so every divergence below is one a
/// test put there on purpose. `dart test` runs with assertions on, which is
/// the only place the check arms. Each test was written by breaking what it
/// covers first; the mutation that would defeat it is named in the test.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// A world of numbers, and the three functions the check is handed.
final class _World {
  final List<int> cells = <int>[0, 0, 0];

  Object? capture() => List<int>.of(cells);

  void restore(Object? state) => cells.setAll(0, state! as List<int>);

  int digest() => StateDigest.of(cells);

  DeterminismCheck check({
    int every = 1,
    void Function(StepDivergence divergence)? onDivergence,
  }) => DeterminismCheck(
    capture: capture,
    restore: restore,
    digest: digest,
    every: every,
    onDivergence: onDivergence,
  );
}

/// A plugin adding one system to `rules` that does [work] to the world.
final class _Rule extends Flutter3dPlugin {
  _Rule(this.id, this.work);

  final String id;
  final void Function(LoopContext context) work;

  @override
  PluginManifest get manifest =>
      PluginManifest(id: id, apiVersion: PluginApiVersion.current);

  @override
  void install(PluginHost host) =>
      host.loop.addSystem('$id.step', LoopPhase.rules, work);
}

final class _Spark extends BusEvent {
  const _Spark(this.at);

  final int at;

  static final EventCodec<_Spark> codec = EventCodec<_Spark>.of(
    encode: (event) => event.at,
    decode: (data, _) => data is int ? _Spark(data) : null,
  );

  @override
  String get name => 'test.spark';

  @override
  void digestInto(EventDigestSink sink) => sink.add(at);
}

void main() {
  test('a step that reads only its world passes, and is run twice', () {
    // Mutation: run the step once and compare nothing. `calls` counts one
    // a step instead of two, and a broken step would pass unseen.
    final world = _World();
    var calls = 0;
    final found = <StepDivergence>[];
    final loop =
        EngineLoop(
          input: InputState(),
          determinismCheck: world.check(onDivergence: found.add),
        )..addSystem('grow', LoopPhase.physics, (c) {
          calls++;
          world.cells[0] += c.step + 1;
        });
    expect(loop.checksDeterminism, isTrue);
    loop.runSteps(10);
    expect(found, isEmpty);
    expect(calls, 20, reason: 'every checked step runs its systems twice');
    expect(world.cells[0], 55, reason: 'the second run is the one that stays');
  });

  test('a plugin reading state outside the snapshot is named, with its id', () {
    // Mutation: compare only the digest at the end of the step. The step
    // differs and nobody can say whose system made it differ.
    final world = _World();
    var outside = 0; // stands in for a clock: read, and never put back
    final found = <StepDivergence>[];
    final loop = EngineLoop(
      input: InputState(),
      determinismCheck: world.check(onDivergence: found.add),
      plugins: <Flutter3dPlugin>[
        _Rule('steady', (_) => world.cells[1] += 1),
        _Rule('clocked', (_) => world.cells[2] = ++outside),
      ],
    )..addSystem('before', LoopPhase.physics, (_) => world.cells[0] += 2);
    loop.runSteps(1);
    expect(found, hasLength(1));
    final divergence = found.single;
    expect(divergence.step, 0);
    expect(divergence.system, 'clocked.step');
    expect(divergence.owner, 'clocked');
    expect(divergence.phase, LoopPhase.rules);
    expect(divergence.reason, contains('plugin "clocked"'));
  });

  test("the application's own system is named as the application's", () {
    // Mutation: name the owner from the first plugin installed. A system
    // the application added would be blamed on somebody else.
    final world = _World();
    var outside = 0;
    final found = <StepDivergence>[];
    EngineLoop(
        input: InputState(),
        determinismCheck: world.check(onDivergence: found.add),
      )
      ..addSystem('drift', LoopPhase.movers, (_) => world.cells[0] = ++outside)
      ..runSteps(1);
    expect(found.single.system, 'drift');
    expect(found.single.owner, isNull);
    expect(found.single.reason, contains('the application'));
  });

  test('a snapshot that leaves state out is reported as the snapshot', () {
    // Mutation: skip the digest taken right after restoring. The system
    // writing the field `capture` forgot would be blamed instead.
    final world = _World();
    final found = <StepDivergence>[];
    final loop = EngineLoop(
      input: InputState(),
      determinismCheck: DeterminismCheck(
        // Captures the first cell only: the second is left where the first
        // run put it.
        capture: () => world.cells[0],
        restore: (state) => world.cells[0] = state! as int,
        digest: world.digest,
        onDivergence: found.add,
      ),
    )..addSystem('count', LoopPhase.rules, (_) => world.cells[1] += 1);
    loop.runSteps(1);
    expect(found.single.system, isNull);
    expect(found.single.reason, contains('capture and restore'));
  });

  test('with no handler the loop throws once the step is over', () {
    // Mutation: throw from inside the step. The step count would not move,
    // the input latches would stay open, and the next frame would run a
    // step whose start was never closed.
    final world = _World();
    var outside = 0;
    final loop = EngineLoop(
      input: InputState(),
      determinismCheck: world.check(),
    )..addSystem('drift', LoopPhase.rules, (_) => world.cells[0] = ++outside);
    expect(
      () => loop.runSteps(1),
      throwsA(
        isA<DeterminismError>().having(
          (e) => e.divergence.system,
          'system',
          'drift',
        ),
      ),
    );
    expect(loop.step, 1, reason: 'the step finished before the throw');
  });

  test('every spaces the checks out', () {
    // Mutation: ignore `every`. Every step runs twice and a game whose
    // digest is expensive cannot afford the check at all.
    final world = _World();
    final runs = <int>[];
    final loop = EngineLoop(
      input: InputState(),
      determinismCheck: world.check(every: 3),
    )..addSystem('note', LoopPhase.rules, (c) => runs.add(c.step));
    loop.runSteps(7);
    expect(runs, <int>[0, 0, 1, 2, 3, 3, 4, 5, 6, 6]);
  });

  test('a resimulated step is not checked', () {
    // Mutation: check resimulated steps too. A rollback re-stepping a
    // second ago would run every one of those steps twice more.
    final world = _World();
    var calls = 0;
    EngineLoop(input: InputState(), determinismCheck: world.check())
      ..addSystem('note', LoopPhase.rules, (_) => calls++)
      ..runSteps(4, resimulated: true);
    expect(calls, 4);
  });

  test('the frame channel shows a checked step\'s events once', () {
    // Mutation: queue the first run's events for the frame as well. Every
    // sound a checked step starts would play twice in a debug build.
    final world = _World();
    final heard = <int>[];
    final loop =
        EngineLoop(input: InputState(), determinismCheck: world.check())
          ..events.declare<_Spark>('test.spark', codec: _Spark.codec)
          ..addSystem(
            'spark',
            LoopPhase.rules,
            (c) => c.publish(_Spark(c.step)),
          );
    loop.events.onFrame<_Spark>('heard', (d) => heard.add(d.event.at));
    loop.frame(1.0 / 60.0);
    expect(heard, <int>[0]);
  });

  test('a step subscriber that publishes differently is found', () {
    // Mutation: compare only the systems' digests. Every system agrees here,
    // and the step's events still differ.
    final world = _World();
    var outside = 0;
    final found = <StepDivergence>[];
    final loop =
        EngineLoop(
            input: InputState(),
            determinismCheck: world.check(onDivergence: found.add),
          )
          ..events.declare<_Spark>('test.spark', codec: _Spark.codec)
          ..addSystem(
            'spark',
            LoopPhase.rules,
            (c) => c.publish(const _Spark(1)),
          );
    loop.events.onStep<_Spark>('echo', (d) {
      if (d.event.at == 1) loop.events.publish(_Spark(100 + ++outside));
    });
    loop.runSteps(1);
    expect(found.single.system, isNull);
    expect(found.single.reason, contains('events differ'));
  });

  test("a check left to the loop's snapshots refuses an empty world", () {
    // Mutation: let the default check run with nothing to capture. It
    // agrees with itself whatever the systems do, and a clocked system
    // passes.
    var outside = 0;
    final loop = EngineLoop(
      input: InputState(),
      determinismCheck: DeterminismCheck(),
    )..addSystem('clocked', LoopPhase.rules, (_) => outside++);
    expect(() => loop.runSteps(1), throwsStateError);
  });

  test("a check left to the loop's snapshots covers a part", () {
    // The world here is a snapshot part, so the default check — no
    // functions of its own — captures and restores it, and finds the
    // system that reads a counter outside it.
    final world = _World();
    var outside = 0;
    final found = <StepDivergence>[];
    final loop =
        EngineLoop(
            input: InputState(),
            determinismCheck: DeterminismCheck(onDivergence: found.add),
          )
          ..addSystem('steady', LoopPhase.rules, (_) => world.cells[0] += 1)
          ..addSystem(
            'clocked',
            LoopPhase.rules,
            (_) => world.cells[1] = ++outside,
          );
    loop.snapshots.add(
      SnapshotPart.of(
        id: 'test.cells',
        capture: world.capture,
        restore: (data, _) => world.restore(List<int>.of(data! as List<int>)),
      ),
    );
    loop.runSteps(1);
    expect(found.single.system, 'clocked');
  });

  test('a loop given no check steps once', () {
    // Mutation: arm the check whenever assertions are on. A loop nobody
    // asked to check would run every system twice in every test.
    var calls = 0;
    final loop = EngineLoop(input: InputState())
      ..addSystem('note', LoopPhase.rules, (_) => calls++);
    expect(loop.checksDeterminism, isFalse);
    loop.runSteps(3);
    expect(calls, 3);
  });
}
