/// The crypt's monsters fall as bodies — N1.
///
///     flutter test test/ragdoll_corpses_test.dart
///
/// The crypt opened the way the game opens it, every monster in it dead at
/// once: each runner's skeleton goes limp into the physics core and lies
/// down on the floor the collision world has, whole and still; the shooters
/// and the tanks, rigs of four joints the ragdoll profile does not name, die
/// by their animation graphs into their death clips. Through `DungeonRun.open`, so what is tested is the
/// game's own assembly and not a copy of it.
library;

import 'package:flutter3d/flutter3d.dart' show FootPlantGoal, LookGoal;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_demo_dungeon/src/monster_looks.dart';
import 'package:flutter3d_demo_dungeon/src/ragdoll_corpses.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart'
    show ChaseBrain, MonsterState;
import 'package:flutter3d_game_shooter/sample.dart' hide Staged, stage;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show SkeletonRagdoll;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The model the dungeon draws [actor] with, which says its kind.
String? _modelOf(Actor actor) => const DungeonMonsters().modelFor(actor);

/// Where joint [name] of [ragdoll]'s skeleton is.
Vector3 _joint(SkeletonRagdoll ragdoll, String name) => ragdoll.skeleton.joints
    .firstWhere((j) => j.name == name)
    .worldMatrix
    .getTranslation();

/// How far apart [a] and [b] are along the floor.
double _flat(Vector3 a, Vector3 b) => Vector3(a.x - b.x, 0.0, a.z - b.z).length;

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
    // The monsters' graphs step with the simulation: here their animation
    // alone, so that no brain changes its mind while the test watches.
    final strides = level.staged.actors.strides!;
    void animate() {
      for (final actor in level.staged.actors.actors) {
        strides.strideOf(actor, 1.0 / 60.0);
      }
      visuals.animate(1.0 / 60.0);
    }

    for (var i = 0; i < 10; i++) {
      animate();
      visuals.sync();
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
    // Every modelled monster is animated by the graph its clips make, and
    // the runners, which have a head, watch with it.
    for (final actor in monsters) {
      expect(visuals.graphOf(actor), isNotNull, reason: _modelOf(actor));
    }
    for (final actor in runners) {
      expect(visuals.graphOf(actor)!.goals.whereType<LookGoal>(), hasLength(1));
      // And their feet on the floor the level has under them: the crypt's
      // is flat where they stand, so each foot finds it where the clip's
      // own floor is.
      final plant = visuals
          .graphOf(actor)!
          .goals
          .whereType<FootPlantGoal>()
          .single;
      for (final leg in plant.legs) {
        expect(leg.ground.abs(), lessThan(0.05), reason: _modelOf(actor));
        expect(leg.foot, isNotNull, reason: 'the Quaternius foot bone');
      }
    }
    // A runner that has seen the player turns its head to the player's eyes
    // over a third of a second: the goal comes in, aimed where they are.
    final watcher = runners.first;
    (watcher.brain! as ChaseBrain).state = MonsterState.chase;
    for (var i = 0; i < 30; i++) {
      animate();
    }
    final look = visuals.graphOf(watcher)!.goals.whereType<LookGoal>().single;
    expect(look.weight, 1.0);
    final eye = Vector3.zero();
    level.staged.player.eye(eye);
    final root = visuals.modelOf(watcher)!.root.worldMatrix;
    expect(
      root.transform3(look.target.clone()).distanceTo(eye),
      lessThan(1e-3),
    );

    // Shot dead the way a shot kills: through the actor system, which tells
    // the brain and makes the body a trigger.
    for (final actor in monsters) {
      level.staged.actors.hurt(actor, 1e6);
    }
    animate();
    // Where each runner's feet stood when it died: the floor under it; and
    // how far its pelvis was from the player, whose shot pushes it away.
    final floors = <Actor, double>{};
    final player = level.staged.player.body.position.clone();
    final reach = <Actor, double>{};
    final standing = <Actor, double>{};
    for (final actor in monsters) {
      final ragdoll = corpses.ragdollOf(actor);
      if (!runners.contains(actor)) {
        expect(ragdoll, isNull, reason: 'a four-joint rig keeps its clip');
        continue;
      }
      expect(ragdoll, isNotNull, reason: 'a runner falls as a body');
      reach[actor] = _flat(_joint(ragdoll!, 'Body'), player);
      standing[actor] = _joint(ragdoll, 'Head').y;
      floors[actor] = ragdoll.skeleton.joints
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
      animate();
      visuals.sync();
      frames++;
    }
    expect(settled(), isTrue, reason: 'still after $frames frames');
    // The rest died by their graphs, into the clip that ends lying down.
    for (final actor in monsters.where((a) => !runners.contains(a))) {
      expect(visuals.graphOf(actor)!.state, 'death', reason: _modelOf(actor));
    }
    // Thrown back by the shot, on the whole: a wall behind one stops it.
    final moved =
        runners
            .map(
              (a) =>
                  _flat(_joint(corpses.ragdollOf(a)!, 'Body'), player) -
                  reach[a]!,
            )
            .reduce((x, y) => x + y) /
        runners.length;
    expect(moved, greaterThan(0.2), reason: 'pushed away from the player');
    for (final actor in runners) {
      final ragdoll = corpses.ragdollOf(actor)!;
      final head = ragdoll.skeleton.joints.firstWhere((j) => j.name == 'Head');
      // Down: its head below six tenths of the height it stood at — lying,
      // or slumped against the wall the shot threw it into.
      expect(
        head.worldMatrix.getTranslation().y - floors[actor]!,
        lessThan(0.6 * (standing[actor]! - floors[actor]!)),
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
