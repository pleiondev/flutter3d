/// The depths: levels past the sanctum made from their seeds as they are
/// reached, played by the game as it ships.
///
///     flutter test test/depths_test.dart
library;

import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_dungeon/src/depths.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/sample.dart' hide Staged, stage;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};
  @override
  String? read(String name) => documents[name];
  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

Future<LevelReady> _open(String asset) async {
  final it = cpuTestDevice(width: 16, height: 16);
  final run = RunCubit(
    DungeonRun(
      firstLevel: asset,
      registry: sampleRegistry(),
      input: InputState(),
      inventory: startingInventory(),
      saves: SaveFile(appName: 'dungeon', storage: _Storage()),
      device: it.device,
    ),
  );
  await run.begin();
  final status = run.state;
  if (status case RunFailed<LevelReady>(:final error)) fail('$error');
  return (status as RunPlaying<LevelReady>).level;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a level of the depths opens, its monsters spawned and the next one '
      'named', () async {
    final level = await _open(Depths.first(1));
    final document = level.loaded.level;
    expect(document.name, startsWith('The Depths'));
    // Mutation: a level built and nothing made of `perRoom`.
    expect(level.staged.actors.aliveCount, greaterThan(0));
    expect(document.next, startsWith(Depths.prefix));
    expect(document.ofType('exit'), isNotEmpty);
  });

  test(
    'the same seed is the same level, as a save that names it needs',
    () async {
      final a = await _open(Depths.first(4));
      final b = await _open(Depths.first(4));
      expect(a.loaded.level.digestHex, b.loaded.level.digestHex);
    },
  );

  test('out of the sanctum, N goes down and the ending says so', () {
    // A scan: the screen is a widget no test mounts without a window.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('LogicalKeyboardKey.keyN'));
    expect(main, contains('_run.run.load(Depths.first(_depthsSeed))'));
    expect(
      File('lib/src/ending.dart').readAsStringSync(),
      contains('to go deeper'),
    );
  });
}
