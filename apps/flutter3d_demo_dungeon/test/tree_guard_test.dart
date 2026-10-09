/// The cistern's drain guard: a monster resting by a behaviour tree the
/// level carries, played by the game as it ships.
///
///     flutter test test/tree_guard_test.dart
library;

import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_content/shooter_sample.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Storage extends Storage {
  final Map<String, String> documents = <String, String>{};
  @override
  Future<String?> read(String name) async => documents[name];
  @override
  Future<void> write(String name, String contents) async {
    documents[name] = contents;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the drain guard walks its beat, and is seen doing it', () async {
    final it = cpuTestDevice(width: 16, height: 16);
    final run = RunCubit(
      DungeonRun(
        firstLevel: 'assets/levels/cistern.json',
        registry: sampleRegistry(),
        input: InputState(),
        inventory: startingInventory(),
        saves: SaveFile(appName: 'dungeon', storage: _Storage()),
        device: it.device,
      ),
    );
    await run.begin();
    final level = (run.state as RunPlaying<LevelReady>).level;
    final actors = level.staged.actors;
    final guard = actors.actors.firstWhere((a) => a.name == 'drain_guard');
    final animations = actors.strides! as ActorAnimations;
    expect(guard.brain, isA<TreeBrain>());

    final states = <String>{};
    var east = false;
    for (var i = 0; i < 600; i++) {
      level.staged.sim.step(1 / 60);
      states.add(animations.graphOf(guard)!.state);
      if (guard.position!.x > 3.5) east = true;
    }
    expect(east, isTrue, reason: 'it never reached the east post');
    // Mutation: a graph that knows no `patrolling` stands the guard in its
    // idle pose the whole way across.
    expect(states, contains('move'));
    // What the B key shows: who, and the path through the tree.
    expect(
      BehaviorOverlay(actors).describe(),
      contains(startsWith('drain_guard: sequence')),
    );
  });

  test(
    'the cistern\'s water mirrors the hall, and its landing is wet',
    () async {
      final it = cpuTestDevice(width: 16, height: 16);
      final run = RunCubit(
        DungeonRun(
          firstLevel: 'assets/levels/cistern.json',
          registry: sampleRegistry(),
          input: InputState(),
          inventory: startingInventory(),
          saves: SaveFile(appName: 'dungeon', storage: _Storage()),
          device: it.device,
        ),
      );
      await run.begin();
      final loaded = (run.state as RunPlaying<LevelReady>).level.loaded;
      // Mutation: a reflector entity the level format reads and nothing
      // builds — the water would stay as dark as it was.
      final mirror = loaded.reflectors.single;
      expect(mirror.surfaces, isNotEmpty);
      expect(
        mirror.surfaces.map((MeshNode n) => n.material.name).toSet(),
        <String>{'water'},
      );
      expect(loaded.wantsDecals, isTrue);
      // And the game draws both: a scan, the frame's settings being a
      // closure in a widget no test mounts.
      final main = File('lib/main.dart').readAsStringSync();
      expect(
        main,
        contains('decals: DecalSettings(enabled: loaded.wantsDecals)'),
      );
      expect(main, contains('enabled: loaded.reflectors.isNotEmpty'));
    },
  );
}
