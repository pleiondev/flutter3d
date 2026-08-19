import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter3d_shooter/flutter3d_shooter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
  });

  final LoadedLevel loaded;
  final Staged staged;
  final ActorVisuals actorVisuals;
  final FixtureVisuals fixtureVisuals;
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
    required this.loader,
    required this.openScene,
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

  /// Reads the document and builds the scene. A function rather than the class
  /// so a test can hand over a device of its own.
  final Future<LoadedLevel> Function(String asset, EntityRegistry registry)
      loader;

  /// Builds what draws, once there is a scene to build it in.
  final ({ActorVisuals actors, FixtureVisuals fixtures}) Function(
    LoadedLevel loaded,
  ) openScene;

  final double eyeOffset;
  final double lookSensitivity;

  @override
  Future<LevelReady> open(String asset) async {
    final loaded = await loader(asset, registry);
    final scene = openScene(loaded);
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
    );
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
}
