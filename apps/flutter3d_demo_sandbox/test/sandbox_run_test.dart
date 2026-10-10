/// The sandbox played headless: digging and placing by looking, the hotbar,
/// the way home, and the world saved and opened again.
///
///     flutter test test/sandbox_run_test.dart
///
/// On the Dart reference, handed in explicitly so the claims here are about
/// the game rather than the backend; `voxel_physics_test.dart` walks the
/// same blocks on whichever backend the build asked for.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart' show LightNode;
import 'package:flutter3d_app/flutter3d_app.dart' show Storage;
import 'package:flutter3d_demo_sandbox/src/palette.dart';
import 'package:flutter3d_demo_sandbox/src/staging.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show LevelWalk;
import 'package:flutter3d_game_kit/world.dart' show Daylight;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Storage in a map, as a browser's or a disk's would keep it.
final class _Memory extends Storage {
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

/// Level ground four deep, sixty-four metres square, with the body at
/// `(20.5, 20.5)` — away from the spawn in the middle.
SandboxRun _plot() => SandboxRun(
  VoxelWorld(
    chunksX: 4,
    chunksY: 1,
    chunksZ: 4,
    terrain: const VoxelTerrain.flat(4),
  ),
  backend: const DartPhysics(),
  at: Vector3(20.5, 4.95, 20.5),
);

void _settle(SandboxRun run, [int steps = 60]) {
  final input = InputState();
  for (var i = 0; i < steps; i++) {
    run.step(1 / 60, input);
    input.endStep();
  }
}

/// Turns the eye to look at [at].
void _aim(SandboxRun run, Vector3 at) {
  final to = at - run.eye;
  run.walk
    ..yaw = math.atan2(to.x, -to.z)
    ..pitch = math.atan2(to.y, math.sqrt(to.x * to.x + to.z * to.z));
}

void main() {
  test('the body lands on the ground it starts over', () {
    final run = _plot();
    _settle(run);
    expect(run.walk.body.isGrounded, isTrue);
    expect(run.walk.body.position.y, closeTo(4.9, 0.01));
  });

  test('a click digs the block looked at, and the lowest layer stays', () {
    final run = _plot();
    _settle(run);
    _aim(run, Vector3(22.5, 4.0, 20.5));
    expect(run.target, isNotNull);
    expect((run.target!.x, run.target!.y, run.target!.z), (22, 3, 20));
    expect(run.dig(), isTrue);
    expect(run.blocks.at(22, 3, 20), Voxels.empty);
    // Mutation: an edit that does not hand its chunk to the screen leaves
    // the hole drawn as ground.
    expect(run.takeStaleSurfaces(), contains((x: 1, y: 0, z: 1)));
    expect(run.unsaved, isTrue);

    // Straight down to the floor, falling a block each time; the floor
    // does not dig.
    for (var i = 0; i < 3; i++) {
      run.walk.pitch = -LevelWalk.pitchLimit;
      expect(run.dig(), isTrue);
      _settle(run, 40);
    }
    run.walk.pitch = -LevelWalk.pitchLimit;
    expect(run.target!.y, 0);
    // Mutation: digging whatever is looked at falls out of the world.
    expect(run.dig(), isFalse);
    expect(run.walk.body.position.y, closeTo(1.9, 0.01));
  });

  test('a block goes against the face looked at, and not into the body', () {
    final run = _plot();
    _settle(run);
    run.slot = hotbar.indexOf(brick);
    _aim(run, Vector3(22.5, 4.0, 20.5)); // the top of (22, 3, 20)
    expect(run.place(), isTrue);
    expect(run.blocks.at(22, 4, 20), brick);

    // Straight down at the feet: the block would go where the body is.
    run.walk.pitch = -LevelWalk.pitchLimit;
    expect(run.target!.y, 3);
    // Mutation: dropping the body check builds the block round the body.
    expect(run.place(), isFalse);
    expect(run.blocks.at(20, 4, 20), Voxels.empty);
  });

  test('the number row and the wheel pick from the hotbar', () {
    final run = _plot();
    final input = InputState()..requestSlot(3);
    run.step(1 / 60, input);
    expect(run.inHand, hotbar[3]);
    input
      ..endStep()
      ..requestSlot(hotbar.length);
    run.step(1 / 60, input);
    expect(run.slot, 3, reason: 'past the end is nothing');
  });

  test('dig and place arrive as actions in a step', () {
    final run = _plot();
    _settle(run);
    _aim(run, Vector3(22.5, 4.0, 20.5));
    final input = InputState()
      ..press(SandboxActions.dig)
      ..release(SandboxActions.dig);
    run.step(1 / 60, input);
    expect(run.blocks.at(22, 3, 20), Voxels.empty);
    input
      ..endStep()
      ..press(SandboxActions.place)
      ..release(SandboxActions.place);
    run.step(1 / 60, input);
    expect(run.blocks.at(22, 3, 20), run.inHand);
  });

  test('a pit dug under the body is no way home', () {
    final run = _plot();
    _settle(run);
    expect(run.homeReachable, isTrue);
    for (final y in <int>[3, 2]) {
      run.walk.pitch = -LevelWalk.pitchLimit;
      expect(run.dig(), isTrue);
      _settle(run, 40);
      expect(run.walk.body.position.y, closeTo(y + 0.9, 0.01));
    }
    // Mutation: asking the mesh as it was before the edits — not baking
    // again where they landed, or not asking again after them.
    expect(run.homeReachable, isFalse);
  });

  test(
    'a saved world opens as it was left: blocks, body, look and hand',
    () async {
      final storage = _Memory();
      final run = SandboxRun.fresh(backend: const DartPhysics());
      _settle(run);
      final x = run.spawn.x.floor(), z = run.spawn.z.floor();
      // The top face of column (cx, cz), whatever height the hills put it.
      Vector3 topOf(int cx, int cz) {
        var top = run.blocks.sizeY;
        while (!run.blocks.isSolid(cx, top - 1, cz)) {
          top--;
        }
        return Vector3(cx + 0.5, top.toDouble(), cz + 0.5);
      }

      _aim(run, topOf(x + 2, z));
      final dug = run.target!;
      expect(run.dig(), isTrue);
      run.slot = 2;
      _aim(run, topOf(x - 2, z));
      expect(run.place(), isTrue);
      expect(run.blocks.editCount, 2);
      expect(await run.save(storage), isTrue);
      expect(run.unsaved, isFalse);

      final again = await SandboxRun.open(
        storage,
        backend: const DartPhysics(),
      );
      // Mutation: opening a fresh world whatever the storage holds.
      expect(again.blocks.digest, run.blocks.digest);
      expect(again.blocks.editCount, 2);
      expect(again.walk.body.position, run.walk.body.position);
      expect(again.walk.yaw, run.walk.yaw);
      expect(again.walk.pitch, run.walk.pitch);
      expect(again.slot, 2);
      // Mutation: leaving the hour out of the snapshot opens every world in
      // the morning, a second of play earlier than it was left.
      expect(run.day.hour, greaterThan(Daylight.morning));
      expect(again.day.hour, run.day.hour);
      // What is kept is the seed and the edits.
      expect(storage.documents[sandboxSaveName]!.length, lessThan(600));

      // The colliders and the navigation are the saved world's, not the
      // terrain's: the dug block is a hole to the physics too.
      final down = RayHit();
      expect(
        again.physics.raycast(
          Vector3(dug.x + 0.5, 30, dug.z + 0.5),
          Vector3(0, -1, 0),
          40,
          down,
        ),
        isTrue,
      );
      expect(down.point.y, closeTo(dug.y.toDouble(), 1e-6));
      expect(again.navigation.mesh.digest, again.navigation.bakeWhole().digest);
    },
  );

  test(
    'the day turns with play, and the moon takes the shadows at night',
    () async {
      final run = _plot();
      final start = run.day.hour;
      _settle(run, 600);
      // Ten seconds of play is a fifth of one of the day's hours.
      expect(
        run.day.hour - start,
        closeTo(10.0 / Daylight.defaultSecondsPerHour, 1e-9),
      );

      final sun = LightNode(name: 'sun');
      final moon = LightNode(name: 'moon');
      Daylight(hour: 12.0).light(sun: sun, moon: moon);
      expect(Daylight(hour: 12.0).towardsSun.y, greaterThan(0.8));
      expect(sun.castsShadow, isTrue);
      expect(moon.castsShadow, isFalse);
      // Its light is the air's: whiter at noon than at the end of the day.
      final evening = LightNode(name: 'sun');
      Daylight(hour: 17.5).light(
        sun: evening,
        moon: LightNode(name: 'moon'),
      );
      expect(
        evening.color.b / evening.color.r,
        lessThan(sun.color.b / sun.color.r),
      );

      Daylight(hour: 0.0).light(sun: sun, moon: moon);
      expect(Daylight(hour: 0.0).towardsSun.y, lessThan(-0.8));
      // Mutation: a sun that asks for the shadow map whatever the hour keeps
      // it at night, cast from under the world, and the moon gets none.
      expect(sun.castsShadow, isFalse);
      expect(moon.castsShadow, isTrue);
      expect(
        sun.color.toVector3().length,
        0.0,
        reason: 'a set sun gives no light',
      );
      expect(moon.color.toVector3().length, greaterThan(0.5));
    },
  );

  test('nothing saved, or a save that will not read, is a new world', () async {
    final storage = _Memory();
    final fresh = SandboxRun.fresh(backend: const DartPhysics());
    expect(
      (await SandboxRun.open(
        storage,
        backend: const DartPhysics(),
      )).blocks.digest,
      fresh.blocks.digest,
    );
    storage.documents[sandboxSaveName] = '{"version": 1, "world": 3}';
    Object? said;
    final opened = await SandboxRun.open(
      storage,
      backend: const DartPhysics(),
      onUnread: (Object error) => said = error,
    );
    expect(opened.blocks.digest, fresh.blocks.digest);
    expect(said, isNotNull);
  });

  test('on the loop the run steps in sixtieths, phase by phase', () {
    // A frame of a thirtieth of a second is two steps of a sixtieth, each
    // what `step` does by hand, so a second of frames leaves the body where
    // sixty hand steps do, to the bit. The hands are in `input`, before the
    // walk; a dig asked for in a frame is made in that frame's step.
    //
    // Mutations: the walk handed the frame's time rather than the step's
    // (`step.dt` → `1 / 30` in `install`) — the body is not where the hand
    // steps put it; the walk in `rules` rather than `physics` — the phases
    // say so; the hands left out of `install` — the dig is never made.
    final looped = _plot();
    final byHand = _plot();
    final input = InputState();
    final loop = EngineLoop(input: input);
    looped.install(loop, input);
    expect(loop.systemsIn(LoopPhase.input), <String>['sandbox.hands']);
    expect(loop.systemsIn(LoopPhase.physics), <String>['sandbox.walk']);
    expect(loop.systemsIn(LoopPhase.fields), <String>['sandbox.elements']);
    expect(loop.systemsIn(LoopPhase.rules), <String>['sandbox.world']);

    for (var i = 0; i < 30; i++) {
      expect(loop.frame(1 / 30), 2);
    }
    _settle(byHand);
    expect(looped.walk.body.position, byHand.walk.body.position);
    expect(looped.day.hour, byHand.day.hour);

    _aim(looped, Vector3(22.5, 4.0, 20.5));
    input
      ..press(SandboxActions.dig)
      ..release(SandboxActions.dig);
    expect(loop.frame(1 / 60), 1);
    expect(looped.blocks.at(22, 3, 20), Voxels.empty);
  });
}
