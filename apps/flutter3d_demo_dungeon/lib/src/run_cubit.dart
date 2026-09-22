import 'package:flutter/widgets.dart' show WidgetBuilder;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart'; // RunSession, RunStatus

import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart' hide Staged, stage;
import 'package:flutter3d_sim/flutter3d_sim.dart';
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
    required this.widgetSurfaces,
    this.exitModel,
  });

  final LoadedLevel loaded;
  final Staged staged;
  final ActorVisuals actorVisuals;
  final FixtureVisuals fixtureVisuals;

  /// `wg-02`: every `widget_surface` entity this level named, resolved
  /// against `DungeonRun.widgetRegistry`.
  final WidgetSurfaceVisuals widgetSurfaces;

  /// The doorway's uploaded model, held so `DungeonRun.close` can release it.
  /// Null when the level has no exit or the file would not read.
  final ModelAsset? exitModel;
}

/// What a crawl has come to: what it killed, how long it took, and how much of
/// the crypt is behind it.
///
/// **The crypt could not say any of this at the end.** The last level's whole
/// reward was three seconds of `You are out.` fading over a corridor, and the
/// two numbers a shooter is played for — what you killed and how long it took —
/// were counted per level by `GameSimulation.tally` and thrown away at every
/// door. So they are counted here instead, where the run is, which is the one
/// object in this game that outlives a level change.
///
/// Mutable fields rather than a value rebuilt per step: this is added to sixty
/// times a second, and a record allocated on every one of them to hold three
/// numbers is the sort of thing `ARCHITECTURE.md` §2.4 asks not to be done.
///
/// **These are the run's, not the save's.** A crawl resumed from disk starts
/// again at nought — the save carries where the player is, not what the sitting
/// has come to — so [levels] counts levels finished *this sitting*, and the
/// screen that shows it says so.
final class Crawl {
  int kills = 0;

  /// Simulated seconds, which is what the crypt's clock is made of and is not
  /// the same as seconds of wall a slow machine spent on them.
  double seconds = 0.0;

  /// Levels this crawl has stood in. One from the moment the first is up.
  ///
  /// Counted on arrival rather than on leaving, because the last one is never
  /// left: `RunSession.carryFrom` fires only where there is a next level, so a
  /// crawl that finishes the sanctum would report four. Counted by the screen
  /// rather than here for the same kind of reason — the screen is told once per
  /// level actually put in front of the player, and a load that is overtaken by
  /// a newer one is never announced.
  int levels = 0;

  /// Monsters killed since the player was last hurt. Whatever `kills` already
  /// was for this crawl — see the note on this class for where that used to
  /// be thrown away, and is not any more — this is the half it never had:
  /// not how many, but how many *in a row*.
  int streak = 0;

  /// The longest [streak] this crawl has reached.
  int bestStreak = 0;

  /// One step's worth.
  ///
  /// [hurt] overrides [killed] rather than combining with it: a step that
  /// both lands a kill and takes a hit is a step the streak does not
  /// survive, the same way a monster's last swing landing the step its own
  /// death does still counts as having been hit. The kill is not lost from
  /// [kills] — only from what would have carried the streak forward.
  void step(double dt, {required int killed, required bool hurt}) {
    seconds += dt;
    kills += killed;
    if (hurt) {
      streak = 0;
    } else {
      streak += killed;
    }
    if (streak > bestStreak) bestStreak = streak;
  }

  void reset() {
    kills = 0;
    seconds = 0.0;
    levels = 0;
    streak = 0;
    bestStreak = 0;
  }
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
    this.widgetRegistry = const <String, WidgetBuilder>{},
    this.eyeOffset = 0.7,
    this.lookSensitivity = 0.0022,
  });

  /// One registry validates the document and then spawns it.
  final EntityRegistry registry;

  /// What a `widget_surface` entity's `widget` name resolves to — `wg-02`'s
  /// own reason this exists: a level naming `"run-terminal"` says nothing
  /// about what that widget is, on purpose, the same principle
  /// `doc/edu-00-interactive-format.md`'s `edu_annotation.widget` already
  /// settled on.
  final Map<String, WidgetBuilder> widgetRegistry;

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

    // `wg-02`: every `widget_surface` entity, resolved against
    // `widgetRegistry` — not fed through `SpawnContext` like a fixture or an
    // actor, because a live widget on a wall names no monster, no key, no
    // mover; `WidgetSurfaceVisuals.add` already answers `null` for anything
    // that is not its own entity type, so handing it the whole document is
    // exactly as cheap as handing it a filtered one.
    final widgets = WidgetSurfaceVisuals(
      loaded.scene,
      device: device,
      registry: widgetRegistry,
    );
    for (final entity in loaded.level.entities) {
      widgets.add(entity);
    }

    return LevelReady(
      loaded: loaded,
      staged: staged,
      actorVisuals: scene.actors,
      fixtureVisuals: scene.fixtures,
      widgetSurfaces: widgets,
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
    level.widgetSurfaces.dispose();
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

  /// What this crawl has come to, for the screen at the end of it.
  final Crawl crawl = Crawl();

  /// Keys do **not** carry. A key opens one door in one place, and a player
  /// arriving at the second level already holding the third level's key is a
  /// level designer's promise broken by the plumbing.
  @override
  void carryFrom(LevelReady level, String next) => inventory.keys.clear();

  /// Rebuilt rather than emptied: a run that begins with the health you died at
  /// is not a restart — and one that begins with the last run's kill count is
  /// not one either.
  @override
  void startFresh() {
    inventory = startingInventory();
    crawl.reset();
  }
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
  Future<void> startOver() => run.startOver();
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
