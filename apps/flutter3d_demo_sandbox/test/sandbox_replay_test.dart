/// The sandbox recorded and played back: a walk and a dig written down
/// through the loop, kept as a run file, and replayed from its start to the
/// same checkpoints and the same events.
///
///     flutter test test/sandbox_replay_test.dart
///
/// Blocks only, on the Dart reference: the elements need a device, and the
/// claim here is about the state a step reads and the restore that puts it
/// back.
library;

import 'package:flutter3d_app/flutter3d_app.dart' show Storage;
import 'package:flutter3d_demo_sandbox/src/runs.dart';
import 'package:flutter3d_demo_sandbox/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show DemoFile;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

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

void main() {
  test('a kept run replays to every checkpoint, and puts a dig back', () async {
    final run = SandboxRun(
      VoxelWorld(
        chunksX: 4,
        chunksY: 1,
        chunksZ: 4,
        terrain: const VoxelTerrain.flat(4),
      ),
      backend: const DartPhysics(),
      at: Vector3(20.5, 4.95, 20.5),
    );
    final input = InputState();
    final loop = EngineLoop(input: input);
    run.install(loop, input);
    final runs = SandboxRuns(
      loop: loop,
      run: run,
      file: DemoFile(appName: 'sandbox_test', storage: _Memory()),
    )..begin();

    // Down onto the ground, a few steps forward, then a look at the floor
    // and a dig.
    loop.runSteps(40);
    input.press(GameAction.moveForward);
    loop.runSteps(30);
    input.release(GameAction.moveForward);
    // The look is input too: a turn made on the walk itself would be in no
    // tape.
    input
      ..addLook(0.0, 1.4 / run.walk.lookSpeed)
      ..press(SandboxActions.dig)
      ..release(SandboxActions.dig);
    loop.runSteps(30);
    final edits = run.blocks.editCount;
    expect(edits, greaterThan(0));
    final at = run.walk.body.position.clone();

    final kept = runs.keep()!;
    expect(kept.tape.steps, 100);
    expect(kept.events, isNotNull);
    expect(kept.poses, isNotNull);

    final replay = (await runs.replay())!;
    expect(replay.steps, 100);
    expect(replay.divergence, isNull);
    expect(replay.eventDivergence, isNull);
    expect(run.blocks.editCount, edits);
    expect(run.walk.body.position.distanceTo(at), lessThan(1e-9));
  });
}
