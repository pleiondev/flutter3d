/// A simulation in an isolate of its own, seen through the same handle as
/// one in this isolate (item 19, `tasks/1.0-arch-review.md`).
///
///     dart test test/isolate_simulation_test.dart
///
/// The loop is built in the spawned isolate by a top-level factory; what
/// comes back is published state on the wire, the events still encoded by
/// their codecs; input, named questions and rewinds go across as messages;
/// a closure is refused, and so is a browser. The mutation that would defeat
/// each test is named in it.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_sim/src/loop/isolate_link_web.dart' as web;
import 'package:test/test.dart';

/// A number that grows by one a step, and by whatever was submitted.
final class _Count {
  _Count(this.value);

  int value;

  static final ComponentCodec<_Count> codec = ComponentCodec<_Count>.of(
    id: 'test.count',
    encode: (count) => count.value,
    decode: (data, _) => data is int ? _Count(data) : null,
  );
}

/// The entity the count is on: the first one the factory spawns.
const Entity _counter = Entity.of(0, 0);

/// What the isolate builds: a loop counting steps, shifting its origin at
/// step 2 so an encoded event crosses, answering two questions by name.
SimulationSetup _counting(Object? arguments) {
  final input = InputState();
  final loop = EngineLoop(input: input);
  loop.world.components.register<_Count>(_Count.codec, published: true);
  final counter = loop.world.spawn();
  loop.world.set(counter, _Count(0));
  loop.addSystem('test.count', LoopPhase.rules, (context) {
    final count = loop.world.get<_Count>(counter)!;
    count.value += 1 + (input.tunesThisStep['test.add'] ?? 0.0).round();
    if (context.step == 2) loop.shiftOrigin(const WorldPosition(10, 0, 0));
  });
  loop.queries
    ..add('test.count', (world, _) => world.get<_Count>(counter)?.value)
    ..add(
      'test.plus',
      (world, arguments) =>
          (world.get<_Count>(counter)?.value ?? 0) + (arguments! as int),
    );
  return SimulationSetup(
    loop: loop,
    applyInput: (_, value) => input.tune('test.add', (value! as num) * 1.0),
    history: (arguments as int?) ?? 0,
  );
}

/// A factory that cannot build anything.
SimulationSetup _broken(Object? _) => throw StateError('no level here');

/// The next state [handle] publishes at [step] or later.
Future<PublishedState> _reach(SimulationHandle handle, int step) {
  if (handle.published.step >= step) {
    return Future<PublishedState>.value(handle.published);
  }
  final reached = Completer<PublishedState>();
  late final Registration listening;
  listening = handle.onPublished((state) {
    if (state.step < step || reached.isCompleted) return;
    listening.cancel();
    reached.complete(state);
  });
  return reached.future.timeout(const Duration(seconds: 10));
}

/// One step's worth of real time and a little more, so a frame owes one.
const double _oneStep = 1.0 / 60.0 + 1e-6;

