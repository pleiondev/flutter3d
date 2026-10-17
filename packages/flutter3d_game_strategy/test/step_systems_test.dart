/// The systems a game hangs on the strategy's own moments: their order, the
/// phases they may go in, and the context they are handed.
///
///     flutter test test/step_systems_test.dart
library;

import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'match_test.dart' show flat;

const double _dt = 1.0 / 30.0;

StrategySimulation _world() =>
    StrategySimulation(random: GameRandom(1), ground: flat());

/// A match nothing decides for a while: two soldiers of two sides, far out
/// of each other's range.
StrategyMatch _standoff(StrategySimulation sim) {
  sim
    ..add(
      StrategyUnit(position: Vector3(5.0, 0.0, 5.0), type: UnitType.soldier),
    )
    ..add(
      StrategyUnit(
        position: Vector3(75.0, 0.0, 75.0),
        type: UnitType.soldier,
        side: 1,
      ),
    );
  return StrategyMatch(simulation: sim, bots: const <Bot>[]);
}

/// An event a system publishes, to see where it goes.
final class _Rang extends GameEvent {
  const _Rang();

  @override
  String get name => 'test.rang';
}

void main() {
  test('the phases run in the order the step reaches them', () {
    // Mutation: run `afterFight` before `afterMoves`, or skip a phase, and
    // the list is not this.
    final sim = _world();
    final seen = <String>[];
    for (final phase in StrategyPhases.all.reversed) {
      sim.addSystem('see ${phase.name}', phase, (LoopContext c) {
        seen.add(c.phase.name);
      });
    }
    sim.step(_dt);
    expect(seen, <String>[
      'strategy.begin',
      'strategy.afterOrders',
      'strategy.afterMoves',
      'strategy.afterFight',
      'strategy.afterProduction',
      'strategy.end',
    ]);
  });

  test('systems run in the order added, moved by after and before', () {
    // Mutation: sort by name, or ignore `before`, and the order changes.
    final sim = _world();
    final order = <String>[];
    sim
      ..addSystem('b', StrategyPhases.afterMoves, (_) => order.add('b'))
      ..addSystem('a', StrategyPhases.afterMoves, (_) => order.add('a'))
      ..addSystem(
        'first',
        StrategyPhases.afterMoves,
        (_) => order.add('first'),
        before: <String>['b'],
      )
      ..addSystem(
        'last',
        StrategyPhases.afterMoves,
        (_) => order.add('last'),
        after: <String>['a', 'not registered'],
      );
    sim.step(_dt);
    expect(order, <String>['first', 'b', 'a', 'last']);
    expect(sim.systemsIn(StrategyPhases.afterMoves), order);
  });

  test('a phase the genre does not have, and a name used twice, are '
      'refused', () {
    // Mutation: drop either check and nothing throws.
    final sim = _world();
    expect(
      () => sim.addSystem('x', LoopPhase.physics, (_) {}),
      throwsArgumentError,
    );
    sim.addSystem('x', StrategyPhases.end, (_) {});
    expect(
      () => sim.addSystem('x', StrategyPhases.begin, (_) {}),
      throwsArgumentError,
    );
  });

  test('stepped by hand through a match, a system is told the step, its dt '
      'and its phase, and publishes onto the match\'s bus', () {
    // Mutation: hand the system the loop phase, another dt, or leave the
    // simulation's bus unset by `StrategyMatch.publishTo`, and an expectation
    // fails.
    final sim = _world();
    final match = _standoff(sim);
    final bus = DirectBus();
    final heard = <String>[];
    bus.onStep<_Rang>('test', (Delivered<_Rang> d) => heard.add(d.event.name));
    match.publishTo(bus);
    final steps = <int>[];
    sim.addSystem('watch', StrategyPhases.afterFight, (LoopContext c) {
      steps.add(c.step);
      expect(c.dt, _dt);
      expect(c.phase, StrategyPhases.afterFight);
      expect(() => c.world, throwsStateError);
      c.publish(const _Rang());
    });
    match
      ..step(_dt)
      ..step(_dt);
    expect(steps, <int>[1, 2]);
    expect(heard, <String>['test.rang', 'test.rang']);
  });

  test('in a loop, a system is handed the loop\'s context with the genre\'s '
      'phase', () {
    // Mutation: hand the system the loop's own context unchanged, and its
    // phase is `physics`.
    final plugin = StrategyPlugin();
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[EntityKinds()],
      plugins: <Flutter3dPlugin>[plugin],
    );
    final sim = _world();
    plugin.simulation = _standoff(sim);
    final seen = <String>{};
    final steps = <int>[];
    sim.addSystem('watch', StrategyPhases.begin, (LoopContext c) {
      seen.add(c.phase.name);
      steps.add(c.step);
    });
    loop.runSteps(3);
    expect(seen, <String>{'strategy.begin'});
    expect(steps, hasLength(3));
  });

  test('a registration cancelled removes the system, even from inside it', () {
    // Mutation: walk the live list, or ignore the cancel, and the count is
    // not one.
    final sim = _world();
    var ran = 0;
    late final Registration once;
    once = sim.addSystem('once', StrategyPhases.end, (_) {
      ran++;
      once.cancel();
    });
    sim
      ..step(_dt)
      ..step(_dt);
    expect(ran, 1);
    expect(sim.systemsIn(StrategyPhases.end), isEmpty);
  });
}
