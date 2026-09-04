import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
// `Material` exists in both flutter/material.dart and flutter3d. This file
// wants Flutter's, for the widgets; the files under `src/` that build the
// engine's do not import flutter/material.dart at all and so need no such
// dance.
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/bridge.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';
import 'src/credits.dart';
import 'src/frame_effects.dart';
import 'src/hud.dart';
import 'src/layers.dart';
import 'src/reactions.dart';
import 'src/run_cubit.dart';
import 'src/shooter_keys.dart';
import 'src/sounds.dart';
import 'src/soundtrack.dart';
import 'src/staging.dart';
import 'src/weapon_models.dart';

/// The game: five levels of a crypt, the things in them, and a run that
/// carries what the player is holding from one to the next.
///
/// Deliberately thin. Everything that could live in a package does — the
/// renderer in `flutter3d`, the clock and the input in `flutter3d_game`, the
/// level documents and their validator in `flutter3d_sim`, the shooter's rules
/// in `flutter3d_game_shooter`, the settings and the save in
/// `flutter3d_screens`, the pointer capture in `pointer_lock` — and what is
/// left here is the part that is specific to this game.
///
/// **This doc used to say "a handful of boxes, because the level format does
/// not exist yet".** It said so long after `assets/levels/crypt.json` was the
/// first thing this file loads. The README points a reader at this file as the
/// worked example, so a comment here that describes a prototype is read as the
/// engine's own account of what it can do.
///
/// What this proves, which no unit test can: that the fixed step, the captured
/// mouse and the renderer agree with each other at 60 Hz on a real device.
void main() {
  // Landscape and no system bars on a handset — see `configureForTouch`,
  // which two applications had written out and the third had not.
  configureForTouch();
  runApp(const DungeonApp());
}

class DungeonApp extends StatelessWidget {
  const DungeonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Dungeon',
      debugShowCheckedModeBanner: false,
      home: GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  /// Radians of view movement per unit of mouse motion.
  ///
  /// A setting, and settings belong to the application. `Player` takes it as a
  /// field with a default so that a game with no preferences never has to
  /// think about it.
  static const double _lookSensitivity = 0.0022;

  final InputState _input = InputState();

  /// What the player has changed, and where it is kept.
  ///
  /// **This game had neither.** No volumes, no rebinding, no way to turn
  /// anything down — the only settings it has ever had were the ones its author
  /// compiled in. The panel is shared with the platformer; what is here is the
  /// wiring and the two lists that are this game's own.
  /// **Routed to the screen, which it was not.** The seam has existed since
  /// `Storage` did and only the platformer used it: this game and the racing
  /// one left the default, which prints to a console no player can see. A
  /// settings document that will not read is a player's bindings silently
  /// reset, and a save that will not read is their run — both indistinguishable
  /// from having changed nothing.
  late final SettingsFile _settingsFile = SettingsFile(
    appName: 'dungeon',
    onIssue: _sayIssue,
  );

  void _sayIssue(String issue) {
    printIssue(issue);
    _effects.say(issue);
  }

  late final GameConfig _config;

  /// The settings screen, which is a state machine and now says so.
  late final SettingsCubit _settings;

  /// What a player can move, in the order the panel lists it.
  static const List<GameAction> _rebindable = <GameAction>[
    GameAction.moveForward,
    GameAction.moveBack,
    GameAction.moveLeft,
    GameAction.moveRight,
    GameAction.jump,
    GameAction.sprint,
    // **`fire` is not here, and it used to be.** Firing with the mouse does
    // not go through the bindings table at all — the `Listener` calls
    // `pressPointer` directly — so the row showed only whatever key or pad
    // button was bound, rebinding it left the mouse button where it was, and
    // the player ended up with two controls where the panel showed one. Until
    // `InputSource` can name a pointer button, offering the row is a promise
    // the table cannot keep.
    GameAction.use,
    // **`crouch` is here, and it never was.** The body has crouched since the
    // package was written — it shrinks, it walks slower, it refuses to stand
    // under something — and nothing on any device asked it to, so the panel
    // listing every verb a player can move was listing every verb but one.
    ShooterActions.crouch,
  ];
  late final DesktopInput _devices;
  late final PadInput _pad;
  late final GameLoop _loop;

  /// Nullable, because the device may never open.
  ///
  /// It used to be `late final`, assigned only on the success path of
  /// [_openGraphics] — and `dispose` called it unconditionally. So a player
  /// who met the renderer-failure panel, read it, and closed the screen got a
  /// `LateInitializationError` thrown over the top of the real error. The
  /// platformer met the same bug first, and this is its fix.
  Ticker? _ticker;

  /// The level, once it has loaded. Null while it is loading or if it failed.
  /// The run: which level is up, what happened to it, and where next.
  ///
  /// Built in [_openGraphics], because loading needs a device — and nullable
  /// because settings do not wait for one. [_applyConfig] runs from
  /// `initState` and again when the settings file arrives, and both can beat
  /// the device: as `late final` this field made the first of those a
  /// `LateInitializationError` on the opening frame. A config applied before
  /// there is a run is kept in [_lookScale] and reaches the player when a
  /// level is staged.
  RunCubit? _runOrNull;

  /// The run, once [_openRun] has built it. Everything behind the renderer
  /// guard in [build] may use this; anything that can fire earlier reads
  /// [_runOrNull].
  RunCubit get _run => _runOrNull!;

  /// What the render loop reads, all of it owned by [_run] now. Getters rather
  /// than fields so there is one answer to "which level is this" — seven fields
  /// assigned in one `setState` were seven chances for a load to leave one of
  /// them describing the level before.
  LevelReady? get _level => _runOrNull?.level;
  LoadedLevel? get _loaded => _level?.loaded;
  CharacterController? get _body => _level?.staged.player.body;

  /// Who the player is, once there is a body to be.
  Player? get _player => _level?.staged.player;
  GameSimulation? get _sim => _level?.staged.sim;

  /// Everything the player is carrying: health, armour, weapons, ammunition,
  /// keys and whatever power-up is running. One object rather than four fields,
  /// so a pickup has somewhere to give something to and the HUD has one thing
  /// to read — and so it can hang off the player's collider, which is how a
  /// locked door asks what the body in front of it holds.
  ///
  /// Owned by the run rather than by this screen, because it is the thing a
  /// level change must *not* reset.
  Inventory get _inventory => _run.inventory;

  /// Everything a document in this game's levels may name.
  ///
  /// Built once and shared by the loader's validator and the spawner, so the
  /// two cannot disagree about what a level is allowed to contain.
  final EntityRegistry _entityKinds = sampleRegistry();

