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
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pad_input/pad_input.dart' show PadButton;
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';
import 'src/credits.dart';
import 'src/effects.dart';
import 'src/fixture_looks.dart';
import 'src/hud.dart';
import 'src/monster_looks.dart';
import 'src/reactions.dart';
import 'src/run_cubit.dart';
import 'src/sounds.dart';
import 'src/soundtrack.dart';
import 'src/staging.dart';
import 'src/weapon_models.dart';

/// The game, as far as it goes: a room to stand in and a camera to look around
/// with.
///
/// Deliberately thin. Everything that could live in a package does — the
/// renderer in `flutter3d`, the clock and the input in `flutter3d_game`, the
/// pointer capture in `pointer_lock` — and what is left here is the part that
/// is specific to this game. Right now that is a handful of boxes, because the
/// level format does not exist yet.
///
/// What this proves, which no unit test can: that the fixed step, the captured
/// mouse and the renderer agree with each other at 60 Hz on a real device.
void main() {
  // A phone is held the way a first-person camera wants it, and rotating it
  // mid-fight would reframe the shot. `ensureInitialized` because both calls
  // are platform channels.
  if (Playing.touch) {
    WidgetsFlutterBinding.ensureInitialized();
    unawaited(SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  }
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
  final SettingsFile _settingsFile = SettingsFile(appName: 'dungeon');
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
    ShooterActions.fire,
    GameAction.use,
  ];
  late final DesktopInput _devices;
  late final PadInput _pad;
  late final GameLoop _loop;
  late final Ticker _ticker;

  /// The level, once it has loaded. Null while it is loading or if it failed.
  /// The run: which level is up, what happened to it, and where next.
  ///
  /// Built in [_openGraphics], because loading needs a device.
  late final RunCubit _run;

  /// What the render loop reads, all of it owned by [_run] now. Getters rather
  /// than fields so there is one answer to "which level is this" — seven fields
  /// assigned in one `setState` were seven chances for a load to leave one of
  /// them describing the level before.
  LevelReady? get _level => _run.level;
  LoadedLevel? get _loaded => _level?.loaded;
  CharacterController? get _body => _level?.staged.player.body;

  /// Everything, loaded. Pickups arrive in a later stage and will replace
  /// this; until they do, a launcher nobody can find is a launcher nobody can
  /// test.
  /// Everything the player is carrying: health, armour, weapons, ammunition,
  /// keys and whatever power-up is running. One object rather than four fields,
  /// so a pickup has somewhere to give something to and the HUD has one thing
  /// to read — and so it can hang off the player's collider, which is how a
  /// locked door asks what the body in front of it holds.
  /// Who the player is, once there is a body to be.
  Player? get _player => _level?.staged.player;
  GameSimulation? get _sim => _level?.staged.sim;

  Inventory get _inventory => _run.inventory;

  /// Everything a document in this game's levels may name.
  ///
  /// Built once and shared by the loader's validator and the spawner, so the
  /// two cannot disagree about what a level is allowed to contain.
  final EntityRegistry _entityKinds = sampleRegistry();

  final ParticleSystem _particles = ParticleSystem(capacity: 3000);
  /// The pistol, not the fists: the game starts with both, and a shooter that
  /// opens on empty hands looks unfinished.
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

  double _hitFlash = 0.0;

  /// Fades after the player is hurt. Red rather than the crosshair's white,
  /// because taking damage and dealing it must never look alike.
  double _painFlash = 0.0;

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

  // Scratch for the occlusion ray, which runs once per audible source per
  // frame and must not allocate.
  final Vector3 _sound = Vector3.zero();
  final Vector3 _flameAt = Vector3.zero();

  /// Toggled by F, and also on its own every two seconds while
  /// [_fogAlternates] is set.
  ///
  /// The automatic half is there because three attempts at an A/B were spoiled
  /// by a synthetic keystroke not reaching the window. A measurement that
  /// depends on the window manager cooperating is not a measurement; one that
  /// depends only on the clock is.
  bool _fogOn = true;

  /// Off in normal play. Turned on for a measurement.
  static const bool _fogAlternates =
      bool.fromEnvironment('DUNGEON_FOG_AB');

  /// What [Effects.flame] settles at with a torch burning steadily.
  ///
  /// Measured from the running game rather than derived — 0.24 to 0.30 with
  /// forty-odd particles alive — because the number depends on the effect's
  /// sizes, alphas and lifetimes in a way that is not worth deriving and would
  /// be wrong the moment any of them changed. The spread around it is the
  /// flicker, and it is the fire's own rather than a sine's.
  static const double _flamePower = 0.34;
  final RayHit _soundRay = RayHit();

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

  final Map<Object, SoundEmitter> _moverVoices =
      <Mechanism, SoundEmitter>{};

  MechanismWorld? get _mechanisms => _level?.staged.mechanisms;
  FixtureVisuals? get _fixtureVisuals => _level?.fixtureVisuals;

  /// The last thing the level said, and how long it has left on screen.
  String _message = '';
  double _messageFor = 0.0;
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
      bindings: (PadInput.knowsPad(_devices.bindings)
          ? _devices.bindings
          : PadInput.addDefaultsTo(_devices.bindings))
        ..bind(InputSource.pad(PadButton.triggerRight.id), ShooterActions.fire)
        ..bind(InputSource.pad(PadButton.shoulderRight.id), ShooterActions.fire),
      slotButtons: PadInput.dpadSlots,
    );
    _loop = GameLoop(
      input: _input,
      onStep: _step,
      drainLook: _drainLook,
    );

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

    _weaponView = WeaponView(
      models: dungeonWeaponModels(device),
      initial: Weapons.pistol,
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
    if (speakers == null || !mounted) return;
    _soloud = speakers.backend;
    _audio = speakers.scene;
    _applyConfig(_config);
    _startAmbience();
  }

  /// How much of a sound survives the trip from [from] to [to].
  double _occlusionBetween(Vector3 from, Vector3 to) {
    final loaded = _loaded;
    if (loaded == null) return 1.0;
    _sound
      ..setFrom(to)
      ..sub(from);
    final distance = _sound.length;
    if (distance < 1e-3) return 1.0;
    _sound.scale(1.0 / distance);
    final blocked = loaded.collision.raycast(
      from,
      _sound,
      distance,
      _soundRay,
      mask: CollisionLayers.world,
    );
    return blocked ? 0.35 : 1.0;
  }

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
      _audio.play(Sounds.torch, torch.position);
    }
  }

  bool _ambienceStarted = false;

  /// Builds the run once there is a device to load through.
  ///
  /// The loader and the scene builder are handed in rather than reached for, so
  /// that `run_cubit_test.dart` can hand over a `CpuDevice` and drive the whole
  /// chain — starting, dying, restarting, moving on, quitting and coming back —
  /// without a window.
  void _openRun(GraphicsDevice device) {
    _run = RunCubit(DungeonRun(
      firstLevel: _firstLevel,
      registry: _entityKinds,
      input: _input,
      inventory: startingInventory(),
      saves: SaveFile(appName: 'dungeon'),
      eyeOffset: _eyeOffset,
      lookSensitivity: _lookSensitivity,
      loader: (String asset, EntityRegistry registry) =>
          const LevelLoader().load(
        asset,
        device: device,
        registry: registry,
        rules: sampleRules(),
      ),
      openScene: (LoadedLevel loaded) => (
        actors: ActorVisuals(
          loaded.scene,
          appearance: const DungeonMonsters(),
          device: device,
        ),
        fixtures: FixtureVisuals(
          loaded.scene,
          loaded,
          appearance: const DungeonFixtures(),
          device: device,
        )
          // Before spawning, so a torch can find the light it drives.
          ..bindLights(),
      ),
    ));
  }

  /// Everything the widget has to do when a level arrives.
  ///
  /// A listener rather than the tail of the load, because the load happens in
  /// the cubit now and these are all effects on things the cubit does not own:
  /// a smoothed camera position, an accumulator full of loading time, and a
  /// looping sound.
  void _levelArrived(LevelReady level) {
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
    _startAmbience();
    // **On entering a level, and on quitting, and at no other time.** This game
    // has no checkpoints — the platformer saves when its respawn point moves,
    // and there is nothing here that moves. A door is not a checkpoint: a
    // player who opens one and then dies has not earned the corridor beyond it.
    // A write per frame would put a file in the frame budget; a write only on
    // quit loses a level to a crash.
    _run.save();
    for (final issue
        in level.loaded.issues.followedBy(level.staged.navIssues)) {
      debugPrint('level: $issue');
    }
  }

  @override
  void dispose() {
    // The other half of the rule above: quitting keeps the level you are in.
    _run.save();
    _audio.stopAll();
    unawaited(_soloud?.dispose());
    unawaited(_settings.close());
    _keyboard.dispose();
    _ticker.dispose();
    _devices.dispose();
    super.dispose();
  }

  static const String _firstLevel = 'assets/levels/crypt.json';

  /// The table this game ships with, for the panel's way back.
  static Bindings _defaultBindings() =>
      PadInput.addDefaultsTo(DesktopInput.defaultBindings())
        ..bind(InputSource.pad(PadButton.triggerRight.id), ShooterActions.fire)
        ..bind(InputSource.pad(PadButton.shoulderRight.id), ShooterActions.fire);

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
  }

  /// What the player has already told the operating system.
  ///
  /// **The whole of this game's accessibility settings, and deliberately.** The
  /// crypt has no settings screen — no volumes, no bindings, nothing — so an
  /// in-game slider would mean building one. What it can do without any of that
  /// is honour the answer the player has already given their system, which is
  /// the answer they would rather not give twice.
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

  void _onTick(Duration elapsed) {
    final dt = _frames.secondsSince(elapsed);
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
    if (_presses.offer(_pad, _settings) &&
        _runIsOver &&
        _pad.heldButtons.contains(PadButton.start)) {
      unawaited(_run.restart());
    }
    // The shared gate, which this game used to write out by hand. Two things
    // came with it: the comment beside the copy still said this game had no
    // settings panel — it has had one for a while — and the copy had **no
    // `ready` clause at all**, so the loop accumulated simulated time while a
    // level was still loading and threw it away on arrival.
    _loop.paused = shouldPause(
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
    // not care where the capsules are.
    _actorVisuals?.sync();
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
    sim.step(dt);

    // A weapon can change hands inside the step — a slot key, or the last
    // round of the current one. The view model is told once, here, rather than
    // by the two places that could have caused it.
    if (!identical(_arsenal.current, heldBefore)) {
      _weaponView.selectWeapon(_arsenal.current);
    }

    final outcome = sim.usedThisStep;
    if (outcome != null) _say(outcome.message);

    // **What to play is decided in `Soundtrack` and only performed here.** It
    // used to be decided here too, in eight places inside a widget, where
    // nothing could ask what a step ought to sound like without a device and a
    // window — so the game being mute was undetectable, and four weapons
    // sharing two sounds went unnoticed for as long as the game has existed.
    _perform(_soundtrack.listen(sim, player));

    final mechanisms = _mechanisms;
    if (mechanisms != null) {
      for (final said in mechanisms.events.messages) {
        _say(said);
      }
    }

    if (_hitFlash > 0.0) _hitFlash = math.max(0.0, _hitFlash - dt * 4.0);
    if (_painFlash > 0.0) _painFlash = math.max(0.0, _painFlash - dt * 1.6);
    if (_messageFor > 0.0) _messageFor = math.max(0.0, _messageFor - dt);
    for (final power in _inventory.expired) {
      _say('$power has run out.');
    }
    _inventory.expired.clear();

    // Scaled rather than skipped, so the day a platform reports the two apart a
    // flash can be turned down without turning the camera down with it. A
    // full-screen flash on every hit is a photosensitivity question, which is
    // not the same harm as a camera that moves by itself.
    if (sim.damageTakenThisStep > 0.0) _painFlash = _system.screenFlash;

    // The run's own state, republished by the cubit on the step it changes —
    // which is what makes the announcement below a listener rather than an
    // edge detector kept in a field here.
    _run.observe();
    // Once a level says there is somewhere to go, go. Does nothing until the
    // level is finished and nothing twice; the guard is the cubit's.
    unawaited(_run.advance());

    // **What is shown is decided in `Reactions` and only performed here**, for
    // the same reason the sound is: three private methods of a widget nothing
    // can mount meant no test in this application had ever mentioned a
    // particle.
    _show(_reactions.listen(sim, player));

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

    _burnTorches();
    // The frame the loop accepted — see `GameLoop.lastFrame`. This game had no
    // limit of its own at all.
    _particles.advance(_loop.lastFrame);

    // Last, so every source has already moved this step. The listener is the
    // simulated eye rather than the interpolated one: the mix should follow
    // the game's idea of where the player is, not the renderer's.
    player.eye(_eye);
    _ears.aimAt(_eye, player.yaw);
    _audio.update(_ears);

    _smoothedPosition.push(body.position);
  }

  /// Performs what `Reactions` decided. Nothing here chooses anything.
  void _show(Reaction reaction) {
    for (final shown in reaction.bursts) {
      _particles.burst(shown.effect, shown.at, direction: shown.direction);
    }
    for (final lingering in reaction.lingering) {
      _particles.emitTimed(
        lingering.key,
        lingering.effect,
        lingering.at,
        perSecond: lingering.perSecond,
        seconds: lingering.seconds,
      );
    }
    // Scaled by the player's own setting rather than decided in `Reactions`: a
    // full-screen flash on every hit is a photosensitivity question, and how
    // much of one is the player's answer.
    if (reaction.flash) _hitFlash = _system.screenFlash;
  }

  /// Every torch, every step. The rate is per second and the system keeps each
  /// source's fractional remainder, so the fire looks the same on a 60 Hz
  /// display and a 120 Hz one.
  void _burnTorches() {
    final fixtures = _fixtureVisuals;
    if (fixtures == null) return;
    for (final entry in fixtures.flames.entries) {
      final fixture = entry.key;
      final fire = entry.value;
      if (!fixture.enabled) continue;
      // A steady rate, not one modulated by brightness. The flicker is
      // supposed to come out of the fire, and feeding brightness back into the
      // emission rate would make it come out of itself.
      _particles.emit(
        fire,
        Effects.flame,
        fire.originInto(_flameAt),
        perSecond: 150.0,
      );

      // And the light is what the fire measures, not a sine running alongside
      // it. Divided by the power a healthy flame settles at, so the fixture
      // sees a fraction and the level's own intensity stays the thing that
      // decides how bright a torch is.
      fixture.measure(
        fire.glow.power / _flamePower,
        // Only once the glow has seen a particle. Before that its centre is
        // the world origin, and a torch whose light spends its first frames
        // inside a wall is worse than one that never moved at all.
        at: fire.glow.located ? fire.glow.centre : null,
      );
    }
  }

  /// Plays what the soundtrack decided, and keeps the running voices in place.
  ///
  /// The lifetimes are the only thing left here, and they are effects rather
  /// than decisions: a grinding door is one voice that has to be started,
  /// moved and stopped by the same key, and which key that is was decided in
  /// `Soundtrack`.
  void _perform(Sounding sounding) {
    for (final heard in sounding.once) {
      _audio.play(heard.sound, heard.at);
    }
    for (final loop in sounding.loops) {
      switch (loop.what) {
        case Voice.begin:
          _moverVoices[loop.key] = _audio.play(loop.sound!, loop.at!);
        case Voice.follow:
          _moverVoices[loop.key]?.position.setFrom(loop.at!);
        case Voice.end:
          _moverVoices.remove(loop.key)?.stop();
      }
    }
  }

  void _say(String? message) {
    if (message == null) return;
    _message = message;
    _messageFor = 3.0;
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<RunCubit, RunStatus<LevelReady>>(
        bloc: _renderer == null ? null : _run,
        // The three things that have to happen *when* the run changes rather
        // than every time it is drawn: a new level needs its camera put where
        // the player is, and an ended one needs saying out loud.
        listener: (BuildContext context, RunStatus<LevelReady> run) {
          switch (run) {
            case RunPlaying<LevelReady>(
                  :final level,
                  outcome: RunOutcome.playing,
                ):
              _levelArrived(level);
            case RunPlaying<LevelReady>(outcome: RunOutcome.lost):
              _say('You died. Press R to try again.');
            case RunPlaying<LevelReady>(:final level, outcome: RunOutcome.won):
              final next = level.staged.sim.nextLevel;
              _say(next == null ? 'You are out.' : 'Level complete.');
            case RunLoading<LevelReady>() || RunFailed<LevelReady>():
              break;
          }
        },
        builder: (BuildContext context, RunStatus<LevelReady> run) =>
            _game(run),
      );

  Widget _game(RunStatus<LevelReady> run) {
    final renderer = _renderer;
    final loaded = _loaded;
    final body = _body;
    if (renderer == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Text(
              'The renderer did not start.\n\n$_initError\n\n'
              'The shader bundle is built by '
              'packages/flutter3d/tool/build_shaders.sh, and has to be rebuilt '
              'after every Flutter SDK change.',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    if (run is RunFailed<LevelReady>) {
      // **This used to be a black screen for ever**: the load caught its own
      // throw and printed it, which is a line in a console nobody playing the
      // game can see. Every one of these is a content mistake — the failure a
      // person editing a level makes.
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Text(
              'That level would not load.\n\n${run.asset}\n\n${run.error}',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    if (loaded == null || body == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Loading…',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
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
          final settingsSay =
              settingsKeys(event, _settings, opening: _openSettings);
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
          // F toggles the fog in place. A before-and-after has to come from
          // one process at one camera position, which is exactly what the
          // measurement I threw away did not have.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyF) {
            setState(() => _fogOn = !_fogOn);
          }
          return _devices.handleKeyEvent(event);
        },
        child: Listener(
          // Desktop only. The web build reads its pointer from the layer above
          // the platform view — see the stack below — because a platform view
          // takes every pointer event over it.
          onPointerDown: (_) {
            _keyboard.requestFocus();
            if (!Playing.capturesPointer) return;
            if (_devices.isCaptured) {
              _devices.pressPointer(ShooterActions.fire);
            } else {
              _devices.captureMouse();
            }
          },
          onPointerUp: (_) {
            if (!Playing.capturesPointer) return;
            _devices.releasePointer(ShooterActions.fire);
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
                  // Off until the surface buffer carries roughness. Without it
                  // the shader reflects off rough stone as readily as off a wet
                  // floor, and the walls light up instead of the floor.
                  //
                  // Off for a second reason too: the march tests only the
                  // front-most depth, so a ray passing behind a wall counts as
                  // hitting it and picks up whatever is drawn at that pixel — a
                  // highlight straight through solid stone. It needs a
                  // view-space test, not a depth-space one.
                  reflections: const ReflectionSettings(),
                  // Straight from the document. A crypt without fog is a crypt
                  // with a visible far wall, and the far wall is the thing an
                  // author least wants seen.
                  fog: FogSettings(
                    color: loaded.level.fogColor,
                    density: _fogOn ? loaded.level.fogDensity : 0.0,
                  ),
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
                      }
                    },
                    onPointerMove: (PointerMoveEvent event) =>
                        _dragLook.moved(event.delta),
                    onPointerUp: (_) {
                      _dragLook.end();
                      if (!Playing.touch) {
                        _devices.releasePointer(ShooterActions.fire);
                      }
                    },
                    onPointerCancel: (_) {
                      _dragLook.end();
                      if (!Playing.touch) {
                        _devices.releasePointer(ShooterActions.fire);
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
              SettingsOverlay(
                settings: _settings,
                mixer: _audio.mixer,
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

                hitFlash: _hitFlash,
                painFlash: _painFlash,
                health: _playerHealth,
                kills: _kills,
                monstersLeft: _actors?.aliveCount ?? 0,
                message: _message,
                messageOpacity: (_messageFor / 0.6).clamp(0.0, 1.0),
                keys: _inventory.keys,
                armour: _playerHealth.armour,
                ammo: _arsenal.currentAmmo,
                pouches: <AmmoType, int>{
                  for (final type in AmmoType.values)
                    if (type != AmmoType.none)
                      type: _arsenal.ammoOf(type),
                },
                powers: _inventory.powers,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Places the camera for the frame about to be drawn.
  ///
  /// Reads the interpolated position rather than the simulated one: on a
  /// display faster than the step rate, several frames in a row would otherwise
  /// show the same place and then jump.
  void _placeCamera() {
    final player = _player;
    if (player == null) return;

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
