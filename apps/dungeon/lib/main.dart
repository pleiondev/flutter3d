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
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_shooter/bridge.dart';
import 'package:flutter3d_shooter/flutter3d_shooter.dart';
import 'package:flutter3d_shooter/sample.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gamepad/gamepad.dart' show PadButton;
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';
import 'src/effects.dart';
import 'src/fixture_looks.dart';
import 'src/hud.dart';
import 'src/monster_looks.dart';
import 'src/scene_surface.dart';
import 'src/sounds.dart';
import 'src/staging.dart';
import 'src/weapon_models.dart';

/// The game, as far as it goes: a room to stand in and a camera to look around
/// with.
///
/// Deliberately thin. Everything that could live in a package does — the
/// renderer in `flutter3d`, the clock and the input in `flutter3d_game`, the
/// pointer capture in `mouse_capture` — and what is left here is the part that
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
  LoadedLevel? _loaded;
  CharacterController? _body;

  /// Everything, loaded. Pickups arrive in a later stage and will replace
  /// this; until they do, a launcher nobody can find is a launcher nobody can
  /// test.
  /// Everything the player is carrying: health, armour, weapons, ammunition,
  /// keys and whatever power-up is running. One object rather than four fields,
  /// so a pickup has somewhere to give something to and the HUD has one thing
  /// to read — and so it can hang off the player's collider, which is how a
  /// locked door asks what the body in front of it holds.
  /// Who the player is, once there is a body to be.
  Player? _player;
  GameSimulation? _sim;
  GameState _shown = GameState.playing;

  final Inventory _inventory = startingInventory();

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
  ActorSystem? _actors;
  ActorVisuals? _actorVisuals;

  Arsenal get _arsenal => _inventory.arsenal;
  Health get _playerHealth => _inventory.health;
  int _kills = 0;

  /// Explosions from the last step, for the effects to catch up with.
  final List<Detonation> _blasts = <Detonation>[];

  /// The last shot's hits, for the impact markers the debug overlay draws.
  final List<ShotHit> _lastShot = <ShotHit>[];
  double _hitFlash = 0.0;

  /// Fades after the player is hurt. Red rather than the crosshair's white,
  /// because taking damage and dealing it must never look alike.
  double _painFlash = 0.0;

  final CameraNode _camera = CameraNode(name: 'player');
  late final RenderView _view;
  Renderer? _renderer;
  Object? _initError;

  /// The backend. Everything that uploads anything needs it, so it outlives
  /// `initState` as a field rather than being rebuilt where it is wanted.
  GraphicsDevice? _device;

  /// How far the eye sits above the centre of the player's box.
  static const double _eyeOffset = 0.7;

  final InterpolatedVector3 _smoothedPosition = InterpolatedVector3();

  Duration _lastTick = Duration.zero;
  int _steps = 0;
  double _fps = 0.0;

  // Scratch vectors, reused every step. Allocating these per frame is the
  // easiest way to hand the collector work it does not need.
  final Vector3 _right = Vector3.zero();
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

  /// Wall-clock seconds since the game started, for anything that only has to
  /// look alive — a turning pickup, a flickering torch.
  double _elapsed = 0.0;

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
  final Vector2 _dragLook = Vector2.zero();
  bool _dragging = false;

  void _drainDragLook(Vector2 out) {
    out.setFrom(_dragLook);
    _dragLook.setZero();
  }

  /// The mouse's motion — or the drag's, in a browser — plus the pad's.
  ///
  /// Where the pointer cannot be captured the delta comes from a drag instead. A
  /// first-person camera reads `lookDelta` inside the step, so the loop is the
  /// right place for it either way; and the pad **adds** to whichever of the two
  /// ran, rather than replacing it, so a player with a hand on each turns the
  /// view by the sum.
  void _drainLook(Vector2 out) {
    if (Playing.dragLook) {
      _drainDragLook(out);
    } else {
      _devices.drainLook(out);
    }
    _pad.drainLook(out);
  }
  SoLoudBackend? _soloud;

  /// Held while a mover is travelling, stopped when it arrives. A one-shot
  /// would be a stone slab that grinds for exactly as long as the sample.
  final Map<Mechanism, SoundEmitter> _moverVoices =
      <Mechanism, SoundEmitter>{};

  MechanismWorld? _mechanisms;
  FixtureVisuals? _fixtureVisuals;

  /// The last thing the level said, and how long it has left on screen.
  String _message = '';
  double _messageFor = 0.0;
  final Vector3 _muzzle = Vector3.zero();
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
    _device = device;

    _weaponView = WeaponView(
      models: dungeonWeaponModels(device),
      initial: Weapons.pistol,
    );

    // Inside `setState` because `build` is reading `_renderer` to decide
    // between the panel and the game, and by this point the first frame has
    // already been built.
    setState(() {
      try {
        _renderer = Renderer.create(
          device: device,
          fallbackAlbedo: SolidColorTexture.white.upload(device),
          fallbackNormal: SolidColorTexture.flatNormal.upload(device),
        );
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

    _ticker = createTicker(_onTick)..start();
    unawaited(_openAudio());
    unawaited(_loadLevel());
  }

  /// Starts SoLoud and swaps it in behind the mixer.
  ///
  /// Failing is allowed and is not fatal: a machine with no audio device, or a
  /// CI runner, keeps the silent backend and plays the game.
  Future<void> _openAudio() async {
    final backend = SoLoudBackend();
    try {
      await backend.open();
    } catch (error) {
      debugPrint('audio: could not start SoLoud: $error');
      return;
    }
    if (!mounted) return;
    _soloud = backend;
    _audio = AudioScene(
      backend: backend,
      // The walls belong to the physics; the mixer must not learn about them.
      // A wall between halves the sound rather than killing it, because a
      // monster you cannot hear at all is a monster that teleports.
      occlusion: _occlusionBetween,
    );
    await _audio.preload(Sounds.all);
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

  Future<void> _loadLevel() async {
    try {
      final loaded =
          await const LevelLoader().load(
        _levelAsset,
        device: _device!,
        registry: _entityKinds,
        rules: sampleRules(),
      );
      final visuals = ActorVisuals(
        loaded.scene,
        appearance: const DungeonMonsters(),
        device: _device!,
      );
      final fixtures = FixtureVisuals(
        loaded.scene,
        loaded,
        appearance: const DungeonFixtures(),
        device: _device!,
      )
        ..fallbackAlbedo = _renderer?.fallbackAlbedo
        // Before spawning, so a torch can find the light it drives.
        ..bindLights();

      // Everything that is not drawing — see `stage`, which is where the rest
      // of this used to be written out longhand, in this file and again in the
      // one test this application has.
      final staged = stage(
        loaded.level,
        loaded.collision,
        input: _input,
        registry: _entityKinds,
        inventory: _inventory,
        onActorSpawned: visuals.add,
        onFixture: fixtures.add,
        eyeOffset: _eyeOffset,
        lookSensitivity: _lookSensitivity,
      );
      _player = staged.player;

      if (!mounted) return;
      setState(() {
        _sim = staged.sim;
        _loaded = loaded;
        _body = staged.player.body;
        _actors = staged.actors;
        _actorVisuals = visuals;
        _mechanisms = staged.mechanisms;
        _fixtureVisuals = fixtures;
        _smoothedPosition.jumpTo(staged.player.body.position);
        // Loading blocked the ticker for a couple of seconds, and all of that
        // time is sitting in the accumulator. None of it happened in the game,
        // so it is dropped rather than simulated — otherwise the first frame
        // spends its whole budget catching up, and the dropped-step counter
        // reads as a performance problem for the rest of the session.
        _loop.clock.reset();
      });

      _startAmbience();

      for (final issue in loaded.issues.followedBy(staged.navIssues)) {
        debugPrint('level: $issue');
      }
    } catch (error, stack) {
      debugPrint('level failed to load: $error\n$stack');
      if (mounted) setState(() => _initError = error);
    }
  }

  @override
  void dispose() {
    _audio.stopAll();
    unawaited(_soloud?.dispose());
    unawaited(_settings.close());
    _keyboard.dispose();
    _ticker.dispose();
    _devices.dispose();
    super.dispose();
  }

  static const String _levelAsset = 'assets/levels/crypt.json';

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
    for (final bus in <AudioBus>[AudioBus.master, AudioBus.music, AudioBus.sfx]) {
      _audio.mixer.setVolume(bus, config.volumeOf(bus.name));
    }
    _pad.applySettings(config);
    _input.setToggled(
      GameAction.sprint,
      toggled: config.settingOf('a11y.toggleSprint', 0.0) >= 0.5,
    );
  }

  void _setVolume(AudioBus bus, double volume) =>
      _settings.setVolume(bus.name, volume);

  void _setSetting(String name, double value) =>
      _settings.setSetting(name, value);

  /// Takes a control the player has just offered for the waiting action.
  /// Saving is `SettingsCubit`'s, and so is the rebuild.
  bool _capture(InputSource source) => _settings.capture(source);

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
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt > 0.0) _fps = _fps * 0.9 + (1.0 / dt) * 0.1;

    _elapsed += dt;
    if (_fogAlternates) {
      final phase = (_elapsed / 2.0).floor().isEven;
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
    // A pad button offered to a waiting rebinding, so a controller can be
    // remapped from the controller.
    if (_settings.state.waitingFor != null && _pad.heldButtons.isNotEmpty) {
      _capture(InputSource.pad(_pad.heldButtons.first.id));
    }
    // A player on a controller never captures the pointer, so a gate that only
    // knew about the mouse would leave them looking at a frozen dungeon.
    // The same gate the platformer names in `pause_gate.dart`, minus its menu:
    // this game has no settings panel to open, which is the one clause that
    // file adds. When it grows one, that clause comes with it.
    // A menu is open, or the player is somewhere else. The platformer's
    // `pause_gate.dart` carries the three ways this line has been wrong; the
    // menu clause is the one that arrived with the panel below.
    _loop.paused = _settings.state.isOpen ||
        (Playing.capturesPointer &&
            !_devices.isCaptured &&
            !_pad.isConnected);
    _steps = _loop.advance(dt);
    // Once a frame, not once a step: this is display, and the simulation does
    // not care where the capsules are.
    _actorVisuals?.sync();
    _fixtureVisuals?.sync(_elapsed);
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
    if (outcome != null) {
      if (outcome is Refused) _audio.play(Sounds.locked, sim.firedFrom);
      _say(outcome.message);
    }

    final mechanisms = _mechanisms;
    if (mechanisms != null) _hearMechanisms(mechanisms);

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

    // Said once, on the edge. There is no restart and no next level to load
    // yet, so this is exactly as much as the application can honestly do about
    // either — and it is more than the nothing it did before, when `exit`
    // spawned no mechanism and dying left you walking around at zero health.
    if (sim.state != _shown) {
      _shown = sim.state;
      switch (sim.state) {
        case GameState.playing:
          break;
        case GameState.dead:
          _say('You died.');
        case GameState.complete:
          final next = sim.nextLevel;
          _say(next == null ? 'Level complete.' : 'Level complete — $next.');
      }
    }

    _showShot(sim);
    _showActors(sim);
    _showBlasts(sim);

    final body = player.body;
    _weaponView.step(
      dt,
      speed: math.sqrt(
        body.velocity.x * body.velocity.x + body.velocity.z * body.velocity.z,
      ),
      grounded: body.isGrounded,
    );

    _burnTorches();
    _particles.advance(dt);

    // Last, so every source has already moved this step. The listener is the
    // simulated eye rather than the interpolated one: the mix should follow
    // the game's idea of where the player is, not the renderer's.
    player.eye(_eye);
    _ears.aimAt(_eye, player.yaw);
    _audio.update(_ears);

    _smoothedPosition.push(body.position);
  }

  /// The noise and the sparks a shot makes. The shot itself already happened.
  void _showShot(GameSimulation sim) {
    final weapon = sim.firedThisStep;
    if (weapon == null) return;
    _weaponView.recoil();

    // At the eye rather than at the muzzle, for the same reason the shot
    // starts there: a sound half a metre to one side pans audibly wrong when
    // the player is against a wall.
    _audio.play(
      weapon.ammo == AmmoType.shells ? Sounds.shotgun : Sounds.pistol,
      sim.firedFrom,
    );

    _lastShot
      ..clear()
      ..addAll(sim.hits);
    if (_lastShot.any((ShotHit h) => h.struckSomething)) {
      _hitFlash = _system.screenFlash;
    }

    // Where the muzzle actually is, unlike where the shot came from: the flare
    // is the one thing that should sit at the barrel rather than at the eye.
    _player!
      ..aim(_aim)
      ..right(_right);
    _muzzle
      ..setFrom(sim.firedFrom)
      ..x += _aim.x * 0.6 - _right.x * 0.18
      ..y += _aim.y * 0.6 - 0.12
      ..z += _aim.z * 0.6 - _right.z * 0.18;
    _particles.burst(Effects.muzzleFlash, _muzzle, direction: _aim);

    for (final hit in _lastShot) {
      if (!hit.struckSomething) continue;
      _particles.burst(Effects.impactSparks, hit.point, direction: hit.normal);
      _particles.burst(Effects.impactDust, hit.point, direction: hit.normal);
    }
  }

  void _showActors(GameSimulation sim) {
    final monsters = sim.actors;
    if (monsters == null) return;
    for (final dead in monsters.died) {
      _kills++;
      _particles.burst(Effects.impactSparks, dead.position!);
      _audio.play(Sounds.monsterDie, dead.position!);
    }
    // `Sounds.monsterPain` was declared, preloaded and never played: nothing
    // anywhere could tell that a monster had been hit and survived. Only the
    // ones that flinched make a noise — a hit that did not stagger reads as a
    // hit that did not land, and every hit screaming is worse than none.
    for (final hurt in monsters.hurtThisStep) {
      if (hurt.staggered) {
        _audio.play(Sounds.monsterPain, hurt.actor.position!);
      }
    }
  }

  void _showBlasts(GameSimulation sim) {
    final projectiles = sim.projectiles;
    if (projectiles == null || projectiles.detonations.isEmpty) return;
    for (final blast in projectiles.detonations) {
      _particles.burst(Effects.explosionCore, blast.position);
      _particles.burst(Effects.explosionEmbers, blast.position);
      // And smoke for a second after the fire is out, from a key that belongs
      // to this blast alone. A fresh object rather than the position: two
      // rockets landing in the same doorway are two plumes, and a key they
      // shared would mean the second restarted the first. The system drops the
      // emission when it runs out, so a key per blast does not accumulate.
      _particles.emitTimed(
        Object(),
        Effects.explosionSmoke,
        blast.position,
        perSecond: 34.0,
        seconds: 0.85,
      );
    }
    _blasts
      ..clear()
      ..addAll(projectiles.detonations);
    _hitFlash = _system.screenFlash;
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

  void _hearMechanisms(MechanismWorld mechanisms) {
    for (final started in mechanisms.events.started) {
      _moverVoices[started] =
          _audio.play(Sounds.stoneMove, started.origin ?? _eye);
    }
    for (final stopped in mechanisms.events.stopped) {
      _moverVoices.remove(stopped)?.stop();
      _audio.play(Sounds.stoneStop, stopped.origin ?? _eye);
    }
    for (final entry in _moverVoices.entries) {
      final at = entry.key.origin;
      if (at != null) entry.value.position.setFrom(at);
    }

    for (final taken in mechanisms.events.taken) {
      _audio.play(Sounds.pickup, taken.origin ?? _eye);
    }
    for (final said in mechanisms.events.messages) {
      _say(said);
    }
  }

  void _say(String? message) {
    if (message == null) return;
    _message = message;
    _messageFor = 3.0;
  }

  @override
  Widget build(BuildContext context) {
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

    if (loaded == null || body == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Loading the crypt…',
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
          // A rebinding takes the next key, before anything else looks at it —
          // including Escape, which is how a player says "not that one".
          if (event is KeyDownEvent && _settings.state.waitingFor != null) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _settings.rebind(null);
            } else {
              _capture(InputSource.key(event.logicalKey.keyId));
            }
            return KeyEventResult.handled;
          }
          // Escape opens the settings as well as letting the pointer go, so a
          // player on a controller — who never took the pointer — has a way in.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            if (!_settings.state.isOpen) _openSettings();
            _settings.toggle();
            return KeyEventResult.handled;
          }
          // F toggles the fog in place. A before-and-after has to come from
          // one process at one camera position, which is exactly what the
          // measurement I threw away did not have.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyF) {
            setState(() => _fogOn = !_fogOn);
          }
          // **With the panel open the keys belong to the panel.** Handing them
          // to the game costs two things at once: Flutter's focus traversal
          // never sees Tab or the arrows, so a player with no mouse cannot
          // reach a slider at all — and a key held as the panel opened stays
          // held in the `InputState`, so closing it sends the player walking
          // off on their own.
          if (_settings.state.isOpen) return KeyEventResult.ignored;
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
                fog: FogSettings(
                  color: loaded.level.fogColor,
                  density: _fogOn ? loaded.level.fogDensity : 0.0,
                ),
                onBeforeFrame: _placeCamera,
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
                      _dragging = true;
                      if (!Playing.touch) {
                        _devices.pressPointer(ShooterActions.fire);
                      }
                    },
                    onPointerMove: (PointerMoveEvent event) {
                      if (!_dragging) return;
                      _dragLook.add(Vector2(event.delta.dx, event.delta.dy));
                    },
                    onPointerUp: (_) {
                      _dragging = false;
                      if (!Playing.touch) {
                        _devices.releasePointer(ShooterActions.fire);
                      }
                    },
                    onPointerCancel: (_) {
                      _dragging = false;
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
              // The panel and the gear are the same piece of state seen twice,
              // so they are built from it rather than from two flags that have
              // to be kept opposite.
              BlocBuilder<SettingsCubit, SettingsState>(
                bloc: _settings,
                builder: (BuildContext context, SettingsState settings) {
                  if (!settings.isOpen) {
                    return Positioned(
                      right: 18,
                      top: 16,
                      child: IconButton(
                        tooltip: 'Settings',
                        onPressed: () {
                          _openSettings();
                          _settings.show();
                        },
                        icon: const Icon(Icons.settings, color: Colors.white70),
                      ),
                    );
                  }
                  return SettingsPanel(
                    mixer: _audio.mixer,
                    bindings: _devices.bindings,
                    config: _config,
                    padConnected: _pad.isConnected,
                    actions: _rebindable,
                    waitingFor: settings.waitingFor,
                    onVolume: _setVolume,
                    onSetting: _setSetting,
                    onRebind: _settings.rebind,
                    onResetControls: () =>
                        _settings.resetControls(_defaultBindings()),
                    // Cancelling a waiting rebind is the cubit's, because a
                    // panel closed any other way — Escape, the pad — has to do
                    // the same thing and used not to.
                    onClose: _settings.hide,
                  );
                },
              ),
              Hud(
                // Nothing to capture in a browser, so nothing to prompt for.
                captured: !Playing.capturesPointer || _devices.isCaptured,
                fps: _fps,
                steps: _steps,
                dropped: _loop.clock.droppedSteps,
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