  final ParticleSystem _particles = ParticleSystem(capacity: 3000);

  /// The weapon in the player's hands, drawn over the world.
  ///
  /// Assigned in `initState`, once there is a device to upload its models to.
  ///
  /// A field initializer used to do it, back when a mesh could reach the
  /// graphics context on its own. Nothing can now, which is the point.
  late final WeaponView _weaponView;
  ActorSystem? get _actors => _level?.staged.actors;
  ActorVisuals? get _actorVisuals => _level?.actorVisuals;

  Arsenal get _arsenal => _inventory.arsenal;
  Health get _playerHealth => _inventory.health;
  int _kills = 0;

  /// What one step's decisions turn into: particles, sounds, the flashes and
  /// the message the HUD reads. See `FrameEffects` for why this is not part
  /// of `_step`.
  final FrameEffects _effects = FrameEffects();

  final CameraNode _camera = CameraNode(name: 'player');
  late final RenderView _view;
  Renderer? _renderer;
  Object? _initError;

  /// Whether the run has ended, either way. Read by the two restarts.
  bool get _runIsOver => _run.isOver;

  /// The pad's presses, told apart from its holds.
  final PadPresses _presses = PadPresses();

  /// How far the eye sits above the centre of the player's box.
  static const double _eyeOffset = 0.7;

  final InterpolatedVector3 _smoothedPosition = InterpolatedVector3();

  /// How long since the last frame, and how long since the first.
  final FrameClock _frames = FrameClock();
  int _steps = 0;

  // Scratch vectors, reused every step. Allocating these per frame is the
  // easiest way to hand the collector work it does not need.
  final Vector3 _aim = Vector3.zero();

  /// Toggled by F, and also on its own every two seconds while
  /// [_fogAlternates] is set.
  ///
  /// The automatic half is there because three attempts at an A/B were spoiled
  /// by a synthetic keystroke not reaching the window. A measurement that
  /// depends on the window manager cooperating is not a measurement; one that
  /// depends only on the clock is.
  bool _fogOn = true;

  /// Off in normal play. Turned on for a measurement.
  static const bool _fogAlternates = bool.fromEnvironment('DUNGEON_FOG_AB');

  /// The mixer. Built with the silent backend so a build that cannot open an
  /// audio device still runs — and replaced with the real one once SoLoud is
  /// up, which is asynchronous and must not hold up the first frame.
  AudioScene _audio = AudioScene(backend: SilentBackend());
  final AudioListener _ears = AudioListener();

  /// Held so the keyboard can be given back after a click.
  ///
  /// The web build draws through a platform view, and clicking one moves the
  /// browser's focus to the canvas element — after which Flutter sees no key
  /// events and the game looks frozen while its clock keeps running.
  final FocusNode _keyboard = FocusNode(debugLabel: 'game');

  /// Mouse motion picked up from a drag, where there is no pointer to lock.
  final DragLook _dragLook = DragLook();

  /// Whether a pointer layer is the one holding [ShooterActions.fire].
  ///
  /// Tracked so a level change can let it go. The layers live inside [_game],
  /// and a load swaps the whole stack for the loading screen — so no
  /// pointer-up ever reaches a `Listener` that is gone, and a trigger held
  /// while walking through an exit stayed pressed into the next level.
  bool _pointerFiring = false;

  /// The mouse's motion — or the drag's, in a browser — plus the pad's.
  ///
  /// Where the pointer cannot be captured the delta comes from a drag instead. A
  /// first-person camera reads `lookDelta` inside the step, so the loop is the
  /// right place for it either way; and the pad **adds** to whichever of the two
  /// ran, rather than replacing it, so a player with a hand on each turns the
  /// view by the sum.
  void _drainLook(Vector2 out) {
    if (Playing.dragLook) {
      _dragLook.drainInto(out);
    } else {
      _devices.drainLook(out);
    }
    _pad.drainLook(out);
  }

  SoLoudBackend? _soloud;

  /// Held while a mover is travelling, stopped when it arrives. A one-shot
  /// would be a stone slab that grinds for exactly as long as the sample.
  /// What a step of this game sounds like. A class rather than eight calls
  /// scattered through this file: a decision can be tested, an effect inside a
  /// widget cannot.
  /// Whether the machine is keeping up, and what it cost when it was not.
  ///
  /// `FixedStep.droppedSteps` was shown here as a raw count in the debug line,
  /// which is a number nobody reads. What it means is **silent slow motion**:
  /// the loop refuses to run more than a few steps for one frame, and the time
  /// it will not run is thrown away.
  final Pace _pace = Pace();

  final Soundtrack _soundtrack = Soundtrack();

  /// What a step looks like. A class for the same reason [_soundtrack] is one.
  final Reactions _reactions = Reactions();

  MechanismWorld? get _mechanisms => _level?.staged.mechanisms;
  FixtureVisuals? get _fixtureVisuals => _level?.fixtureVisuals;

  final Vector3 _eye = Vector3.zero();
  final Vector3 _target = Vector3.zero();

  @override
  void initState() {
    super.initState();

    // Settings before devices: the bindings a player saved are the ones the
    // keyboard should read from the first key press, not from the first rebind.
    _config = _settingsFile.read();
    // **One table, and it is the config's** — see `ownedBindings`, named after
    // the bug it replaces: the ternary that used to be here handed the keyboard
    // a fresh table on a first launch, so a rebind worked until the player quit
    // and was then gone. The pad's defaults went the same way.
    _devices = DesktopInput(
      state: _input,
      bindings: ownedBindings(_config, DesktopInput.defaultBindings),
    );
    // One table for both devices, and the d-pad chooses a weapon here rather
    // than walking: this game numbers things, and a first-person player has the
    // left stick for walking already.
    _pad = PadInput(
      state: _input,
      bindings: PadInput.knowsPad(_devices.bindings)
          ? _devices.bindings
          : PadInput.addDefaultsTo(_devices.bindings),
      slotButtons: PadInput.dpadSlots,
    );
    // The genre's own, into whatever table came back — a fresh one or a saved
    // one. `fire` cannot be rebound (see [_rebindable]) so it is simply
    // written every launch; `crouch` can, so a table that already says
    // something about crouching keeps what the player said, the same way
    // `knowsPad` leaves a saved table's rebindings alone above.
    if (_devices.bindings.sourcesFor(ShooterActions.crouch).isEmpty) {
      addShooterKeysTo(_devices.bindings);
    } else {
      _devices.bindings
        ..bind(InputSource.pad(PadButton.triggerRight.id), ShooterActions.fire)
        ..bind(
          InputSource.pad(PadButton.shoulderRight.id),
          ShooterActions.fire,
        );
    }
    _loop = GameLoop(input: _input, onStep: _step, drainLook: _drainLook)
      ..recorders.add(_rewind.recorder);

    _view = RenderView(camera: _camera);

    _settings = SettingsCubit(
      config: _config,
      file: _settingsFile,
      apply: _applyConfig,
    );
    _applyConfig(_config);

    unawaited(_openGraphics());
  }

