/// The crypt on the run's physics: the core by default, the Dart reference
/// when the build asks for it — and the ragdolls only where there is a core.
///
///     flutter test test/physics_backend_test.dart
///     flutter test --dart-define=FLUTTER3D_PHYSICS=dart test/physics_backend_test.dart
library;

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_dungeon/src/ragdoll_corpses.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/sample.dart' hide Staged, stage;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
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

Future<LevelReady> _crypt() async {
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
  return (run.state as RunPlaying<LevelReady>).level;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('by default the cistern walks on the core, corpses and all', () async {
    await startPhysics(asked: 'native');
    final level = await _crypt();
    expect(level.loaded.collision.characterMover, isA<NativeCharacterMover>());
    expect(level.loaded.collision.rays, isA<NativeWorldRays>());
    expect(level.actorVisuals.corpses, isA<RagdollCorpses>());
  });

  test(
    'on the reference it walks on Dart, and the dead keep their clips',
    () async {
      // Mutation: the ragdolls made whatever the backend, which on the
      // reference is a core nobody chose.
      await startPhysics(asked: 'dart');
      final level = await _crypt();
      expect(level.loaded.collision.characterMover, isNull);
      expect(level.loaded.collision.rays, isNull);
      expect(level.actorVisuals.corpses, isNull);
      // A run recorded here says so, and replays on it.
      expect(PhysicsBackend.current.name, 'dart');
    },
  );
}
