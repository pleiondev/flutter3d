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

import 'package:flutter3d_app/flutter3d_app.dart' show Storage;
import 'package:flutter3d_demo_sandbox/src/palette.dart';
import 'package:flutter3d_demo_sandbox/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show LevelWalk;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Storage in a map, as a browser's or a disk's would keep it.
final class _Memory implements Storage {
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

  test('a saved world opens as it was left: blocks, body, look and hand', () {
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
    expect(run.save(storage), isTrue);
    expect(run.unsaved, isFalse);

    final again = SandboxRun.open(storage, backend: const DartPhysics());
    // Mutation: opening a fresh world whatever the storage holds.
    expect(again.blocks.digest, run.blocks.digest);
    expect(again.blocks.editCount, 2);
    expect(again.walk.body.position, run.walk.body.position);
    expect(again.walk.yaw, run.walk.yaw);
    expect(again.walk.pitch, run.walk.pitch);
    expect(again.slot, 2);
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
  });

  test('nothing saved, or a save that will not read, is a new world', () {
    final storage = _Memory();
    final fresh = SandboxRun.fresh(backend: const DartPhysics());
    expect(
      SandboxRun.open(storage, backend: const DartPhysics()).blocks.digest,
      fresh.blocks.digest,
    );
    storage.documents[sandboxSaveName] = '{"version": 1, "world": 3}';
    Object? said;
    final opened = SandboxRun.open(
      storage,
      backend: const DartPhysics(),
      onUnread: (Object error) => said = error,
    );
    expect(opened.blocks.digest, fresh.blocks.digest);
    expect(said, isNotNull);
  });
}