  /// Builds the device and everything that hangs off it.
  ///
  /// Asynchronous only because loading the shader bundle is, since flutter_gpu
  /// 3.47. Nothing else here waits for anything, and the order is the order it
  /// ran in when `initState` did it directly — the ticker still starts after
  /// the renderer exists, and the level still loads after the ticker.
  ///
  /// `build` is safe in the gap: it returns the panel whenever `_renderer` is
  /// null, which is exactly the state this leaves behind until it finishes, and
  /// which is also the state a failure leaves permanently.
  Future<void> _openGraphics() async {
    // The device first, because the weapon models and the fallback textures are
    // uploaded through it. A failure here is the same failure as a missing
    // shader bundle — `_renderer` stays null and `build` shows the panel — so
    // there is nothing further to set up.
    final GraphicsDevice device;
    try {
      // Which backend this is was decided at compile time by
      // `src/backend.dart`. The size is ignored by a backend that sizes itself
      // per frame, and is the canvas for one that does not.
      device = await openDevice(width: kRenderWidth, height: kRenderHeight);
    } catch (error) {
      if (mounted) setState(() => _initError = error);
      return;
    }
    if (!mounted) return;

    // Awaited before the view exists, so the player is never handed a block
    // that turns into a pistol a moment later.
    final weapons = await dungeonWeaponModels(device);
    if (!mounted) return;

    // The studio the held weapon reflects. Its own, not the crypt's — see
    // `studioEnvironment`, which says why a corridor is the wrong thing for a
    // barrel to mirror.
    final studio = studioEnvironment(device);
    _weaponView = WeaponView(
      models: weapons,
      initial: Weapons.pistol,
      environment: studio?.texture,
      environmentLevels: studio?.levels ?? 0,
    );

    // Inside `setState` because `build` is reading `_renderer` to decide
    // between the panel and the game, and by this point the first frame has
    // already been built.
    setState(() {
      try {
        _renderer = Renderer.create(device: device);
      } catch (error) {
        _initError = error;
      }
    });

    // What draws alongside the world is registered rather than passed in each
    // frame. Particles inside the scene pass so they are lit and bloomed and
    // hidden by walls; the weapon over the top of it, sharing no depth with a
    // world that would otherwise slice the barrel off in every doorway.
    _renderer
      ?..addContributor(ParticleContributor(_particles))
      ..addNode(_weaponView.plugin);

    _openRun(device);
    _ticker = createTicker(_onTick)..start();
    unawaited(_openAudio());
    unawaited(_run.begin());
  }

  /// Starts SoLoud and swaps it in behind the mixer.
  ///
  /// Failing is allowed and is not fatal: a machine with no audio device, or a
  /// CI runner, keeps the silent backend and plays the game.
  Future<void> _openAudio() async {
    // Opened by `flutter3d_audio` — see `openSpeakers` for the trap all three
    // games had written a catch for. The walls belong to the physics and the
    // mixer must not learn about them, so occlusion arrives as a function: a
    // wall between halves the sound rather than killing it, because a monster
    // you cannot hear at all is a monster that teleports.
    final speakers = await openSpeakers(
      bank: Sounds.all,
      occlusion: _occlusionBetween,
    );
    if (speakers == null) return;
    if (!mounted) {
      // The screen is gone and nothing below will adopt this backend, so it is
      // shut down here — its own doc warns that an engine left initialized
      // blocks a later open().
      unawaited(speakers.backend.dispose());
      return;
    }
    _soloud = speakers.backend;
    _audio = speakers.scene;
    _applyConfig(_config);
    _startAmbience();
  }

  /// How much of a sound survives the trip from [from] to [to].
  double _occlusionBetween(Vector3 from, Vector3 to) =>
      _soundOcclusion?.between(from, to) ?? 1.0;

  /// The walls between a sound and the ear, per level. Null until one loads.
  ///
  /// Every obstacle takes half, so a torch behind a door and a torch three
  /// rooms away are no longer the same torch — see `SoundOcclusion`. The
  /// muffle that goes with the loss reaches the backend as a low-pass, which
  /// is the "through a wall" a player recognises.
  SoundOcclusion? _soundOcclusion;

  /// The torches, which run for as long as the level does.
  ///
  /// Called from both ends of a race: the audio device and the level load in
  /// parallel and either can finish first. Whichever is second starts the
  /// ambience, and the flag keeps them from starting it twice — the first
  /// version only called this from the audio side, and since the level takes
  /// seconds longer, the torches never lit.
  void _startAmbience() {
    if (_ambienceStarted) return;
    final loaded = _loaded;
    if (loaded == null || _soloud == null) return;
    _ambienceStarted = true;
    for (final torch in loaded.level.ofType(SampleEntities.torch)) {
      _ambience.add(_audio.play(Sounds.torch, torch.position));
    }
  }

  /// Ends the level's torches, so the next level can light its own.
  ///
  /// **The latch used to be for the session, and the emitters were kept
  /// nowhere.** So a level change left the old level's loops playing forever
  /// at stale coordinates — each one costing an occlusion raycast per frame —
  /// and the new level's torches never got ambience at all, because
  /// [_startAmbience] believed its work was already done.
  void _stopAmbience() {
    for (final torch in _ambience) {
      torch.stop();
    }
    _ambience.clear();
    _ambienceStarted = false;
  }

  bool _ambienceStarted = false;

  /// What [_startAmbience] created, so [_stopAmbience] can undo it — the same
  /// bookkeeping `FrameEffects.moverVoices` keeps for the movers.
  final List<SoundEmitter> _ambience = <SoundEmitter>[];

