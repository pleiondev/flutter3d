/// Three genres installed into one `EngineLoop`: a platformer's level with
/// a race through it and a map of armies beside it, each a plugin, none
/// knowing the others.
///
///     flutter test test/combined_genres_test.dart
///
/// **Genres can be combined** is decision 18 of `tasks/0.9-plugins.md`, and
/// it is a claim about every genre at once: their step systems, their event
/// names and their entity kinds share one engine's registries, where any two
/// claiming the same name is refused. So the test holds three of them, which
/// is why this package has the other two as dev dependencies and nothing
/// under `lib/` may reach them.
library;

import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

final class _CampKind extends EntityKind {
  const _CampKind() : super('camp');
}

/// The three genres in one loop, with the kinds they were handed.
({EngineLoop loop, EntityKinds kinds}) _combined() {
  final kinds = EntityKinds();
  final loop = EngineLoop(
    input: InputState(),
    registries: <PluginRegistry>[kinds],
    plugins: <Flutter3dPlugin>[
      PlatformerPlugin(),
      RacingPlugin(),
      StrategyPlugin(kinds: const <EntityKind>[_CampKind()]),
    ],
  );
  return (loop: loop, kinds: kinds);
}

void main() {
  test('three genres install side by side with no claim refused', () {
    // Mutation: name every genre's step system 'genre.step'. The second
    // genre's install then throws, naming the first.
    final (:loop, :kinds) = _combined();
    expect(loop.plugins.statuses.every((s) => s.enabled), isTrue);
    expect(loop.systemsIn(LoopPhase.physics), <String>[
      PlatformerPlugin.stepSystem,
      RacingPlugin.stepSystem,
      StrategyPlugin.stepSystem,
    ], reason: 'ties in a phase go to install order');

    // Mutation: declare a shared engine event (LevelSaid) from two genres.
    // The engine refuses the second declaration, and this loop is never
    // built.
    // The engine's own (the floating origin) is the application's.
    final declared = <String, String>{
      for (final d in loop.events.declared)
        if (d.declaredBy != 'app') d.name: d.declaredBy,
    };
    expect(declared.values.toSet(), <String>{
      PlatformerPlugin.id,
      RacingPlugin.id,
      StrategyPlugin.id,
    });

    // Mutation: have the platformer add the format's shared `lamp` kind.
    // Any second genre that lights its levels would then be refused.
    expect(kinds.ownerOf('camp'), StrategyPlugin.id);
    expect(
      kinds.types.where((t) => kinds.ownerOf(t) == PlatformerPlugin.id),
      isNotEmpty,
    );
  });

  test('the combined loop steps with nothing attached, and each genre '
      'switches off alone', () {
    final (:loop, :kinds) = _combined();
    // No level, no race and no match yet: every genre's step is a no-op,
    // which is what a loop built before its first level does.
    loop.runSteps(3);
    expect(loop.step, 3);

    // Mutation: cancel every plugin's registrations on one disable. The
    // race and the map would stop stepping with the platformer.
    loop.plugins.disable(PlatformerPlugin.id);
    loop.runSteps(1);
    expect(loop.systemsIn(LoopPhase.physics), <String>[
      RacingPlugin.stepSystem,
      StrategyPlugin.stepSystem,
    ]);
    expect(
      kinds.types.where((t) => kinds.ownerOf(t) == PlatformerPlugin.id),
      isEmpty,
    );
    expect(kinds.ownerOf('camp'), StrategyPlugin.id);
  });
}