void main() {
  // Every handle a test opens, let go of after it whatever it asserted.
  final opened = <IsolateSimulation>[];
  Future<IsolateSimulation> open({
    Object? arguments,
    bool ownsClock = false,
  }) async {
    final handle = await IsolateSimulation.open(
      _counting,
      arguments: arguments,
      ownsClock: ownsClock,
    );
    opened.add(handle);
    return handle;
  }

  tearDown(() async {
    for (final each in opened) {
      await each.dispose();
    }
    opened.clear();
  });

  test('publishes every step across, components and encoded events', () async {
    // Mutation: send the `PublishedState` itself rather than its wire —
    // `fromWire` is never exercised, and a state the codecs did not write
    // would cross only within one isolate group.
    final handle = await open();
    expect(handle.published.step, 0);
    expect(handle.published.read(_Count.codec, _counter)?.value, 0);
    final heard = <PublishedState>[];
    handle.onPublished(heard.add);
    for (var i = 0; i < 3; i++) {
      handle.advance(_oneStep);
    }
    final state = await _reach(handle, 3);
    expect(state.read(_Count.codec, _counter)?.value, state.step);
    expect(state.origin, const WorldPosition(10, 0, 0));
    // Each step publishes its own events: the shift made in step 2 arrives
    // once, encoded, and reads back through its codec.
    final shifted = <OriginShifted>[
      for (final published in heard)
        for (final event in published.eventsNamed(OriginShifted.eventName))
          ?event.decode(OriginShifted.codec),
    ];
    expect(shifted, hasLength(1));
    expect(shifted.single.to, const WorldPosition(10, 0, 0));
  });

  test('hands submitted input to the next step', () async {
    // Mutation: drop the `submit` message on the floor — the count grows
    // by one a step and never by the five submitted.
    final handle = await open();
    handle
      ..submit(5)
      ..advance(_oneStep);
    final state = await _reach(handle, 1);
    expect(state.read(_Count.codec, _counter)?.value, 6);
  });

  test(
    'answers a question by name, and refuses one it does not know',
    () async {
      // Mutation: answer every name with null — `test.plus` is not 41.
      final handle = await open();
      expect(await handle.ask('test.count'), 0);
      expect(await handle.ask('test.plus', arguments: 41), 41);
      await expectLater(
        handle.ask('test.missing'),
        throwsA(isA<SimulationCapabilityException>()),
      );
    },
  );

  test('refuses a closure, which does not cross', () async {
    // Mutation: run the closure on a copy of the world sent back — the
    // view would hold a world that no longer steps.
    final handle = await open();
    await expectLater(
      handle.query((world) => world.length),
      throwsA(isA<SimulationCapabilityException>()),
    );
  });

  test('rewinds to a step it kept, and refuses one it did not', () async {
    // Mutation: answer the rewind without restoring — the count asked
    // afterwards is still step 4's.
    final handle = await open(arguments: 10);
    for (var i = 0; i < 4; i++) {
      handle.advance(_oneStep);
    }
    await _reach(handle, 4);
    expect(await handle.ask('test.count'), 4);
    await handle.rewindTo(2);
    expect(await handle.ask('test.count'), 2);
    await expectLater(
      handle.rewindTo(400),
      throwsA(isA<SimulationCapabilityException>()),
    );
  });

  test('keeps its own clock unless told not to', () async {
    // Mutation: start no timer — nothing is ever published past step 0.
    final handle = await open(ownsClock: true);
    expect(handle.ownsClock, isTrue);
    expect(() => handle.advance(_oneStep), throwsStateError);
    final state = await _reach(handle, 2);
    expect(state.step, greaterThanOrEqualTo(2));
  });

  test('says what the factory threw', () async {
    // Mutation: wait for a ready that never comes — the open hangs.
    await expectLater(
      IsolateSimulation.open(_broken, ownsClock: false),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('no level here'),
        ),
      ),
    );
  });

  test('a disposed handle is asked nothing', () async {
    // Mutation: send the question to an isolate that has exited — the
    // future never completes.
    final handle = await open();
    await handle.dispose();
    await expectLater(
      handle.ask('test.count'),
      throwsA(isA<SimulationCapabilityException>()),
    );
  });

  test('one factory builds the local handle too', () async {
    // Mutation: make `local` ignore the history — the rewind is refused.
    final local = _counting(3).local();
    local.loop.runSteps(2);
    await local.rewindTo(1);
    expect(await local.ask('test.count'), 1);
    await local.dispose();
  });

  test('in a browser it refuses, and says to build it here', () async {
    // Mutation: answer a link that never opens — a game on the web waits
    // for ever instead of falling back to `local()`.
    expect(web.isolatesRun, isFalse);
    expect(IsolateSimulation.isSupported, isTrue);
    await expectLater(
      web.openIsolateLink(_counting, null, ownsClock: false),
      throwsA(
        isA<SimulationCapabilityException>().having(
          (error) => error.message,
          'message',
          contains('local()'),
        ),
      ),
    );
  });
}