  /// Builds the run once there is a device to load through.
  ///
  /// The loader and the scene builder are handed in rather than reached for, so
  /// that `run_cubit_test.dart` can hand over a `CpuDevice` and drive the whole
  /// chain — starting, dying, restarting, moving on, quitting and coming back —
  /// without a window.
  void _openRun(GraphicsDevice device) {
    _runOrNull = RunCubit(
      DungeonRun(
        firstLevel: _firstLevel,
        registry: _entityKinds,
        input: _input,
        inventory: startingInventory(),
        saves: SaveFile(appName: 'dungeon', onIssue: _sayIssue),
        eyeOffset: _eyeOffset,
        lookSensitivity: _lookSensitivity,
        device: device,
      ),
    );
    _demos = DemoFile(appName: 'dungeon', onIssue: _sayIssue);
  }

  /// The last run, as what the player did. See [DemoFile].
  DemoFile? _demos;

  /// Where the run being recorded started, and in which level.
  Snapshot? _demoStart;
  String? _demoLevel;

  /// Starts writing the run down, from the state the level is in now.
  ///
  /// Now rather than at load: a level resumed from a save begins mid-run, and
  /// the demo has to begin where the player did. The tape's seed is the dice
  /// the snapshot carries, which is the one number a replay cannot do without.
  void _beginDemo(String asset, LevelReady level) {
    final start = level.staged.sim.save();
    _demoStart = start;
    _demoLevel = asset;
    // A kill camera still playing when the next level arrives — a restart
    // pressed through it — is over, and the level it was replaying is gone.
    _endKillcam(restorePresent: false);
    _endRecording();
    final recorder = InputTapeRecorder(seed: start.data.integer('random'));
    _demoRecorder = recorder;
    _loop.recorders.add(recorder);
    // The last few seconds, for the kill camera: a new level has none yet, and
    // the recorder is put back if a kill camera took it out.
    _rewind.reset();
    if (!_loop.recorders.contains(_rewind.recorder)) {
      _loop.recorders.add(_rewind.recorder);
    }
  }

  /// The state the death left, kept while the last seconds play again. Null
  /// when no kill camera is playing.
  Snapshot? _killcamPresent;

  /// How far back the kill camera looks.
  static const double _killcamSeconds = 3.0;

  /// Where the kill camera stands: behind the player's aim and above it.
  static const double _killcamDistance = 2.5;
  static const double _killcamHeight = 1.0;

  /// Plays the last seconds before the death again, from outside the body.
  ///
  /// What the rewind buffer was kept for. The state three seconds before the
  /// death is restored and the tape played forward through the ordinary step
  /// — so the sounds, the flashes and the monsters happen again as they did —
  /// while the camera stands back from the player instead of behind their
  /// eyes. Three traps, each closed here:
  ///
  /// * the restored state says the game is being played, and `RunSession`
  ///   would announce a new level on seeing it; [_step] does not ask it while
  ///   this plays;
  /// * the devices write into the same input the tape does; they are muted,
  ///   and the tape lifts the mute for its own writes;
  /// * the rewind buffer would record the replay into the run's history; its
  ///   recorder is taken out, and put back when the next level begins.
  void _startKillcam() {
    final sim = _sim;
    if (sim == null || _killcamPresent != null) return;
    final point = _rewind.rewindBy(_killcamSeconds);
    if (point == null) return;
    _killcamPresent = sim.save();
    _loop.recorders.remove(_rewind.recorder);
    _input
      ..clear()
      ..muted = true;
    sim.restore(point.snapshot);
    // From the keyframe to the moment the camera starts, without drawing or
    // sounding: the step is the simulation's own, not the one with effects.
    final toPoint = InputTapePlayback(point.tapeToPoint);
    while (!toPoint.isFinished) {
      toPoint.applyTo(_input);
      _input.beginStep();
      sim.step(_loop.clock.stepSeconds);
      _input.endStep();
    }
    final player = _player;
    if (player != null) _smoothedPosition.jumpTo(player.body.position);
    _loop.playback = InputTapePlayback(point.tapeFromPoint);
  }

  /// Puts the present back once the tape has played, or drops it at once.
  void _endKillcam({required bool restorePresent}) {
    final present = _killcamPresent;
    if (present == null) return;
    _killcamPresent = null;
    _loop.playback = null;
    _input
      ..muted = false
      ..clear();
    // The death, exactly as it was: the replay lands on it by determinism
    // anyway, and restoring it is what makes that a fact rather than a hope.
    if (restorePresent) _sim?.restore(present);
  }

  /// The demo's own recorder, beside the rewind buffer's in the loop.
  InputTapeRecorder? _demoRecorder;

