/// The crypt's monsters animated in the simulation's step — N1.
///
///     flutter test test/monster_animation_step_test.dart
///
/// Opened the way the game opens it: after one step every modelled monster
/// has the graph the simulation steps, drawn by the visuals rather than one
/// of their own; and a run restored from a snapshot into a level opened
/// afresh steps on to the same graphs and the same events as the run that
/// took it — the graphs made again on restore, not left to the next step.
library;

import 'dart:convert';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_demo_content/shooter_sample.dart';
import 'package:flutter3d_demo_dungeon/src/monster_looks.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

import 'heard_events.dart';

/// Saves kept in a map: nothing here saves.
final class _Storage extends Storage {
  final Map<String, String> _documents = <String, String>{};

  @override
  Future<String?> read(String name) async => _documents[name];

  @override
  Future<void> write(String name, String contents) async {
    _documents[name] = contents;
  }

  @override
  Future<void> remove(String name) async => _documents.remove(name);
}

Future<LevelReady> _open() async {
  final run = DungeonRun(
    firstLevel: 'assets/levels/crypt.json',
    registry: sampleRegistry(extra: const <EntityKind>[WidgetSurfaceKind()]),
    input: InputState(),
    inventory: startingInventory(),
    saves: SaveFile(appName: 'dungeon', storage: _Storage()),
    device: CpuDevice(
      width: 16,
      height: 9,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    ),
  );
  final level = await run.loadLevel('assets/levels/crypt.json');
  addTearDown(() => run.disposeLevel(level));
  return level;
}

/// Steps [level] [steps] times and says, each step, what the graphs hold
/// and what happened.
/// An event as the run's text says it: a marker by which and where.
String _said(GameEvent event) => switch (event) {
  AnimationMarkerPassed(:final marker, :final state) =>
    'animation marker $marker in $state',
  _ => event.name,
};

List<String> _run(LevelReady level, int steps) {
  final heard = HeardEvents.of(level.staged);
  return <String>[
    for (var i = 0; i < steps; i++)
      (() {
        level.staged.sim.step(1.0 / 60.0);
        final animations = level.staged.actors.strides! as ActorAnimations;
        // The poses too, not only what is saved: a pose made again from a
        // snapshot with last frame's goals would differ here and nowhere
        // else.
        final poses = <String>[
          for (final actor in level.staged.actors.actors)
            if (animations.graphOf(actor) case final graph?)
              '${graph.pose.translations.toList()}${graph.pose.rotations.toList()}',
        ];
        return '${jsonEncode(animations.save())} $poses '
            '${heard.take().map(_said).toList()}';
      })(),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'after a step every modelled monster has the simulation\'s graph',
    () async {
      final level = await _open();
      final animations = level.staged.actors.strides! as ActorAnimations;
      final monsters = <Actor>[
        for (final actor in level.staged.actors.actors)
          if (const DungeonMonsters().modelFor(actor) != null) actor,
      ];
      expect(monsters, isNotEmpty);
      expect(animations.graphOf(monsters.first), isNull, reason: 'not stepped');
      _run(level, 1);
      for (final actor in monsters) {
        final graph = animations.graphOf(actor);
        expect(
          graph,
          isNotNull,
          reason: const DungeonMonsters().modelFor(actor),
        );
        expect(level.actorVisuals.graphOf(actor), same(graph));
      }
    },
  );

  test('a run restored into a level opened afresh steps on the same', () async {
    final live = await _open();
    // The player put six metres from a runner, so the crypt does something:
    // a crypt where every monster stood idle would agree with itself
    // trivially. Saved as the runner sets off, so what follows is a chase
    // run, footfalls and all, then the swing it ends in.
    final runner = live.staged.actors.actors.firstWhere(
      (a) => const DungeonMonsters().modelFor(a)?.contains('runner') ?? false,
    );
    live.staged.player.body.teleport(
      runner.body!.position + Vector3(6.0, 0.0, 0.0),
    );
    _run(live, 15);
    // Through text, as a save file or a rewind buffer holds it.
    final saved = Snapshot.fromJson(
      jsonDecode(jsonEncode(live.staged.sim.save().toJson()))
          as Map<String, Object?>,
    );
    final ahead = _run(live, 120);
    expect(
      ahead.where((step) => step.contains('animation marker step')),
      isNotEmpty,
      reason: 'a monster walked, and was heard',
    );

    final again = await _open();
    again.staged.sim.restore(saved);
    final animations = again.staged.actors.strides! as ActorAnimations;
    expect(
      again.staged.actors.actors.where((a) => animations.graphOf(a) != null),
      isNotEmpty,
      reason: 'made again on restore',
    );
    expect(_run(again, 120), ahead);
  });
}
