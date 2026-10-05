/// The crypt's monsters fall as bodies — N1.
///
///     flutter test test/ragdoll_corpses_test.dart
///
/// The crypt opened the way the game opens it, every monster in it dead at
/// once: each runner's skeleton goes limp into the physics core and lies
/// down on the floor the collision world has, whole and still; the shooters
/// and the tanks, rigs of four joints the ragdoll profile does not name, keep
/// their death clips. Through `DungeonRun.open`, so what is tested is the
/// game's own assembly and not a copy of it.
library;

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_demo_dungeon/src/monster_looks.dart';
import 'package:flutter3d_demo_dungeon/src/ragdoll_corpses.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/sample.dart' hide Staged, stage;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// The model the dungeon draws [actor] with, which says its kind.
String? _modelOf(Actor actor) => const DungeonMonsters().modelFor(actor);

/// Saves kept in a map: nothing here saves.
final class _Storage implements Storage {
  final Map<String, String> _documents = <String, String>{};

  @override
  String? read(String name) => _documents[name];

  @override
  bool write(String name, String contents) {
    _documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => _documents.remove(name);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('in the crypt every runner falls as a body and lies still, and the '
      'rest keep their death clips', () async {
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
    final level = await run.open('assets/levels/crypt.json');
    addTearDown(() => run.close(level));
    final visuals = level.actorVisuals;
    await visuals.settled;
    final corpses = visuals.corpses! as RagdollCorpses;
    for (var i = 0; i < 10; i++) {
      visuals
        ..animate(1.0 / 60.0)
        ..sync();
    }

    final monsters = <Actor>[
      for (final actor in level.staged.actors.actors)
        if (_modelOf(actor) != null) actor,
    ];
    final runners = <Actor>[
      for (final actor in monsters)
        if (_modelOf(actor)!.contains('runner')) actor,
    ];
    expect(runners, isNotEmpty, reason: 'the crypt has runners');
    expect(monsters.length, greaterThan(runners.length), reason: 'and others');

    for (final actor in monsters) {
      actor.health!.damage(1e6);
    }
    level.staged.actors.syncCorpses();
    visuals.animate(1.0 / 60.0);
    // Where each runner's feet stood when it died: the floor under it.
    final floors = <Actor, double>{};
    for (final actor in monsters) {
      final ragdoll = corpses.ragdollOf(actor);
      if (!runners.contains(actor)) {
        expect(ragdoll, isNull, reason: 'a four-joint rig keeps its clip');
        continue;
      }
      expect(ragdoll, isNotNull, reason: 'a runner falls as a body');
      floors[actor] = ragdoll!.skeleton.joints
          .firstWhere((j) => j.name == 'Foot.L')
          .worldMatrix
          .getTranslation()
          .y;
    }
    expect(corpses.count, runners.length);

    bool settled() =>
        runners.every((a) => corpses.ragdollOf(a)!.ragdoll.isAsleep);
    var frames = 0;
    while (!settled() && frames < 900) {
      visuals
        ..animate(1.0 / 60.0)
        ..sync();
      frames++;
    }
    expect(settled(), isTrue, reason: 'still after $frames frames');
    for (final actor in runners) {
      final ragdoll = corpses.ragdollOf(actor)!;
      final head = ragdoll.skeleton.joints.firstWhere((j) => j.name == 'Head');
      // Lying: its head within half a metre of the floor it stood on.
      expect(
        head.worldMatrix.getTranslation().y - floors[actor]!,
        lessThan(0.5),
      );
      // Its bodies on the floor and not in it.
      for (final j in ragdoll.skeleton.joints) {
        if (ragdoll.bodyNamed(j.name!) == null) continue;
        expect(
          j.worldMatrix.getTranslation().y,
          greaterThan(floors[actor]! - 0.05),
          reason: j.name,
        );
      }
    }
  });
}