  /// The last ten seconds of the run, every step of them. See [RewindBuffer].
  ///
  /// Ten because that is what a death is worth looking back over; the memory
  /// is eleven snapshots of the crypt and six hundred tape entries, which the
  /// buffer's own doc puts a number on.
  final RewindBuffer _rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);

  /// Stops the demo's recorder, leaving the rewind buffer's in place.
  InputTapeRecorder? _endRecording() {
    final recorder = _demoRecorder;
    if (recorder != null) _loop.recorders.remove(recorder);
    _demoRecorder = null;
    return recorder;
  }

  /// Writes the run down when it ends, either way.
  ///
  /// Either way, because a death is the run somebody wants to send: "it shot
  /// me through the wall" is a sentence, and the demo is the proof. Written
  /// once at the end rather than as it goes, for the reason the save is: a
  /// write per step would put a file in the step budget.
  void _endDemo() {
    final recorder = _endRecording();
    final start = _demoStart;
    final level = _demoLevel;
    if (recorder == null || start == null || level == null) return;
    _demos?.write(Demo(level: level, start: start, tape: recorder.tape));
  }

  /// Everything the widget has to do when a level arrives.
  ///
  /// A listener rather than the tail of the load, because the load happens in
  /// the cubit now and these are all effects on things the cubit does not own:
  /// a smoothed camera position, an accumulator full of loading time, and a
  /// looping sound.
  void _levelArrived(LevelReady level) {
    _soundOcclusion = SoundOcclusion(level.loaded.collision);
    // The player is built by the staging, which knows the compiled-in default
    // and nothing about what this player has chosen. Applied here rather than
    // threaded through, because a setting changed mid-run has to reach the
    // level that is already up as well.
    level.staged.player
      ..lookSensitivity = _lookSensitivity * _lookScale
      ..invertLook = _lookInverted;
    _smoothedPosition.jumpTo(level.staged.player.body.position);
    // Loading blocked the ticker for a couple of seconds, and all of that time
    // is sitting in the accumulator. None of it happened in the game, so it is
    // dropped rather than simulated — otherwise the first frame spends its
    // whole budget catching up, and the dropped-step counter reads as a
    // performance problem for the rest of the session.
    _loop.clock.reset();
    // A load takes far longer than a frame and drops simulated time every time.
    // Counting that against the machine would light the warning on every level
    // of every run, which is the same as not having one.
    _pace.reset(_loop.clock.droppedSteps);
    // A fresh level makes its own noises. The soundtrack's running set and the
    // effects' mover voices both name the old level's mechanisms, and those
    // will never report `stopped` now — a mover caught mid-travel by the level
    // change was a stone slab grinding into the next level forever.
    _soundtrack.reset();
    _effects.stopVoices();
    // The old level's torches out, the new level's lit.
    _stopAmbience();
    _startAmbience();
    // **On entering a level, and on quitting, and at no other time.** This game
    // has no checkpoints — the platformer saves when its respawn point moves,
    // and there is nothing here that moves. A door is not a checkpoint: a
    // player who opens one and then dies has not earned the corridor beyond it.
    // A write per frame would put a file in the frame budget; a write only on
    // quit loses a level to a crash.
    _run.save();
    for (final issue in level.loaded.issues.followedBy(
      level.staged.navIssues,
    )) {
      debugPrint('level: $issue');
    }
  }

  @override
  void dispose() {
    // The other half of the rule above: quitting keeps the level you are in.
    // Null if the window closed before the device opened: nothing ran, so
    // there is nothing to keep.
    _runOrNull?.save();
    // Closed like [_settings], and the cubit unhooks itself from the session
    // first — see `RunCubit.close` for why the order matters.
    unawaited(_runOrNull?.close());
    _audio.stopAll();
    unawaited(_soloud?.dispose());
    unawaited(_settings.close());
    _keyboard.dispose();
    _ticker?.dispose();
    _devices.dispose();
    super.dispose();
  }

  static const String _firstLevel = 'assets/levels/crypt.json';

  /// The table this game ships with, for the panel's way back.
  ///
  /// The genre's own two go on last — see [addShooterKeysTo], and the crouch
  /// that nothing had ever bound.
  static Bindings _defaultBindings() =>
      addShooterKeysTo(PadInput.addDefaultsTo(DesktopInput.defaultBindings()));

  /// The pointer goes back and the keys are let go, before a panel is shown.
  ///
  /// The second half used to happen only as a side effect of the first, so on a
  /// build with no pointer to release a key held as the panel opened stayed
  /// held — and closing it walked the player into a wall.
  void _openSettings() {
    unawaited(_devices.release());
    _input.clear();
  }

  /// Puts the config onto everything that is playing.
  ///
  /// **One function called from one place**, which it was not: a volume change
  /// moved the mixer and nothing else, and a settings change moved the pad and
  /// the sprint toggle and not the mixer. Neither needed the other's half, and
  /// neither said so — which is how two half-applies stay correct right up
  /// until one of them grows a third thing.
  void _applyConfig(GameConfig config) {
    applySavedVolumes(config, _audio.mixer);
    _pad.applySettings(config);
    _input.setToggled(
      GameAction.sprint,
      toggled: config.settingOf('a11y.toggleSprint', 0.0) >= 0.5,
    );
    // **The most adjusted setting a first-person game has, and there was no
    // way to change it.** It was a `static const` compiled into this file; the
    // right stick had a slider and the mouse had nothing. Stored as a factor
    // rather than in radians per pixel, because that is a number somebody can
    // set by feel — and negative inverts, which is what a switch elsewhere in
    // the panel means.
    final scale = config.settingOf('mouse.look', 1.0);
    final inverted = config.settingOf('mouse.invertY', 0.0) >= 0.5;
    _lookScale = scale;
    _lookInverted = inverted;
    _player
      ?..lookSensitivity = _lookSensitivity * scale
      ..invertLook = inverted;
  }

  /// The player's own sensitivity is set when a level is staged, and a level
  /// staged after this ran would otherwise get the compiled-in default.
  double _lookScale = 1.0;
  bool _lookInverted = false;

  /// What the player has already told the operating system.
  ///
  /// **The whole of this game's accessibility settings, and deliberately.** The
  /// crypt's own panel carries volumes, bindings and a dead zone, and none of
  /// those is this: reduced motion and high contrast are answers a player has
  /// already given their system, and the answer they would rather not give
  /// twice. This doc said the panel did not exist at all, for a while after it
  /// did — see [SettingsOverlay] at the bottom of [build].
  ///
  /// Only the flashes read it. This is a first-person game and its camera has no
  /// rig to shake, so the full-screen white on every hit is the only thing here
  /// that moves without being asked to.
  Accommodations _system = const Accommodations();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _system = Accommodations.of(context);
  }

  void _onTick(Duration _) {
    // The ticker's argument is the frame's scheduled time, not the present;
    // `FrameClock` says why the wall is measured instead.
    final dt = _frames.tick();
    if (_fogAlternates) {
      final phase = (_frames.elapsed / 2.0).floor().isEven;
      if (phase != _fogOn) _fogOn = phase;
    }
    // Paused exactly when the pointer is not captured, which is what Escape
    // already does and what clicking back in already undoes. No menu, no second
    // key, and no state that can disagree with what the player sees: the
    // crosshair is gone and the cursor is back, so a game that kept simulating
    // would be a game running behind the player's back.
    // There is no pointer to own in a browser, so there the game is never
    // paused by not owning it.
    // Before the loop, so the frame that reads the pad is the frame it moves in.
    _pad.tick(dt);
    // Start restarts a finished run, and a pad button offered to a waiting
    // rebinding takes precedence over it — `PadPresses` holds both, and holds
    // the edge this game did not have on the rebinding: a controller resting
    // against something used to bind itself to whatever the panel was waiting
    // for, because the button was read as held rather than as pressed.
    if (_presses.offer(
          _pad,
          _settings,
          menuButton: PadButton.start,
          opening: _openSettings,
        ) &&
        _runIsOver &&
        _pad.heldButtons.contains(PadButton.start)) {
      unawaited(_run.restart());
    }
    // The shared gate, which this game used to write out by hand. Two things
    // came with it: the comment beside the copy still said this game had no
    // settings panel — it has had one for a while — and the copy had **no
    // `ready` clause at all**, so the loop accumulated simulated time while a
    // level was still loading and threw it away on arrival.
    // A kill camera plays whether or not the pointer is held: the player is
    // dead, and a replay that waited for a click would never start.
    _loop.paused = _killcamPresent != null
        ? _settings.state.isOpen
        : shouldPause(
            ready: _sim != null,
            menuOpen: _settings.state.isOpen,
            pointerIsTheGate: Playing.capturesPointer,
            pointerHeld: _devices.isCaptured,
            padConnected: _pad.isConnected,
          );
    _steps = _loop.advance(dt);
    _pace.note(
      dropped: _loop.clock.droppedSteps,
      dt: dt,
      stepSeconds: _loop.clock.stepSeconds,
    );
    // Once a frame, not once a step: this is display, and the simulation does
    // not care where the capsules are. **With the loop's alpha**, so a monster
    // is drawn between the two steps either side of this frame rather than
    // where the later one left it — which is what the player's own camera has
    // always done, and what every monster in the crypt was not doing.
    _actorVisuals?.sync(_loop.alpha);
    // Once a frame with the frame's own delta, not once per simulation step:
    // an animation is display, and playing it on the fixed step would make a
    // monster's stride depend on how far behind the machine is.
    _actorVisuals?.animate(dt);
    _fixtureVisuals?.sync(_frames.elapsed);
    setState(() {});
  }

  /// One step of simulated time.
  ///
  /// The order everything happens in belongs to `GameSimulation` now, along with
  /// the two claims about it that turned out to need measuring. What is left
  /// here is presentation: this reads what the step reports and turns it into
  /// noise, sparks and flashes.
  void _step(double dt) {
    final sim = _sim;
    final player = _player;
    if (sim == null || player == null) return;

    final heldBefore = _arsenal.current;
    // Before the step, so the keyframe is the state this step's recorded
    // entry acts on — the moment `RewindBuffer` and the loop agree about.
    if (_rewind.keyframeDue) _rewind.keyframe(sim.save());
    sim.step(dt);
    // The tape's last entry was consumed by the step that just ran, so this
    // is the moment the replay has arrived back at the death.
    if (_killcamPresent != null && (_loop.playback?.isFinished ?? true)) {
      _endKillcam(restorePresent: true);
    }

    // Where everything ended up, for the frame that draws between this step
    // and the next. Here rather than in the frame method because that is what
    // "per step" means, and the two are different counts on any display that
    // is not exactly 60 Hz.
    _actorVisuals?.recordStep(dt: dt);

    // A weapon can change hands inside the step — a slot key, or the last
    // round of the current one. The view model is told once, here, rather than
    // by the two places that could have caused it.
    if (!identical(_arsenal.current, heldBefore)) {
      _weaponView.selectWeapon(_arsenal.current);
    }

    final outcome = sim.usedThisStep;
    if (outcome != null) _effects.say(outcome.message);

    // **What to play is decided in `Soundtrack` and only performed here.** It
    // used to be decided here too, in eight places inside a widget, where
    // nothing could ask what a step ought to sound like without a device and a
    // window — so the game being mute was undetectable, and four weapons
    // sharing two sounds went unnoticed for as long as the game has existed.
    _effects.perform(_soundtrack.listen(sim, player), _audio);

    final mechanisms = _mechanisms;
    if (mechanisms != null) {
      for (final said in mechanisms.events.messages) {
        _effects.say(said);
      }
    }

    _effects.fade(dt);
    for (final power in _inventory.expired) {
      _effects.say('$power has run out.');
    }
    _inventory.expired.clear();

    // Scaled rather than skipped, so the day a platform reports the two apart a
    // flash can be turned down without turning the camera down with it. A
    // full-screen flash on every hit is a photosensitivity question, which is
    // not the same harm as a camera that moves by itself.
    if (sim.damageTakenThisStep > 0.0) _effects.hurt(_system.screenFlash);

    // The run's own state, republished by the cubit on the step it changes —
    // which is what makes the announcement below a listener rather than an
    // edge detector kept in a field here.
    // Not while a kill camera plays: the restored state says the game is
    // being played, and the run would announce a new level on seeing it.
    if (_killcamPresent == null) {
      _run.observe();
      // Once a level says there is somewhere to go, go. Does nothing until the
      // level is finished and nothing twice; the guard is the cubit's.
      unawaited(_run.advance());
    }

    // **What is shown is decided in `Reactions` and only performed here**, for
    // the same reason the sound is: three private methods of a widget nothing
    // can mount meant no test in this application had ever mentioned a
    // particle.
    _effects.show(
      _reactions.listen(sim, player),
      _particles,
      _system.screenFlash,
    );

    // The two that are not reactions to an event. A recoil is the weapon view's
    // own animation, and the kill count is a number the HUD shows.
    if (sim.firedThisStep != null) _weaponView.recoil();
    _kills += sim.actors?.died.length ?? 0;

    final body = player.body;
    _weaponView.step(
      dt,
      speed: math.sqrt(
        body.velocity.x * body.velocity.x + body.velocity.z * body.velocity.z,
      ),
      grounded: body.isGrounded,
    );

    _effects.burnTorches(_fixtureVisuals, _particles);
    // The frame the loop accepted — see `GameLoop.lastFrame`. This game had no
    // limit of its own at all.
    _particles.advance(_loop.lastFrame);

    // Last, so every source has already moved this step. The listener is the
    // simulated eye rather than the interpolated one: the mix should follow
    // the game's idea of where the player is, not the renderer's.
    player.eye(_eye);
    _ears.aimAt(_eye, player.yaw);
    _audio.update(_ears);

    // What the walls hide from here is left undrawn. Once a step rather than
    // once a frame: the eye moves in the step, and a frame between two steps
    // sees the same walls either one did. Through the level rather than its
    // culler, because the level knows to wait for its probes — see
    // `LoadedLevel.cull`.
    _loaded?.cull(_eye, device: _run.run.device);

    // A rocket that cut a wall this step: the walls are drawn again from the
    // brushes as they are now, the same list the collision world already
    // walks. Rare, and the whole level's batches at once — see
    // `LevelLoader.rebuildBrushes` for why not just the one.
    final breaches = sim.breaches;
    final loaded = _loaded;
    if (breaches != null &&
        loaded != null &&
        breaches.version != _breachVersion) {
      _breachVersion = breaches.version;
      const LevelLoader().rebuildBrushes(
        loaded,
        device: _run.run.device,
        brushes: breaches.brushes,
      );
    }

    _smoothedPosition.push(body.position);
  }

  @override
  Widget build(BuildContext context) {
    // **`bloc: null` does not mean "wait".** It means "find one in the tree",
    // and nothing above this ever provides a `RunCubit` — it is owned by this
    // State. So every build before the renderer started threw
    // `ProviderNotFoundException`, which is the red screen the game opened on.
    // `_run` is assigned beside the renderer, so this is also what keeps it
    // from being read before it is written.
    if (_renderer == null) return RendererFailure(error: _initError);
    return BlocConsumer<RunCubit, RunStatus<LevelReady>>(
      bloc: _run,
      // The three things that have to happen *when* the run changes rather
      // than every time it is drawn: a new level needs its camera put where
      // the player is, and an ended one needs saying out loud.
      listener: (BuildContext context, RunStatus<LevelReady> run) {
        switch (run) {
          case RunPlaying<LevelReady>(
            :final asset,
            :final level,
            outcome: RunOutcome.playing,
          ):
            _levelArrived(level);
            _beginDemo(asset, level);
          case RunPlaying<LevelReady>(outcome: RunOutcome.lost):
            // What the player is told to do has to be something they can do:
            // on a handset there is no R, and the tap layer below the touch
            // controls is the way back in.
            _effects.say(
              Playing.touch
                  ? 'You died. Tap to try again.'
                  : 'You died. Press R to try again.',
            );
            _endDemo();
            _startKillcam();
          case RunPlaying<LevelReady>(:final level, outcome: RunOutcome.won):
            final next = level.staged.sim.nextLevel;
            _effects.say(next == null ? 'You are out.' : 'Level complete.');
            _endDemo();
          case RunLoading<LevelReady>() || RunFailed<LevelReady>():
            // The pointer layers unmount with the level — see [_pointerFiring]
            // — so whatever they were holding is let go here, where the swap
            // to the loading screen is announced.
            _dragLook.end();
            if (_pointerFiring) {
              _devices.releasePointer(ShooterActions.fire);
              _pointerFiring = false;
            }
        }
      },
      builder: (BuildContext context, RunStatus<LevelReady> run) => _game(run),
    );
  }

  /// The game, once the renderer, the level and the player's body all exist.
  ///
  /// [build] returns one of the three screens in `status_screens.dart` while
  /// any of those is missing; this returns another of them for the same
  /// reason it always did — the null checks here are what promote `_renderer`,
  /// `loaded` and `body` for the rest of the method.
  Widget _game(RunStatus<LevelReady> run) {
    final renderer = _renderer;
    final loaded = _loaded;
    final body = _body;
    if (renderer == null) return RendererFailure(error: _initError);

    if (run is RunFailed<LevelReady>) {
      // **The way out, which this screen had not been given.** Of the three
      // games this is the one with a save, so a level that will not read is
      // the one dead end a player cannot walk out of: the keyboard handler
      // lives further down this method and never mounts, so no key is read,
      // and R would reload the same broken document anyway. The save that
      // names the previous level is thrown away with the run, or the next
      // launch resumes into the same corridor.
      return LevelLoadFailed(
        asset: run.asset,
        error: run.error,
        onStartOver: () => unawaited(_run.startOver()),
      );
    }

    if (loaded == null || body == null) {
      return const LoadingScreen();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _keyboard,
        autofocus: true,
        onKeyEvent: (_, KeyEvent event) {
          // The settings get the key first — the rebinding, Escape, and the
          // panel keeping the keys while it is open. See `settingsKeys` for why
          // that is the order.
          final settingsSay = settingsKeys(
            event,
            _settings,
            opening: _openSettings,
          );
          if (settingsSay != null) return settingsSay;
          // **R**, because a dead player pressing keys is looking for a way
          // back into the game rather than into a menu. This was the whole of
          // what was missing: dying printed a word and left the only exit as
          // closing the application.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyR &&
              _runIsOver) {
            unawaited(_run.restart());
            return KeyEventResult.handled;
          }
          // G toggles the fog in place. A before-and-after has to come from
          // one process at one camera position, which is exactly what the
          // measurement I threw away did not have.
          //
          // **G rather than F, which is where this used to be.** The default
          // bindings put `use` on both E *and* F, and this branch does not
          // report the key as handled — so a player who reached for F to open
          // a door opened it and turned the level's fog off at the same time,
          // and the far wall the fog exists to hide appeared and disappeared
          // with every doorway. G is bound to nothing in the table and is not
          // a weapon slot, so a measurement toggle is only ever a measurement
          // toggle.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyG) {
            setState(() => _fogOn = !_fogOn);
            return KeyEventResult.handled;
          }
          // M shows the map the run has drawn so far. The game keeps running
          // underneath, as it did in the games this one is drawn from: a map
          // that pauses the fight is a menu, and this is not one.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyM) {
            setState(() => _mapOn = !_mapOn);
            return KeyEventResult.handled;
          }
          return _devices.handleKeyEvent(event);
        },
        child: Listener(
          // Wherever the pointer can be captured, which now includes a desktop
          // browser: `Playing.capturesPointer` asks the capture backend rather
          // than a list of platforms. The pointer reaches here on the web
          // because the platform view holding the frame is `pointer-events:
          // none` — see `WebGlDevice.present`, which sets it for this reason.
          //
          // **The capture must stay inside this handler.** A browser refuses
          // `requestPointerLock` without a user gesture behind it, and this
          // press is the gesture; asking after an `await` on anything slow is
          // asking outside it.
          onPointerDown: (_) {
            _keyboard.requestFocus();
            if (!Playing.capturesPointer) return;
            if (_devices.isCaptured) {
              _devices.pressPointer(ShooterActions.fire);
              _pointerFiring = true;
            } else {
              _devices.captureMouse();
            }
          },
          onPointerUp: (_) {
            if (!Playing.capturesPointer) return;
            _devices.releasePointer(ShooterActions.fire);
            _pointerFiring = false;
          },
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              SceneSurface(
                renderer: renderer,
                scene: loaded.scene,
                view: _view,
                onBeforeFrame: _placeCamera,
                settings: () => RenderSettings(
                  // Off, and no longer for either of the reasons written here
                  // before. Rough stone stopped being the problem when the
                  // surface buffer began carrying perceptual roughness in its
                  // blue channel and `reflections.frag` started fading the
                  // march out over it. The hit test stopped being one too: it
                  // measured `thickness` in window depth, which is not a
                  // distance — a few centimetres of stone near the camera and
                  // metres across the room, so a ray passing well behind a
                  // distant wall counted as landing on it and painted a
                  // highlight through solid rock. That is fixed; the march now
                  // asks how far behind in metres. See `ReflectionSettings`.
                  //
                  // What keeps it off here is a cost rather than a defect. SSR
                  // needs the surface buffer, and attaching it turns MSAA off
                  // for the whole scene pass, so the crypt would trade the
                  // antialiasing of every edge in the frame for a wet look on
                  // the floor. That is a decision about how the crypt should
                  // look, and nothing has drawn one with it on to judge.
                  reflections: const ReflectionSettings(),
                  // Straight from the document. A crypt without fog is a crypt
                  // with a visible far wall, and the far wall is the thing an
                  // author least wants seen.
                  fog: FogSettings(
                    color: loaded.level.fogColor,
                    density: _fogOn ? loaded.level.fogDensity : 0.0,
                  ),
                  // Metered from the frame, which a crypt lit by torches is
                  // the case for: a room with a torch in view is exposed to
                  // the torchlit walls, and a corridor with none in view
                  // brightens until it can be seen, the way eyes do. The
                  // engine's default rates — a slow climb into the dark, a
                  // quick fall back into the light.
                  autoExposure: const AutoExposureSettings(enabled: true),
                  // The sensor: while the power-up lasts, whatever walks
                  // behind a wall is drawn through it as a silhouette. The
                  // actors are on their own layer for exactly this, and a
                  // mask of zero — the default — draws nothing extra.
                  xray: _inventory.hasSensor
                      ? const XraySettings(layerMask: DungeonLayers.actors)
                      : const XraySettings(),
                ),
              ),
              // Hold to fire and drag to aim, which is what a captured pointer
              // already does at once — so the two are the same gesture here
              // rather than two that fight over the button.
              //
              // **On a phone it aims and does not fire.** A finger dragging to
              // look is the same gesture as a mouse dragging to look, but a
              // mouse has a second button and a thumb does not: firing on every
              // drag would empty the weapon every time the player turned round.
              // So a touch build gets a trigger of its own, below.
              if (Playing.dragLook)
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) {
                      _keyboard.requestFocus();
                      _dragLook.begin();
                      if (!Playing.touch) {
                        _devices.pressPointer(ShooterActions.fire);
                        _pointerFiring = true;
                      }
                    },
                    onPointerMove: (PointerMoveEvent event) =>
                        _dragLook.moved(event.delta),
                    onPointerUp: (_) {
                      _dragLook.end();
                      if (!Playing.touch) {
                        _devices.releasePointer(ShooterActions.fire);
                        _pointerFiring = false;
                      }
                    },
                    onPointerCancel: (_) {
                      _dragLook.end();
                      if (!Playing.touch) {
                        _devices.releasePointer(ShooterActions.fire);
                        _pointerFiring = false;
                      }
                    },
                  ),
                ),
              // Above the drag layer, so a thumb on the stick is not also a turn
              // of the view.
              if (Playing.touch)
                TouchControls(
                  state: _input,
                  buttons: const <TouchAction>[
                    TouchAction(GameAction.use, 'use'),
                    TouchAction(ShooterActions.fire, 'fire'),
                  ],
                ),
              // Above the stick in turn, and only once the run is over: R and
              // a pad's Start were the whole of the way back in, and a phone
              // has neither. Over the stick because the stick is what a thumb
              // would land on otherwise, and a dead body does not walk.
              if (Playing.touch && _runIsOver)
                TapToRestart(onRestart: () => unawaited(_run.restart())),
              SettingsOverlay(
                settings: _settings,
                mixer: _audio.mixer,
                // Only the sliders this game's own sounds can be heard through.
                // `busesIn` reads the bank, so a soundtrack arriving one day brings
                // its slider with it and nobody has to remember.
                buses: busesIn(Sounds.all),
                bindings: _devices.bindings,
                config: _config,
                padConnected: _pad.isConnected,
                actions: _rebindable,
                defaultBindings: _defaultBindings,
                opening: _openSettings,
                // **This game had no credits screen at all**, and did not need
                // one until the monsters arrived: everything else in it is
                // generated by a script in `tool/`.
                credits: const CreditsSection(credits: Credits.models),
              ),
              Hud(
                // Nothing to capture in a browser, so nothing to prompt for.
                captured: !Playing.capturesPointer || _devices.isCaptured,
                fps: _frames.fps,
                steps: _steps,
                dropped: _loop.clock.droppedSteps,
                behind: _pace.behind,
                voices: _audio.voiceCount,
                particles: _particles.aliveCount,
                position: body.position,
                grounded: body.isGrounded,
                weapon: _arsenal.current,

                hitFlash: _effects.hitFlash,
                painFlash: _effects.painFlash,
                health: _playerHealth,
                kills: _kills,
                monstersLeft: _actors?.aliveCount ?? 0,
                message: _effects.message,
                messageOpacity: (_effects.messageFor / 0.6).clamp(0.0, 1.0),
                keys: _inventory.keys,
                armour: _playerHealth.armour,
                ammo: _arsenal.currentAmmo,
                pouches: <AmmoType, int>{
                  for (final type in AmmoType.values)
                    if (type != AmmoType.none) type: _arsenal.ammoOf(type),
                },
                powers: _inventory.powers,
              ),
              if (_mapOn && _sim?.automap != null && _player != null)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(48.0),
                    child: AutomapView(
                      automap: _sim!.automap!,
                      position: body.position,
                      yaw: _player!.yaw,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether the automap is up. See the M key.
  bool _mapOn = false;

  /// The breaches the walls were last drawn with. Reset with the level, as
  /// `Breaches.version` is.
  int _breachVersion = 0;

  /// Places the camera for the frame about to be drawn.
  ///
  /// Reads the interpolated position rather than the simulated one: on a
  /// display faster than the step rate, several frames in a row would otherwise
  /// show the same place and then jump.
  void _placeCamera() {
    final player = _player;
    if (player == null) return;

    if (_killcamPresent != null) {
      // Standing back from the body rather than behind its eyes, so the death
      // is seen rather than lived through twice. Through walls when the room
      // is small; a camera that pushes off the brushes is a later refinement.
      _smoothedPosition.read(_loop.alpha, _eye);
      player
        ..eyeFrom(_eye, _eye)
        ..aim(_aim);
      _target.setFrom(_eye);
      _eye
        ..addScaled(_aim, -_killcamDistance)
        ..y += _killcamHeight;
      _camera
        ..setPositionFrom(_eye)
        ..lookAt(_target);
      return;
    }

    _smoothedPosition.read(_loop.alpha, _eye);
    player
      // The interpolated position, not the simulated one — hence `eyeFrom`,
      // which takes the place rather than reading the body.
      ..eyeFrom(_eye, _eye)
      ..aim(_aim);
    _target
      ..setFrom(_eye)
      ..add(_aim);

    _camera
      ..setPositionFrom(_eye)
      ..lookAt(_target);
  }
}
