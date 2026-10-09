import 'dart:typed_data';

import 'package:flutter/widgets.dart' show WidgetBuilder;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_demo_content/crypt.dart';
import 'package:flutter3d_demo_content/shooter_sample.dart';
import 'package:flutter3d_game/flutter3d_game.dart'; // RunSession, RunStatus
import 'package:flutter3d_game_physics/ragdoll.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativeDynamics, NativePhysics, NativeWorld, preparePhysics, usePhysics;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'depths.dart';
import 'exit_door.dart';
import 'fixture_looks.dart';
import 'game_posts.dart';
import 'layers.dart';
import 'monster_graphs.dart';
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
    this.crypt,
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

  /// The fire, the water and the loose wood, in the run — see [CryptWorld].
  /// Null on the Dart reference, which has no core to burn or flood with.
  final CryptWorld? crypt;
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
    this.published,
  });

  /// What the simulation last published — `() => loop.published` — which
  /// the monsters are drawn from: where each stands, which way it faces,
  /// whether it lives. Null draws them from the actors themselves, as a test
  /// with no loop does.
  final PublishedState Function()? published;

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

  /// The seed the depths begin at, so each level of them knows how deep it
  /// is and grows crowded as the run goes down.
  int depthsFrom = 1;

  @override
  Future<LevelReady> loadLevel(String asset) async =>
      _withCrypt(await _build(asset));

  /// [asset] built and staged — or [document], an edit of it — without the
  /// crypt's elements, which [_withCrypt] stands in: they share one world,
  /// and an edit is built while the level it replaces still plays in it.
  Future<LevelReady> _build(String asset, {Level? document}) async {
    // The run's physics: the core, which the browser fetches as WebAssembly
    // once — natively it is in the app — or the reference where it will not
    // start. Chosen once; every level after asks the same.
    await preparePhysics();
    // The depths are made, not read: a seed where an asset would be.
    final depth = Depths.seedOf(asset);
    final loaded = switch ((document, depth)) {
      (final Level edited, _) => await const LevelLoader().build(
        edited,
        device: device,
        registry: registry,
        rules: sampleRules(),
        physics: usePhysics(),
      ),
      (null, null) => await const LevelLoader().load(
        asset,
        device: device,
        registry: registry,
        rules: sampleRules(),
        physics: usePhysics(),
      ),
      (null, final int seed) => await const LevelLoader().build(
        await Depths.level(seed, first: depthsFrom),
        device: device,
        registry: registry,
        rules: sampleRules(),
        physics: usePhysics(),
      ),
    };

    // The player, once the level is staged below: the corpses ask it where
    // the killing shot came from.
    Player? shooter;
    // The monsters are walked by a graph over their own clips — see
    // [MonsterClips], the same strides a headless run of this level hangs.
    // **In the simulation's step, not on the frame**, so a footfall is a game
    // event in order with the shots and a rewind or a replay steps the same
    // strides: the clips are read here, before the first step rather than
    // whenever a model arrives on screen.
    final animations = (await MonsterClips.load()).animate(
      collision: loaded.collision,
      player: () => shooter,
    );
    final scene = (
      actors: ActorVisuals(
        loaded.scene,
        appearance: const DungeonMonsters(),
        // The monsters are animated by a graph over their own clips: idle,
        // walking into running by speed, attacking, struck, dying — and
        // turning their heads to watch the player once they have seen them.
        // Drawn in the pose the simulation's step left each monster's graph
        // in; see `animations` below.
        simulated: animations.graphOf,
        // Placed from what the step published, not from the actors: the
        // view's side of the boundary.
        published: published,
        device: device,
        // On their own layer as well as the world's, which is what lets the
        // sensor draw their silhouettes and nothing else's.
        layerMask: DungeonLayers.world | DungeonLayers.actors,
        // The dead fall as ragdolls rather than playing a death clip,
        // pushed away from the player, whose shots killed them.
        // On the reference, the death clip: a ragdoll is the core's.
        corpses: usePhysics() is NativePhysics
            ? RagdollCorpses(
                loaded.collision,
                pushedFrom: () => shooter?.body.position,
              )
            : null,
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
      dynamicsFor: dungeonDynamics,
      onFixture: scene.fixtures.add,
      eyeOffset: eyeOffset,
      lookSensitivity: lookSensitivity,
    );
    shooter = staged.player;
    // Its markers go onto the bus the game points it at, each step, beside
    // the run's own events (`_beforeStep` in `main.dart`).
    staged.actors.strides = animations;

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

  /// [level] with the crypt's fire, water and loose wood stood in after the
  /// run is, so they hang on its step and ride in its snapshot. On the core
  /// only: the reference has nothing to burn or flood with, and a run
  /// recorded there never met them.
  ///
  /// The world is put back to blank first, so whatever level was in it — a
  /// level being replaced by this one — is gone from it.
  LevelReady _withCrypt(LevelReady level) {
    if (usePhysics() is! NativePhysics) return level;
    final loaded = level.loaded;
    return LevelReady(
      loaded: loaded,
      staged: level.staged,
      actorVisuals: level.actorVisuals,
      fixtureVisuals: level.fixtureVisuals,
      widgetSurfaces: level.widgetSurfaces,
      exitModel: level.exitModel,
      // The package's own staging, the one a headless run stands too: the
      // torches' flames from the level, not from where the scene drew them.
      crypt: CryptWorld.stage(
        world: _elementsWorld,
        blank: _blankElements,
        sim: level.staged.sim,
        level: loaded.level,
        collision: loaded.collision,
        fixtures: level.staged.fixtures,
      ),
    );
  }

  // ------------------------------------------------------- live edits (HR3)

  /// An edit of the level being played, built and waiting for
  /// [installEdit], with the build it was made to replace.
  ({LevelReady edited, LevelReady replaces})? _edit;

  /// Whether the last change of level the run reported was an edit put in
  /// under it rather than a level entered: read once, by [takeEdited].
  bool _edited = false;

  /// The run as it stood when an edit was installed, carried into the edit
  /// by [replaceLevel] — taken before the crypt's world is restaged for it.
  Snapshot? _carrying;

  /// Builds [next], an edit of the level being played, without touching the
  /// run: textures, meshes, colliders and a simulation of its own, so the
  /// swap itself can be synchronous. Throws, and changes nothing, when
  /// nothing is being played, when [next] is another level, or when it does
  /// not build.
  ///
  /// **The crypt's elements are not stood in here.** They are in one world
  /// with the level still being played, which goes on stepping while this
  /// builds; [installEdit] stands them in at the swap.
  Future<void> prepareEdit(Level next) async {
    final playing = status;
    if (playing is! RunPlaying<LevelReady>) {
      throw StateError('no level is being played');
    }
    final name = playing.level.loaded.level.name;
    if (next.name != name) {
      throw StateError('the game is playing $name, not ${next.name}');
    }
    final edited = await _build(playing.asset, document: next);
    final waiting = _edit;
    if (waiting != null) disposeLevel(waiting.edited);
    _edit = (edited: edited, replaces: playing.level);
  }

  /// Swaps in what [prepareEdit] built, the run carried over: the run as it
  /// stands is written down first, then the crypt's elements are stood into
  /// the edit — which clears the world the level being replaced had them in
  /// — and the run, elements and all, is restored into it. Called inside the
  /// timeline's replay when the edit reaches the simulation.
  ///
  /// A build made for a level that has since been left is let go.
  void installEdit() {
    final edit = _edit;
    if (edit == null) return;
    _edit = null;
    if (!identical(level, edit.replaces)) {
      disposeLevel(edit.edited);
      return;
    }
    _carrying = snapshotOf(edit.replaces);
    try {
      _edited = replaceLevel(_withCrypt(edit.edited)) || _edited;
    } finally {
      _carrying = null;
    }
  }

  /// Whether the level the run now reports came in as an edit, and so is
  /// not a new level to begin a run in; true once per edit.
  bool takeEdited() {
    final edited = _edited;
    _edited = false;
    return edited;
  }

  /// The core's world the crypt's elements are in: one for the whole run,
  /// so what draws them is made once, and put back to [_blankElements]
  /// whenever a level is stood into it. Made on the first level, once the
  /// core has been chosen.
  late final NativeWorld _elementsWorld = NativeWorld();

  /// The elements' world as it was made, before anything was in it.
  late final Uint8List _blankElements = _elementsWorld.snapshot();

  /// The elements' world, for what draws it; null before the first level
  /// is open on the core.
  NativeWorld? get elementsWorld =>
      usePhysics() is NativePhysics ? _elementsWorld : null;

  /// Gives a finished level's uploads back to the device.
  ///
  /// The hook `RunSession.close`'s own doc was written for, wired up at last:
  /// the visuals let go of their nodes, meshes and models, then the doorway's
  /// model and the level's own brushes and maps go back. The level's last,
  /// because the fixtures were built on its textures and share the objects
  /// rather than copies.
  @override
  void disposeLevel(LevelReady level) {
    // The core's world, and with it the characters' mover.
    if (level.staged.sim.dynamics case final NativeDynamics native) {
      native.dispose();
    }
    level.actorVisuals.dispose();
    level.fixtureVisuals.dispose();
    level.widgetSurfaces.dispose();
    level.exitModel?.dispose();
    level.loaded.dispose(device);
  }

  @override
  RunOutcome outcomeOf(LevelReady level) => level.staged.sim.state.outcome;

  @override
  String? nextOf(LevelReady level) => level.staged.sim.nextLevel;

  @override
  Snapshot snapshotOf(LevelReady level) => _carrying ?? level.staged.sim.save();

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
/// about state management, and this game happens to use BLoC. What it adds
/// is telling [posts] what it emits, so the moments the screen reacts to are
/// the moments posted for whoever watches from outside.
final class RunCubit extends Cubit<RunStatus<LevelReady>> {
  RunCubit(this.run) : posts = GamePosts(run), super(run.status) {
    run.onChanged = (RunStatus<LevelReady> status) {
      emit(status);
      posts.changed(status);
    };
  }

  final DungeonRun run;

  /// What the run posts about itself — see [GamePosts].
  final GamePosts posts;

  Inventory get inventory => run.inventory;
  LevelReady? get level => run.level;
  bool get isOver => run.isOver;

  Future<bool> begin() => run.begin();
  Future<void> restart() => run.restart();
  Future<void> startOver() => run.startOver();
  Future<void> advance() => run.advance();

  /// Once per step, after it: what the step took off the floor is posted,
  /// then the run reads how it is going. Not called while a kill camera
  /// replays the last seconds, so a pickup taken again there is not posted
  /// twice.
  void observe() {
    posts.stepped();
    run.observe();
  }

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
