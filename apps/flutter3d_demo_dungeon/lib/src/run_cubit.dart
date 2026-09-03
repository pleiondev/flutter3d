import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart'; // RunSession, RunStatus
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'exit_door.dart';
import 'fixture_looks.dart';
import 'layers.dart';
import 'monster_looks.dart';
import 'staging.dart';

/// A level, drawn and playable.
///
/// Holds the live objects rather than copies of their numbers: a scene, a
/// simulation and two sets of visuals are things the render loop reads sixty
/// times a second, and putting their contents in a state class would mean
/// emitting one per frame.
final class LevelReady {
  const LevelReady({
    required this.loaded,
    required this.staged,
    required this.actorVisuals,
    required this.fixtureVisuals,
    this.exitModel,
  });

  final LoadedLevel loaded;
  final Staged staged;
  final ActorVisuals actorVisuals;
  final FixtureVisuals fixtureVisuals;

  /// The doorway's uploaded model, held so `DungeonRun.close` can release it.
  /// Null when the level has no exit or the file would not read.
  final ModelAsset? exitModel;
}

/// This game's answers to the five questions a run asks.
///
/// **The sequencing is not here any more.** Starting, restarting, moving on,
/// saving, resuming — and the four rules that were each got wrong once — live
/// in `RunSession`, shared with the other two games. What is left is the part
/// only this game can answer: how a crypt is read, what "the run is over" means
/// in a shooter's words, and that keys do not travel between levels.
final class DungeonRun extends RunSession<LevelReady> {
  DungeonRun({
    required super.firstLevel,
    required super.saves,
    required this.registry,
    required this.input,
    required this.inventory,
    required this.device,
    this.eyeOffset = 0.7,
    this.lookSensitivity = 0.0022,
  });

  /// One registry validates the document and then spawns it.
  final EntityRegistry registry;

  final InputState input;

  /// What the player is carrying.
  ///
  /// **Carried across levels on purpose**: health and ammunition are what a
  /// corridor costs you, and a game that refilled both at every door is a game
  /// with no corridors in it.
  Inventory inventory;

  /// What the level is read through and what the visuals are built on.
  ///
  /// **A device rather than two callbacks, and that is a correction.** This used
  /// to take a `loader` and an `openScene` so that a test could hand over a
  /// `CpuDevice` — and the test handed over its own *assembly* along with it.
  /// The copy in `run_cubit_test.dart` left out one line, `bindLights()`, so
  /// every torch in the harness lit nothing and the harness agreed with any bug
  /// about lights the game had. That is the failure `one_assembly_test` is named
  /// after, met inside a game that the rule's own list did not reach.
  ///
  /// A device is what a test actually needs to vary. The assembly is the game's,
  /// and there is now one of it.
  final GraphicsDevice device;

  final double eyeOffset;
  final double lookSensitivity;

  @override
  Future<LevelReady> open(String asset) async {
    final loaded = await const LevelLoader().load(
      asset,
      device: device,
      registry: registry,
      rules: sampleRules(),
    );

    final scene = (
      actors: ActorVisuals(
        loaded.scene,
        appearance: const DungeonMonsters(),
        device: device,
        // On their own layer as well as the world's, which is what lets the
        // sensor draw their silhouettes and nothing else's.
        layerMask: DungeonLayers.world | DungeonLayers.actors,
      ),
      fixtures:
          FixtureVisuals(
              loaded.scene,
              loaded,
              appearance: const DungeonFixtures(),
              device: device,
            )
            // Before spawning, so a torch can find the light it drives. Held by
            // `run_cubit_test.dart`, which is where losing this line was found.
            ..bindLights(),
    );

    // The way out, which was a trigger with nothing to see. Awaited rather than
    // left running: a doorway that appears a moment after the level does is a
    // wall that turns into an exit while somebody is looking at it.
    final exitModel = await addExitsTo(
      loaded.scene,
      loaded.level,
      device: device,
    );
    final staged = stage(
      loaded.level,
      loaded.collision,
      input: input,
      registry: registry,
      inventory: inventory,
      onActorSpawned: scene.actors.add,
      onFixture: scene.fixtures.add,
      eyeOffset: eyeOffset,
      lookSensitivity: lookSensitivity,
    );
    return LevelReady(
      loaded: loaded,
      staged: staged,
      actorVisuals: scene.actors,
      fixtureVisuals: scene.fixtures,
      exitModel: exitModel,
    );
  }

  /// Gives a finished level's uploads back to the device.
  ///
  /// The hook `RunSession.close`'s own doc was written for, wired up at last:
  /// the visuals let go of their nodes, meshes and models, then the doorway's
  /// model and the level's own brushes and maps go back. The level's last,
  /// because the fixtures were built on its textures and share the objects
  /// rather than copies.
  @override
  void close(LevelReady level) {
    level.actorVisuals.dispose();
    level.fixtureVisuals.dispose();
    level.exitModel?.release(device);
    level.loaded.dispose(device);
  }

  @override
  RunOutcome outcomeOf(LevelReady level) => level.staged.sim.state.outcome;

  @override
  String? nextOf(LevelReady level) => level.staged.sim.nextLevel;

  @override
  Snapshot snapshotOf(LevelReady level) => level.staged.sim.save();

  @override
  void restoreInto(LevelReady level, Snapshot snapshot) =>
      level.staged.sim.restore(snapshot);

  /// Keys do **not** carry. A key opens one door in one place, and a player
  /// arriving at the second level already holding the third level's key is a
  /// level designer's promise broken by the plumbing.
  @override
  void carryFrom(LevelReady level, String next) => inventory.keys.clear();

  /// Rebuilt rather than emptied: a run that begins with the health you died at
  /// is not a restart.
  @override
  void startFresh() => inventory = startingInventory();
}

/// The run, as the widget tree sees it.
///
/// A wrapper and nothing more, which is the point: `RunSession` decides nothing
/// about state management, and this game happens to use BLoC.
final class RunCubit extends Cubit<RunStatus<LevelReady>> {
  RunCubit(this.run) : super(run.status) {
    run.onChanged = emit;
  }

  final DungeonRun run;

  Inventory get inventory => run.inventory;
  LevelReady? get level => run.level;
  bool get isOver => run.isOver;

  Future<bool> begin() => run.begin();
  Future<void> restart() => run.restart();
  Future<void> advance() => run.advance();
  void observe() => run.observe();
  void save() => run.save();

  @override
  Future<void> close() {
    // Unhooked before the stream closes: a load or an advance still in flight
    // finishes on the session's side, and its report would otherwise be an
    // emit into a closed cubit — a `StateError` over whatever the screen was
    // being torn down for.
    run.onChanged = null;
    return super.close();
  }
}
