/// The strategy as a plugin: installed into an `EngineLoop`, a match stepped
/// by it, its events on the bus, and all of it withdrawn when it is switched
/// off.
///
///     flutter test test/plugin_test.dart
///
/// **The step through the loop is the step without it**, to the bit: a
/// recorded match is `Match.step` called once a step, and the plugin is the
/// same call made from the loop's physics phase. The second test holds that,
/// because every order tape this genre has written rests on it.
library;

import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'match_test.dart' show digestOf, flat, mirror;

final class _CampKind extends EntityKind {
  const _CampKind() : super('camp');
}

/// A loop with the plugin in it, and the kinds it was handed.
({EngineLoop loop, EntityKinds kinds}) _loopWith(StrategyPlugin plugin) {
  final kinds = EntityKinds();
  final loop = EngineLoop(
    input: InputState(),
    plugins: <Flutter3dPlugin>[plugin],
    registries: <PluginRegistry>[kinds],
  );
  return (loop: loop, kinds: kinds);
}

/// Two soldiers of two sides inside each other's range, nobody else: a
/// match the fight decides in a few seconds.
Match _duel() {
  final sim = StrategySimulation(random: GameRandom(3), ground: flat());
  sim
    ..add(
      StrategyUnit(position: Vector3(30.0, 0.0, 30.0), type: UnitType.soldier),
    )
    ..add(
      StrategyUnit(
        position: Vector3(33.0, 0.0, 30.0),
        type: UnitType.soldier,
        side: 1,
      ),
    );
  return Match(simulation: sim, bots: const <Bot>[]);
}

void main() {
  test('installs its step in physics, its events and the kinds it was '
      'handed', () {
    final plugin = StrategyPlugin(kinds: const <EntityKind>[_CampKind()]);
    final (:loop, :kinds) = _loopWith(plugin);

    expect(loop.systemsIn(LoopPhase.physics), <String>[
      StrategyPlugin.stepSystem,
    ]);
    // Mutation: add the step to `LoopPhase.rules`. A game's own rule in
    // rules would then run before the match moved rather than after it.
    expect(loop.systemsIn(LoopPhase.rules), isEmpty);

    final declared = <String, String>{
      for (final d in loop.events.declared) d.name: d.declaredBy,
    };
    expect(declared, containsPair(UnitFired.eventName, StrategyPlugin.id));
    expect(declared, containsPair(MatchDecided.eventName, StrategyPlugin.id));
    expect(kinds.types, <String>['camp']);
    expect(kinds.ownerOf('camp'), StrategyPlugin.id);
    expect(plugin.manifest.touches, PluginTouches.simulation);
  });

  test('steps a match to the same bits as Match.step does', () {
    final plugin = StrategyPlugin();
    final (:loop, kinds: _) = _loopWith(plugin);
    final through = mirror();
    final direct = mirror();
    plugin.simulation = through;

    loop.runSteps(600);
    for (var i = 0; i < 600; i++) {
      direct.step(loop.stepSeconds);
    }

    // Mutation: step the match twice in the system, or hand it a `dt` of
    // the frame's rather than the step's. The crowd then walks a different
    // distance per step and every recorded match parts at its first.
    expect(digestOf(through.simulation), digestOf(direct.simulation));
    expect(loop.stepSeconds, 1.0 / 60.0);
  });

  test('a loop with no match steps nothing and says nothing', () {
    final (:loop, kinds: _) = _loopWith(StrategyPlugin());
    final heard = <BusEvent>[];
    loop.events.onStep<BusEvent>('test', (e) => heard.add(e.event));

    loop.runSteps(10);

    expect(heard, isEmpty);
  });

  test('publishes each shot and the decision on the step channel', () {
    final plugin = StrategyPlugin()..simulation = _duel();
    final (:loop, kinds: _) = _loopWith(plugin);
    final fired = <UnitFired>[];
    final decided = <Delivered<MatchDecided>>[];
    loop.events
      ..onStep<UnitFired>('test.fired', (e) => fired.add(e.event))
      ..onStep<MatchDecided>('test.decided', decided.add);

    for (var i = 0; i < 6000 && !plugin.simulation!.standing.isOver; i++) {
      loop.runSteps(1);
    }
    loop.runSteps(30);

    expect(plugin.simulation!.standing.isOver, isTrue, reason: 'nobody fell');
    expect(fired, isNotEmpty);
    expect(fired.map((f) => f.side).toSet(), <int>{0, 1});
    // Mutation: publish the decision whenever the match is over rather than
    // on the step it ended. It is then heard every step after, and a
    // victory fanfare plays for as long as the screen is up.
    expect(decided, hasLength(1));
    expect(decided.single.event.winner, plugin.simulation!.standing.winner);
  });

  test('switched off, takes back its step, its events and its kinds', () {
    final plugin = StrategyPlugin(kinds: const <EntityKind>[_CampKind()]);
    final (:loop, :kinds) = _loopWith(plugin);
    final match = mirror();
    plugin.simulation = match;

    loop.plugins.disable(StrategyPlugin.id);
    final before = digestOf(match.simulation);
    loop.runSteps(30);

    // Mutation: register the step outside the host's scoped loop. It then
    // survives the switch, and the match goes on being stepped by a plugin
    // that says it is off.
    expect(loop.systemsIn(LoopPhase.physics), isEmpty);
    expect(digestOf(match.simulation), before);
    expect(
      loop.events.declared.map((d) => d.declaredBy),
      isNot(contains(StrategyPlugin.id)),
    );
    expect(kinds.types, isEmpty);
  });
}
