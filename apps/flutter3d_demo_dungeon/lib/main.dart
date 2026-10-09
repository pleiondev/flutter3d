import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_demo_content/crypt.dart';
import 'package:flutter3d_demo_content/shooter_sample.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart'
    show
        Audible,
        Elements,
        ElementsQuality,
        HearingScale,
        LiquidLook,
        PhysicsHearing;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_physics/elements.dart' show ElementSounds;
import 'package:flutter3d_game_shooter/bridge.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
// `Material` exists in both flutter/material.dart and flutter3d. This file
// wants Flutter's, for the widgets; the files under `src/` that build the
// engine's do not import flutter/material.dart at all and so need no such
// dance.
import 'package:flutter3d_game_ui/flutter3d_game_ui.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show usePhysics;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pad_input/pad_input.dart';

import 'src/backend.dart';
import 'src/credits.dart';
import 'src/crypt_elements.dart';
import 'src/crypt_fog.dart';
import 'src/depths.dart';
import 'src/element_sounds.dart';
import 'src/ending.dart';
import 'src/first_shot_hint.dart';
import 'src/frame_effects.dart';
import 'src/high_contrast_rings.dart';
import 'src/hud.dart';
import 'src/layers.dart';
import 'src/photo_mode.dart';
import 'src/reactions.dart';
import 'src/run_cubit.dart';
import 'src/run_terminal.dart';
import 'src/shooter_keys.dart';
import 'src/sounds.dart';
import 'src/soundtrack.dart';
import 'src/spoken.dart';
import 'src/staging.dart';
import 'src/touch_crypt.dart';
import 'src/weapon_models.dart';
import 'src/wooden_props.dart';

/// Which build wrote a `.f3drun` — `Demo.buildStamp` is free text this
/// package has no opinion on the shape of, and this application's opinion is
/// "whatever the release process passes in, `dev` otherwise". A real release
/// train sets `--dart-define=FLUTTER3D_BUILD_STAMP=<version>`; nothing here
/// reads a package version at runtime, because that needs a plugin this
/// application does not otherwise carry.
const String _buildStamp = String.fromEnvironment(
  'FLUTTER3D_BUILD_STAMP',
  defaultValue: 'dev',
);

/// The game: five levels of a crypt, the things in them, and a run that
/// carries what the player is holding from one to the next.
///
/// Deliberately thin. Everything that could live in a package does — the
/// renderer in `flutter3d`, the clock and the input in `flutter3d_game`, the
/// level documents and their validator in `flutter3d_sim`, the shooter's rules
/// in `flutter3d_game_shooter`, the settings and the save in
/// `flutter3d_game`, the pointer capture in `pointer_lock` — and what is
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
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape and no system bars on a handset — see `lockLandscapeForTouch`,
  // which two applications had written out and the third had not.
  lockLandscapeForTouch(_playing);
  // Settings before the screen: the bindings a player saved are the ones the
  // keyboard should read from the first key press, not from the first rebind.
  final unread = <Issue>[];
  final config = await SettingsFile(
    appName: 'dungeon',
    defaultActions: shooterActionMap,
    onIssue: (Issue reported) {
      printIssue(reported);
      unread.add(reported);
    },
  ).read();
  runApp(DungeonApp(config: config, configIssue: unread.lastOrNull?.message));
}

/// How this build is played — fingers or keys, a pointer that can be taken
/// — asked of the platform once, for the whole game.
final Playing _playing = Playing.ofPlatform();

class DungeonApp extends StatelessWidget {
  const DungeonApp({super.key, this.config, this.configIssue});

  /// What the player changed, read before the first frame; the defaults
  /// when null.
  final GameSettings? config;

  /// Why [config] could not be read, if it could not.
  final String? configIssue;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dungeon',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        Flutter3dGameLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: GameScreen(config: config, configIssue: configIssue),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.config, this.configIssue});

  /// See [DungeonApp.config].
  final GameSettings? config;

  /// See [DungeonApp.configIssue].
  final String? configIssue;

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
    defaultActions: shooterActionMap,
    onIssue: _sayIssue,
  );

  void _sayIssue(Issue reported) {
    printIssue(reported);
    _effects.say(reported.message);
  }

  /// The player's settings as they are now: replaced on every change, by
  /// [_applyConfig].
  late GameSettings _config;

  /// What the high-contrast look rings, and in which role's colour — `N9`.
  late final CryptRings _rings = CryptRings(() => _config);

  /// The colour table for the player's colour vision, once there is a device
  /// to hold it. See `ColorVisionLook`.
  ColorVisionLook? _vision;

  /// The settings screen, which is a state machine and now says so.
  late final GameSettingsController _settings;

  late final DesktopInput _devices;
  late final PadInput _pad;

  /// The engine's frame: the input, the steps phase by phase, the frame's
  /// phases. The shooter is a plugin of it ([_shooter]) and steps in its
  /// `physics` phase; what this game does around a step is its own systems
  /// — see [_addSystems] for the order, which is the order `_step` had.
  late final EngineLoop _loop;

  /// The genre, installed into [_loop]: it steps whichever simulation the
  /// level up now has, and nothing here calls `sim.step` itself.
  late final ShooterPlugin _shooter = ShooterPlugin(
    kinds: <EntityKind>[
      for (final type in _entityKinds.types) _entityKinds[type]!,
    ],
  );

  /// The weapon held before this step ran, read in the `input` phase and
  /// compared in `publish`: a slot key or the last round changes it inside
  /// the step.
  WeaponDef? _heldBefore;

  /// Times the shooter's step alone, for `rp-06` — started just before
  /// `shooter.step` and stopped just after it.
  final Stopwatch _stepWatch = Stopwatch();

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
  final EntityRegistry _entityKinds = sampleRegistry(
    // `wg-02`: `widget_surface` is a bridge word, not a shooter word — see
    // `sampleRegistry`'s own doc for why it arrives through `extra` rather
    // than as a new dependency of `flutter3d_game_shooter`.
    extra: const <EntityKind>[WidgetSurfaceKind()],
  );

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

  /// What one step's decisions turn into: particles, sounds, the flashes and
  /// the message the HUD reads. See `FrameEffects` for why this is not part
  /// of `_step`.
  final FrameEffects _effects = FrameEffects();

  /// Whether this run's own first-shot hint (`ls-g-01`) has already gone to
  /// [_effects] — reset in `_beginDemo`, so a restart teaches it again.
  bool _taughtFirstShot = false;

  final CameraNode _camera = CameraNode(name: 'player');
  late final RenderView _view;
  Renderer? _renderer;
  Object? _initError;

  /// Whether the run has ended, either way. Read by the two restarts.
  bool get _runIsOver => _run.isOver;

  /// Whether the crawl is finished — out of the last level, alive.
  ///
  /// Not [_runIsOver], which is also true of dying and of finishing any level
  /// that has one after it. Winning a level with somewhere to go next is not
  /// the end of anything: the game is already loading the next crypt, and the
  /// credits over that beat would roll four levels early.
  bool get _crawlIsOut {
    final sim = _sim;
    if (sim == null) return false;
    return sim.state == GameState.complete && sim.nextLevel == null;
  }

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
    if (_playing.usesDragLook) {
      _dragLook.drainInto(out);
    } else {
      _devices.drainLook(out);
    }
    _pad.drainLook(out);
  }

  AudioBackend? _soloud;

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

  /// The steps the last skipped cutscene ran, from the first to one past the
  /// last, as the loop numbers them. Their events reach the frame channel
  /// with the frame's own, and are neither shown nor heard.
  (int, int) _skipped = (0, 0);

  /// Whether the event the bus is handing out now is shown and heard: not one
  /// of [_skipped]'s.
  bool _shown = true;

  /// Where the soundtrack plays a skipped cutscene's events: nowhere.
  final AudioScene _unheard = AudioScene(backend: SilentBackend());

  MechanismWorld? get _mechanisms => _level?.staged.mechanisms;
  FixtureVisuals? get _fixtureVisuals => _level?.fixtureVisuals;
  WidgetSurfaceVisuals? get _widgetSurfaces => _level?.widgetSurfaces;

  final Vector3 _eye = Vector3.zero();
  final Vector3 _target = Vector3.zero();

  /// `N8`: the run stopped and a camera to fly — see [PhotoMode]. P.
  final PhotoMode _photo = cryptPhotoMode();

  /// What the frame on screen is drawn with, for a photo drawn larger.
  RenderSettings Function()? _frameSettings;

  LookSettings _photoLook(LookSettings seen) =>
      _photo.isActive && !_photo.isBusy ? _photo.look(seen) : seen;

  /// Opens photo mode where the player's eye is, or closes it.
  void _togglePhoto() {
    if (_photo.isActive) {
      setState(_photo.leave);
      return;
    }
    final loaded = _loaded;
    if (loaded == null || _player == null) return;
    setState(
      () => _photo.enter(
        world: loaded.collision,
        eye: _eye.clone(),
        target: _target.clone(),
        fieldOfView: const PerspectiveProjection().fovY,
      ),
    );
  }

  /// Draws the photo at [scale] times the window and saves it.
  Future<void> _takePhoto(int scale) async {
    final renderer = _renderer;
    final loaded = _loaded;
    final settings = _frameSettings;
    if (renderer == null ||
        loaded == null ||
        settings == null ||
        _photo.isBusy) {
      return;
    }
    final size =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    setState(() => _photo.isBusy = true);
    // The frame saying so is drawn first; after it nothing redraws until the
    // picture is done.
    await SchedulerBinding.instance.endOfFrame;
    final taken = await savePhoto(
      renderer: renderer,
      scene: loaded.scene,
      camera: _camera,
      width: (size.width * scale).round(),
      height: (size.height * scale).round(),
      settings: settings(),
      filter: _photo.filter,
      clearColorSrgb: _view.clearColorSrgb,
      shelf: defaultPhotoShelf('dungeon'),
      name: 'dungeon-${DateTime.now().millisecondsSinceEpoch}.png',
    );
    if (!mounted) return;
    setState(() {
      _photo
        ..isBusy = false
        ..said = taken.saved.message;
    });
  }

  @override
  void initState() {
    super.initState();

    // Settings before devices: the bindings a player saved are the ones the
    // keyboard should read from the first key press, not from the first rebind.
    _config = widget.config ?? const GameSettings();
    if (widget.configIssue case final String issue) _effects.say(issue);
    // **One map, and the settings controller holds it**: the keyboard, the
    // pad and the rebinding screen read the same object, and every change is
    // saved from it. A fresh table on a first launch, edited by the screen
    // and never saved, is the bug this replaced.
    final controls = _config.actionsOr(shooterActionMap);
    _devices = DesktopInput(state: _input, actions: controls);
    // A table saved before this game read a controller gains the pad's
    // defaults and keeps every rebinding the player made.
    if (!PadInput.knowsPad(controls)) PadInput.addDefaultsTo(controls);
    // One map for both devices, and the d-pad chooses a weapon here rather
    // than walking: this game numbers things, and a first-person player has the
    // left stick for walking already. A map saved before slots were actions
    // gains the number row too.
    PadInput.addSlotDefaultsTo(controls);
    if (!controls.buttons.sources.any(
      (InputSource s) => SlotActions.indexOf(controls.buttons[s]!) != null,
    )) {
      DesktopInput.addSlotsTo(controls, const <LogicalKeyboardKey>[
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
      ]);
    }
    _pad = PadInput(state: _input, actions: controls);
    // The genre's own, into whatever table came back — a fresh one or a saved
    // one. `fire` is not offered for rebinding, so it is simply
    // written every launch; `crouch` can, so a table that already says
    // something about crouching keeps what the player said, the same way
    // `knowsPad` leaves a saved table's rebindings alone above.
    if (controls.buttons.sourcesFor(ShooterActions.crouch).isEmpty) {
      addShooterKeysTo(controls.buttons);
    } else {
      controls.buttons
        ..bind(InputSource.pad(PadButton.triggerRight.id), ShooterActions.fire)
        ..bind(
          InputSource.pad(PadButton.shoulderRight.id),
          ShooterActions.fire,
        );
    }
    _loop = EngineLoop(
      input: _input,
      drainLook: _drainLook,
      // What the crypt looks and sounds like, and what it says to a screen
      // reader: view plugins hearing the shooter's events on the frame
      // channel, after the frame's steps and before it is drawn. The scene
      // the soundtrack plays through is asked for each event, since the
      // speakers replace the silent scene once they open.
      plugins: <Flutter3dPlugin>[
        _shooter,
        _reactions.plugin,
        _soundtrack.plugin(scene: () => _shown ? _audio : _unheard),
        SpokenEvents(cryptSpoken),
      ],
      registries: <PluginRegistry>[EntityKinds()],
    );
    _rewinding = _rewind.attach(_loop);
    // The monsters' animation markers are this game's event, published by
    // the strides it hangs on the actors (see `_beforeStep`).
    _loop.events.declare<AnimationMarkerPassed>(
      AnimationMarkerPassed.eventName,
      description: "A monster's animation passed a marker.",
      codec: AnimationMarkerPassed.codec,
    );
    // Before any plugin's subscription, being the application's: whether the
    // event about to be handed out belongs to a skipped cutscene, whose steps
    // happen and are not shown or heard.
    _loop.events.onFrame<BusEvent>('dungeon.shown', (
      Delivered<BusEvent> delivered,
    ) {
      final (from, to) = _skipped;
      _shown = delivered.step < from || delivered.step >= to;
      _reactions.quiet = !_shown;
    });
    _addSystems();
    // `rp-02`: harmless where the VM service is off (a release build, or a
    // debug run nobody attaches to) — `registerExtension` just adds an
    // entry nothing ever asks for.
    registerTimelineExtensions(
      _timeline,
      frameTimes: _frameTimes,
      bugReport: _remoteBugReport,
    );
    // `P12`: the frame this game draws, pass by pass and draw by draw, for
    // whichever renderer is open when somebody asks.
    registerRenderExtensions(() => _renderer);

    _view = RenderView(camera: _camera);

    _settings = GameSettingsController(
      settings: _config,
      actions: controls,
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
        _vision = ColorVisionLook(device);
      } catch (error) {
        _initError = error;
      }
    });

    // What draws alongside the world is registered rather than passed in each
    // frame. Particles inside the scene pass so they are lit and bloomed and
    // hidden by walls; the weapon over the top of it, sharing no depth with a
    // world that would otherwise slice the barrel off in every doorway.
    _renderer
      ?..renderSteps.addContributor(ParticleContributor(_particles))
      ..renderSteps.addNode(_weaponView.plugin);

    _openRun(device);
    _ticker = createTicker(_onTick)..start();
    unawaited(_openAudio());
    unawaited(_openElements(device));
    unawaited(_begin());
  }

  /// The fire, the water and the loose wood of the crypt, drawn and heard —
  /// see [CryptElements]. They are the run's own — see `CryptWorld` — and
  /// this only reads them. Null until the crates' pictures and the water's
  /// material have loaded and a level on the core is up, and on a renderer
  /// that failed.
  CryptElements? _elements;
  WoodenProps? _woodenProps;
  bool _adopting = false;
  final ElementSounds _elementSounds = ElementSounds(cryptElementCues);
  final Vector3 _elementsEye = Vector3.zero();

  /// Loads what the elements are drawn with, and stands them in the level
  /// that is up, if one already is. A failure leaves the crypt undrawn and
  /// the run as it is.
  Future<void> _openElements(GraphicsDevice device) async {
    try {
      final props = await WoodenProps.load(device);
      if (!mounted) return;
      _woodenProps = props;
    } catch (error) {
      debugPrint('elements: not loaded ($error)');
      return;
    }
    final level = _level;
    if (level != null) _enterElements(level);
  }

  /// What draws the run's elements, adopted onto [crypt]'s world — once for
  /// the run, since the world is the run's for as long as it lasts — and
  /// stood in the level that is up by then.
  Future<void> _adoptElements(CryptWorld crypt) async {
    final renderer = _renderer;
    final props = _woodenProps;
    if (renderer == null || props == null || _adopting) return;
    _adopting = true;
    try {
      final elements = await Elements.adopt(
        crypt.world,
        device: _run.run.device,
        renderer: renderer,
        scene: Scene(),
        load: rootBundle.load,
        quality: ElementsQuality.of(phone: _playing.touch),
        hearing: (world) => PhysicsHearing(
          world,
          fireScale: const HearingScale(
            quiet: 500.0,
            loud: 5e5,
            reference: 2e4,
          ),
          fallScale: const HearingScale(quiet: 50.0, loud: 1e5, reference: 5e3),
          splashScale: const HearingScale(
            quiet: 20.0,
            loud: 2e4,
            reference: 2e3,
          ),
        ),
      );
      final bundle = await rootBundle.load(LiquidLook.asset);
      if (!mounted) {
        elements.dispose();
        return;
      }
      _elements = CryptElements(
        elements: elements,
        device: _run.run.device,
        liquidBundle: bundle,
        props: props,
        particles: _particles,
        light: _playing.touch,
      );
    } catch (error) {
      debugPrint('elements: not drawn ($error)');
      return;
    } finally {
      _adopting = false;
    }
    final level = _level;
    if (level != null) _enterElements(level);
  }

  /// The elements of [level] drawn into its scene.
  void _enterElements(LevelReady level) {
    final crypt = level.crypt;
    if (crypt == null || _woodenProps == null) return;
    final elements = _elements;
    if (elements == null) {
      unawaited(_adoptElements(crypt));
      return;
    }
    _elementSounds.silence();
    elements.enter(
      crypt: crypt,
      scene: level.loaded.scene,
      textures: level.loaded.materialTextures,
    );
  }

  /// The run this device and the save server agree on, begun — the cloud
  /// asked first only if the player turned cloud saves on.
  Future<void> _begin() async {
    final synced = await syncBeforeBegin(context, _cloud.sync);
    if (synced != null) _effects.say(synced);
    if (mounted) await _run.begin();
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
    final Speakers speakers;
    try {
      speakers = await openSpeakers(
        bank: Sounds.all,
        occlusion: _occlusionBetween,
      );
    } on AudioDeviceException {
      return;
    }
    if (!mounted) {
      // The screen is gone and nothing below will adopt this backend, so it is
      // shut down here — its own doc warns that an engine left initialized
      // blocks a later open().
      unawaited(speakers.dispose());
      return;
    }
    _soloud = speakers.backend;
    _audio = speakers.scene;
    _applyConfig(_config);
    _startAmbience();
    // The crates' fires, the culvert and the splashes: the effects
    // package's recordings, loaded beside the game's own.
    unawaited(_audio.preload(cryptElementCues.all));
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
  final List<AudioEmitter> _ambience = <AudioEmitter>[];

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
        saves: _saves,
        widgetRegistry: <String, WidgetBuilder>{
          // `wg-02`'s first demo scene: a terminal on the crypt's own wall,
          // echoing what `_effects.say` already tells the HUD.
          'run-terminal': (context) => RunTerminal(log: _effects.log),
        },
        eyeOffset: _eyeOffset,
        lookSensitivity: _lookSensitivity,
        device: device,
        published: () => _loop.published,
      ),
    );
    _demos = DemoFile(appName: 'dungeon', onIssue: _sayIssue);
    _autosave = Autosave(_run.run)..watchLifecycle();
  }

  /// The run on this device.
  late final SaveFile _saves = SaveFile(appName: 'dungeon', onIssue: _sayIssue);

  /// What the player is asked about their data, and what a yes turns on:
  /// the run kept on the save server, finished levels sent to see where
  /// they are hard. Both off until answered.
  late final GameCloud _cloud = GameCloud(
    game: 'dungeon',
    storage: _saves.storage,
    saves: _saves,
    server: const String.fromEnvironment('FLUTTER3D_CLOUD'),
    policy: '2026-10',
  );

  /// Writes the run at a pause and when the window goes to the background,
  /// as well as on quitting.
  Autosave? _autosave;

  /// The last run, as what the player did. See [DemoFile].
  DemoFile? _demos;

  /// The run being recorded, through [_loop]: where it started and in which
  /// level, the tape, a checkpoint every so many steps — `rp-01`'s reason a
  /// `.f3drun` can be verified rather than only watched — and what the loop
  /// journals and each step's event digest, so a divergence is found to the
  /// event. Kept after the run ends, for the level a bug report names.
  DemoRecording? _demo;

  /// Whether [_demo] is still being written.
  bool _demoOpen = false;

  /// Starts writing the run down, from the state the level is in now.
  ///
  /// Now rather than at load: a level resumed from a save begins mid-run, and
  /// the demo has to begin where the player did. The tape's seed is the dice
  /// the snapshot carries, which is the one number a replay cannot do without.
  void _beginDemo(String asset, LevelReady level) {
    _taughtFirstShot = false;
    final start = level.staged.sim.save();
    // A kill camera still playing when the next level arrives — a restart
    // pressed through it — is over, and the level it was replaying is gone.
    _endKillcam(restorePresent: false);
    _endRecording();
    _demo = DemoRecording(
      physics: usePhysics(),
      level: asset,
      levelHash: level.loaded.level.digestHex,
      start: start,
      seed: start.data.integer('random'),
      simulation: shooterSimulationVersion,
    )..attach(_loop);
    _demoOpen = true;
    // The last few seconds, for the kill camera: a new level has none yet, and
    // the recorder is put back if a kill camera took it out.
    _rewinding?.cancel();
    _rewind.reset();
    _rewinding = _rewind.attach(_loop);
  }

  /// [_rewind] attached to [_loop]: its recorder and its keyframes, the
  /// loop's captures. Null while a kill camera plays.
  Registration? _rewinding;

  /// The loop's step when the kill camera took the present, which
  /// [_endKillcam] puts it back at.
  int _killcamStep = 0;

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
  /// * the rewind buffer would record the replay into the run's history; it
  ///   is detached from the loop, and attached again when the next level
  ///   begins.
  ///
  /// The present and the keyframe go through the loop's snapshots — every
  /// part of the state, the shooter's run among them — and the loop's step
  /// count with them.
  void _startKillcam() {
    final sim = _sim;
    if (sim == null || _killcamPresent != null) return;
    final point = _rewind.rewindBy(_killcamSeconds);
    if (point == null) return;
    _killcamPresent = _loop.capture();
    _killcamStep = _loop.step;
    final keyframe = point.step - point.replayed;
    final loopStep = _loop.step - (_rewind.step - keyframe);
    _rewinding?.cancel();
    _rewinding = null;
    _input
      ..clear()
      ..muted = true;
    _loop.rewindTo(loopStep, state: point.snapshot);
    // From the keyframe to the moment the camera starts, without drawing or
    // sounding: through the loop, marked resimulated, so the shooter steps
    // and nothing of this game's runs — no recorder writes, no keyframe is
    // taken, nothing is read or shown ([_addSystems] says so of each).
    final toPoint = point.tapeToPoint;
    _loop
      ..playback = InputTapePlayback(toPoint)
      ..runSteps(toPoint.steps, resimulated: true);
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
    if (restorePresent) _loop.rewindTo(_killcamStep, state: present);
  }

  /// The last ten seconds of the run, every step of them. See [RewindBuffer].
  ///
  /// Ten because that is what a death is worth looking back over; the memory
  /// is eleven snapshots of the crypt and six hundred tape entries, which the
  /// buffer's own doc puts a number on.
  final RewindBuffer _rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);

  /// `rp-02`'s door onto this run, over the VM service — see
  /// `registerTimelineExtensions`. Through the loop and its snapshots, so
  /// whichever simulation the shooter is stepping is the one rewound.
  late final RunTimeline _timeline = RunTimeline(rewind: _rewind, loop: _loop);

  /// `rp-06`: how long each step of `sim.step` cost, read back over the same
  /// VM service `_timeline` is on.
  final StepTimeTrace _frameTimes = StepTimeTrace();
  int _frameTimeStep = 0;

  /// `rp-04`'s "send this run", called remotely rather than from a button
  /// this game draws itself — the last few seconds `_rewind` has kept, as
  /// plain JSON. Null (and the extension answers with an error) when there
  /// is nothing to report yet, the same case `bugReportTape` itself returns
  /// null for.
  Map<String, Object?> _remoteBugReport() {
    // The start as the run's own snapshot, which is what a `.f3drun` holds.
    final report = bugReportTape(_rewind, part: ShooterPlugin.id);
    if (report == null) {
      throw StateError('nothing has been recorded yet');
    }
    // A run as a `.f3drun` reads it, with no checkpoints — a tool that
    // keeps it takes them by playing it again — so what an agent drops into
    // `test/tapes/` replays as it is.
    return <String, Object?>{
      'version': 1,
      'level': _demo?.level ?? 'unknown',
      'levelHash': _demo?.levelHash ?? '',
      'start': report.start.toJson(),
      'tape': report.tape.toJson(),
      'buildStamp': _buildStamp,
      'checkpoints': DigestTrace().toJson(),
      'platform': defaultTargetPlatform.name,
      'physics': usePhysics().name,
    };
  }

  /// Stops recording the demo, leaving the rewind buffer's recorder in
  /// place. The recording that was open, or null when none was.
  DemoRecording? _endRecording() {
    final demo = _demoOpen ? _demo : null;
    demo?.detach();
    _demoOpen = false;
    return demo;
  }

  /// Writes the run down when it ends, either way.
  ///
  /// Either way, because a death is the run somebody wants to send: "it shot
  /// me through the wall" is a sentence, and the demo is the proof. Written
  /// once at the end rather than as it goes, for the reason the save is: a
  /// write per step would put a file in the step budget.
  void _endDemo() {
    final recording = _endRecording();
    if (recording == null) return;
    // The physics it replays on is `PhysicsBackend.current`, which
    // `usePhysics` chose when the level was staged.
    final demo = recording.demo(
      buildStamp: _buildStamp,
      platform: defaultTargetPlatform.name,
    );
    unawaited(_demos?.write(demo));
    // To the server too, if the player said runs may go: the uploader
    // asks their answer at the moment of sending.
    unawaited(_cloud.send(demo));
  }

  /// `HR3`: the level on screen, as the editor sees it.
  LiveLevel? _live;

  /// Lets a level saved in the editor into this run, or tells the door
  /// which level is up now.
  ///
  /// **Registered with the first level rather than in [initState]**, because
  /// a `LiveLevel` compares every edit with the level it holds and there is
  /// none before one loads; a VM service extension cannot be registered
  /// twice, so later levels move the one door along. The edit is built ahead
  /// by [DungeonRun.prepareEdit] and swapped in inside [_timeline]'s replay
  /// by [DungeonRun.installEdit], so the run is lived again under it.
  void _takeEdits(LevelReady level) {
    final live = _live;
    if (live != null) {
      live.level = level.loaded.level;
      return;
    }
    final run = _run.run;
    registerLevelExtension(
      _live = LiveLevel(
        level: level.loaded.level,
        timeline: _timeline,
        prepare: run.prepareEdit,
        rebuild: (Level next) => run.installEdit(),
        present: (Level next, LevelDiff diff) => run.installEdit(),
      ),
    );
  }

  /// Everything the widget has to do when a level arrives.
  ///
  /// A listener rather than the tail of the load, because the load happens in
  /// the cubit now and these are all effects on things the cubit does not own:
  /// a smoothed camera position, an accumulator full of loading time, and a
  /// looping sound. [edited] when it is the same level changed in the
  /// editor and put in under the run, which is not one more level entered.
  void _levelArrived(LevelReady level, {bool edited = false}) {
    // One more level of the crypt stood in, for the screen at the end of it.
    // Here rather than in `DungeonRun` because this fires once per level
    // actually put in front of the player: a load overtaken by a newer one
    // never reaches this listener, and `RunSession.carryFrom` — the other
    // candidate — is not called for the last level at all.
    if (!edited) _run.run.crawl.levels++;
    _soundOcclusion = SoundOcclusion(level.loaded.collision);
    // The crypt's sparks and embers fall by the crypt's world, as its
    // monsters and its fire do.
    _particles.world = level.loaded.collision.properties;
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
    _loop.resetClock();
    // A load takes far longer than a frame and drops simulated time every time.
    // Counting that against the machine would light the warning on every level
    // of every run, which is the same as not having one.
    _pace.reset(_loop.lostSteps);
    // A fresh level makes its own noises. The soundtrack's running set and the
    // effects' mover voices both name the old level's mechanisms, and those
    // will never report `stopped` now — a mover caught mid-travel by the level
    // change was a stone slab grinding into the next level forever.
    _soundtrack.reset();
    _effects.stopVoices();
    // The old level's torches out, the new level's lit.
    _stopAmbience();
    _startAmbience();
    // And the old level's crates and water gone with it, the new level's
    // stood in.
    _enterElements(level);
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
    _autosave?.dispose();
    // Closed like [_settings], and the cubit unhooks itself from the session
    // first — see `RunCubit.close` for why the order matters.
    unawaited(_runOrNull?.close());
    _elementSounds.silence();
    _elements?.dispose();
    _audio.stopAll();
    unawaited(_soloud?.dispose());
    _settings.dispose();
    _keyboard.dispose();
    _ticker?.dispose();
    _devices.dispose();
    super.dispose();
  }

  static const String _firstLevel = 'assets/levels/crypt.json';

  /// The pointer goes back and the keys are let go, before a panel is shown.
  ///
  /// The second half used to happen only as a side effect of the first, so on a
  /// build with no pointer to release a key held as the panel opened stayed
  /// held — and closing it walked the player into a wall.
  void _openSettings() {
    unawaited(_devices.releaseMouse());
    _input.clear();
  }

  /// Puts the config onto everything that is playing.
  ///
  /// **One function called from one place**, which it was not: a volume change
  /// moved the mixer and nothing else, and a settings change moved the pad and
  /// the sprint toggle and not the mixer. Neither needed the other's half, and
  /// neither said so — which is how two half-applies stay correct right up
  /// until one of them grows a third thing.
  void _applyConfig(GameSettings config) {
    _config = config;
    applySavedVolumes(config, _audio.mixer);
    _pad.applySettings(config);
    _input.setToggled(
      GameAction.sprint,
      toggled: config.valueOf(GameSettingKeys.toggleSprint),
    );
    // **The most adjusted setting a first-person game has, and there was no
    // way to change it.** It was a `static const` compiled into this file; the
    // right stick had a slider and the mouse had nothing. Stored as a factor
    // rather than in radians per pixel, because that is a number somebody can
    // set by feel — and negative inverts, which is what a switch elsewhere in
    // the panel means.
    final scale = config.valueOf(GameSettingKeys.mouseLook);
    final inverted = config.valueOf(GameSettingKeys.mouseInvertY);
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
    final paused = _killcamPresent != null
        ? _settings.value.isOpen || _photo.isActive
        : shouldPause(
            ready: _sim != null,
            menuOpen: _settings.value.isOpen,
            pointerIsTheGate: _playing.capturesPointer,
            pointerHeld: _devices.isCaptured,
            padConnected: _pad.isConnected,
            photoMode: _photo.isActive,
          );
    // A level that has just arrived holds this one frame: the loop gives a
    // paused frame's time to nobody and empties its accumulator on the way
    // out, which drops the loading time. Not a pause the autosave hears of.
    _loop.isPaused = paused;
    unawaited(_autosave?.paused(now: paused && _sim != null));
    // Space or use, or the button on the overlay: whichever the player has.
    // Held rather than pressed, read here between steps — the simulation
    // reads none of the player's input while a cutscene plays, so the keys
    // are free.
    if (_sim?.cutscene != null &&
        (_skipAsked ||
            _input.held(GameAction.jump) ||
            _input.held(GameAction.use))) {
      _skipAsked = false;
      _skipCutscene();
    }
    _skipAsked = false;
    // The steps, then the frame's phases — the elements, the visuals, the
    // photo camera, the overlays; see [_addSystems].
    _steps = _loop.frame(dt);
    _pace.note(
      dropped: _loop.lostSteps,
      dt: dt,
      stepSeconds: _loop.stepSeconds,
    );
    // Not while a photo is drawn: a rebuild draws a frame on the renderer
    // the tiles are drawn on — see `capturePhoto`.
    if (!_photo.isBusy) setState(() {});
  }

  /// This game's half of [_loop]: what it does around the shooter's step,
  /// and what it does once a frame.
  ///
  /// **The step is in the order `_step` had under the old loop**, so a tape
  /// this game recorded steps the same simulation the same way:
  ///
  /// | phase | system | was |
  /// | --- | --- | --- |
  /// | `input` | `dungeon.before` | the weapon held, the rewind keyframe |
  /// | `physics` | `dungeon.time.start` | `rp-06`'s timer started |
  /// | `physics` | `shooter.step` (the plugin) | `sim.step(dt)` |
  /// | `physics` | `dungeon.time.stop` | `rp-06`'s timer read |
  /// | step's end | `onStepEnd` | the checkpoint, the step's events, the rest |
  ///
  /// The two timers name `shooter.step` in `before`/`after` rather than
  /// trusting registration order, which would put the application's systems
  /// first in the phase either way. A step run again — the kill camera's
  /// way to its starting point — runs the shooter and nothing here, as the
  /// hand-written loop it replaces did.
  ///
  /// Once a frame, after the steps, in the frame phases: the elements and
  /// the visuals in `animate`, the photo camera in `camera`, the overlays in
  /// `render`. These were the lines after `advance` in [_onTick], and each
  /// reads the world the steps left and changes none of it, so their order
  /// among themselves is the phases' and not the old line order.
  void _addSystems() {
    // The step's end rather than the `publish` phase, since that is where the
    // bus hands out what the step published: the whole step's events at once.
    _loop.onStepEnd(_afterStep);
    _loop
      ..addSystem('dungeon.before', LoopPhase.input, _beforeStep)
      ..addSystem('dungeon.time.start', LoopPhase.physics, (LoopContext step) {
        if (!step.isResimulated) _stepWatch.start();
      }, before: <String>[ShooterPlugin.stepSystem])
      ..addSystem('dungeon.time.stop', LoopPhase.physics, (LoopContext step) {
        if (step.isResimulated || !_stepWatch.isRunning) return;
        _stepWatch.stop();
        _frameTimes.observe(
          ++_frameTimeStep,
          _stepWatch.elapsedMicroseconds / 1e6,
        );
        _stepWatch.reset();
      }, after: <String>[ShooterPlugin.stepSystem])
      ..addSystem('dungeon.reactions', LoopPhase.animate, (LoopContext frame) {
        // What the reactions plugin decided from the frame's events, on the
        // frame they happened in.
        _effects.show(
          _reactions.plugin.drain(),
          _particles,
          _system.screenFlash,
        );
      })
      ..addSystem('dungeon.elements', LoopPhase.animate, (LoopContext frame) {
        _stepElements(frame.realDt);
      })
      ..addSystem('dungeon.visuals', LoopPhase.animate, (LoopContext frame) {
        // Once a frame, not once a step: this is display, and the simulation
        // does not care where the capsules are. **With the loop's alpha**,
        // so a monster is drawn between the two steps either side of this
        // frame rather than where the later one left it — which is what the
        // player's own camera has always done, and what every monster in the
        // crypt was not doing. Asked for their rings as well, which the
        // engine reads only while the high-contrast look is on — so they are
        // set whether or not it is.
        _actorVisuals
          ?..outlineOf ??= _rings.actor
          ..sync(frame.alpha);
        _fixtureVisuals?.outlineOf ??= _rings.fixture;
        // The monsters' graphs are stepped by the simulation and this draws
        // the pose the last step left; what it still plays on the frame's
        // own clock is a model with no graph, naming its clips, and the
        // corpses falling.
        _actorVisuals?.animate(frame.realDt);
        _fixtureVisuals?.sync(_frames.elapsed);
      })
      ..addSystem('dungeon.photo', LoopPhase.camera, (LoopContext frame) {
        if (!_photo.isActive) return;
        // The paused loop drains nothing, so the look is taken here; the
        // camera is put on the node in `_placeCamera`.
        final look = Vector2.zero();
        _drainLook(look);
        _photo.fly(frame.realDt, input: _input, look: look);
      })
      ..addSystem('dungeon.overlays', LoopPhase.render, (LoopContext frame) {
        final actors = _actors;
        _renderer?.debugLines = _treesOn && actors != null
            ? BehaviorOverlay(actors).draw
            : null;
        // `wg-02`: once a frame, fire-and-forget — `WidgetSurface.tick`
        // uploads a texture only when its own pipeline is actually dirty,
        // the same budget `wg-00` measured, so a terminal nobody wrote to
        // this frame costs one boolean check.
        unawaited(_widgetSurfaces?.tickAll());
      });
  }

  /// The shooter is handed the level up now — none while there is no player
  /// to be, so nothing steps — and, before its step, the weapon held is
  /// noted. The rewind's keyframes are the loop's own captures, taken by the
  /// buffer it is attached to.
  void _beforeStep(LoopContext step) {
    final sim = _player == null ? null : _sim;
    _shooter.simulation = sim;
    // The monsters' markers onto the bus the run publishes on, which the
    // plugin has just handed its actors: in order with the shots and deaths
    // of the same step.
    final actors = _actors;
    if (actors?.strides case final ActorAnimations animations) {
      animations.events = sim == null ? null : actors?.events;
    }
    if (sim == null || step.isResimulated) return;
    _heldBefore = _arsenal.current;
  }

  /// The elements drawn one frame on, as the run's steps left them, and
  /// heard through the game's mixer. Frozen with the run under a pause, as
  /// everything drawn is.
  void _stepElements(double dt) {
    final elements = _elements;
    final player = _player;
    if (elements == null || player == null || _loop.isPaused) return;
    player.eye(_elementsEye);
    elements.update(
      dt,
      eye: _elementsEye,
      player: player.body.position,
      monsters: _actors?.actors ?? const <Actor>[],
    );
    final torches = elements.torchHeads;
    _elementSounds.play(
      _audio,
      elements.hearing,
      splashes: elements.wading,
      heldElsewhere: (Audible fire) => torches.contains(fire.key ~/ 64),
    );
  }

  /// What this game does with a step the shooter has just run.
  ///
  /// The order everything happens in belongs to `GameSimulation` now, along with
  /// the two claims about it that turned out to need measuring. What is left
  /// here is presentation: this reads what the step reports and turns it into
  /// noise, sparks and flashes, at the step's end, from [summary]'s events.
  void _afterStep(StepEventSummary summary) {
    final sim = _sim;
    final player = _player;
    if (sim == null || player == null || summary.resimulated) return;
    final dt = _loop.stepSeconds;
    final heldBefore = _heldBefore;
    // The demo's own checkpoint, taken here rather than replayed later from
    // the finished tape: recording it live is what a bug report's file needs
    // to carry, and the step number is the recorder's own, so a later replay
    // that steps the tape one entry at a time lands on the same numbering.
    //
    // Saved only on the steps the trace keeps: the run's state carries the
    // crypt's whole elements world now, a tenth of a megabyte written out,
    // and a save on every step to keep one in twenty-five was most of a
    // millisecond a step thrown away.
    if (_demoOpen) _demo?.observe(sim.save);
    // The step's events, read once here and handed to everything that wants
    // them, in the order the step published them.
    final events = summary.events.whereType<GameEvent>().toList();
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

    // A skipped cutscene's steps happen and are not shown. The run still
    // hears about them — a cutscene could end a level — and the camera still
    // follows the body, so the frame after the skip is drawn from where the
    // player is.
    if (_skipping) {
      if (_killcamPresent == null) {
        _run.observe();
        unawaited(_run.advance());
      }
      _smoothedPosition.push(player.body.position);
      return;
    }

    // A weapon can change hands inside the step — a slot key, or the last
    // round of the current one. The view model is told once, here, rather than
    // by the two places that could have caused it.
    if (!identical(_arsenal.current, heldBefore)) {
      _weaponView.selectWeapon(_arsenal.current);
    }

    // A monster's foot down, as its animation graph marks it in the step: a
    // footstep where it is, so one coming down a corridor is heard before
    // it is seen.
    for (final passed in events.whereType<AnimationMarkerPassed>()) {
      final at = passed.actor.position;
      if (passed.marker == 'step' && at != null) _audio.play(Sounds.step, at);
    }
    for (final MechanismUsed used in events.whereType<MechanismUsed>()) {
      final said = used.outcome.message;
      if (said != null) _effects.say(said);
    }

    // **What to play is decided in `Soundtrack` and only performed here.** It
    // used to be decided here too, in eight places inside a widget, where
    // nothing could ask what a step ought to sound like without a device and a
    // window — so the game being mute was undetectable, and four weapons
    // sharing two sounds went unnoticed for as long as the game has existed.
    // The events' cues are the soundtrack plugin's, played on the frame
    // channel; the footsteps and the machinery are heard here, by the step.
    _effects.perform(_soundtrack.listenStep(sim, player), _audio);

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
    final hurt = events.any((GameEvent e) => e is PlayerHurt);
    if (hurt) {
      _effects.hurt(_system.screenFlash);
    }

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
    //
    // The events' half is the reactions plugin's, decided on the frame
    // channel and shown in `dungeon.reactions`; the blasts are the
    // projectiles' own list, read here by the step that detonated them.
    _reactions.player = player;
    _effects.show(_reactions.blasts(sim), _particles, _system.screenFlash);

    // The two that are not reactions to an event. A recoil is the weapon view's
    // own animation, and the crawl is what the HUD shows and what the screen at
    // the end of the game is made of.
    //
    // **The kill count used to be a field of this widget that nothing reset.**
    // It counted every monster killed since the application was launched, which
    // is right for as long as nobody restarts and wrong from the first R. The
    // run owns it now, along with the clock, and `startFresh` empties both.
    if (events.any((GameEvent e) => e is ShotFired)) _weaponView.recoil();
    // `ls-g-01`: gated on the run, not on the application's own lifetime —
    // `_beginDemo` clears `_taughtFirstShot`, so a player restarting after
    // death is taught again, the same reason the kill count resets there
    // rather than at launch.
    final hint = firstShotHintFor(events, alreadyTaught: _taughtFirstShot);
    if (hint != null) {
      _taughtFirstShot = true;
      _effects.say(hint);
    }
    _run.run.crawl.step(
      dt,
      killed: events.whereType<ActorDied>().length,
      hurt: hurt,
    );

    final body = player.body;
    _weaponView.step(
      dt,
      speed: math.sqrt(
        body.velocity.x * body.velocity.x + body.velocity.z * body.velocity.z,
      ),
      grounded: body.isGrounded,
    );

    _effects.burnTorches(_fixtureVisuals, _particles);
    // The frame the loop accepted — see `EngineLoop.lastFrame`. This game had no
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
        // Which wall each piece was cut out of, so the walls the rocket missed
        // keep the light that was baked for them.
        origins: breaches.origins,
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
            // An edit from the editor, put in under the run: the same
            // level, changed, and the run going on in it.
            // The demo begins again from the edited level as it stands: a
            // tape recorded across an edit replays in neither level.
            _levelArrived(level, edited: _run.run.takeEdited());
            _takeEdits(level);
            _beginDemo(asset, level);
          case RunPlaying<LevelReady>(outcome: RunOutcome.lost):
            // What the player is told to do has to be something they can do:
            // on a handset there is no R, and the tap layer below the touch
            // controls is the way back in.
            _effects.say(
              _playing.touch
                  ? 'You died. Tap to try again.'
                  : 'You died. Press R to try again.',
            );
            _endDemo();
            _startKillcam();
          case RunPlaying<LevelReady>(:final level, outcome: RunOutcome.won):
            final next = level.staged.sim.nextLevel;
            _effects.say(next == null ? 'You are out.' : 'Level complete.');
            _endDemo();
          case RunPlaying<LevelReady>():
            // An outcome a later engine adds: nothing to say about it yet.
            break;
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
          // Photo mode before the settings: Escape there means "back to the
          // crypt", and the panel would take it as "open me".
          if (event is KeyDownEvent &&
              !_settings.value.isOpen &&
              !_photo.isBusy &&
              (event.logicalKey == LogicalKeyboardKey.keyP ||
                  (_photo.isActive &&
                      event.logicalKey == LogicalKeyboardKey.escape))) {
            _togglePhoto();
            return KeyEventResult.handled;
          }
          final photoSays = _photo.key(
            event,
            onCapture: (int scale) => unawaited(_takePhoto(scale)),
          );
          if (photoSays != null) {
            setState(() {});
            return photoSays;
          }
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
          // N, out of the sanctum: on into the depths, levels nobody built,
          // each made from its seed as it is reached — see `Depths`.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyN &&
              _crawlIsOut) {
            _run.run.depthsFrom = _depthsSeed;
            unawaited(_run.run.load(Depths.first(_depthsSeed)));
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
          // B shows what every monster running a behaviour tree has decided:
          // its path through the tree over its head and where it is going,
          // and the same in words in the corner. Reads the boards and
          // writes nothing, so a run watched with it on is the same run.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyB) {
            setState(() => _treesOn = !_treesOn);
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
          // browser: `_playing.capturesPointer` asks the capture backend rather
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
            if (!_playing.capturesPointer) return;
            if (_devices.isCaptured) {
              _devices.pressPointer(ShooterActions.fire);
              _pointerFiring = true;
            } else {
              _devices.captureMouse();
            }
          },
          onPointerUp: (_) {
            if (!_playing.capturesPointer) return;
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
                // Kept for the photo, which draws the same frame larger.
                settings: _frameSettings = () => RenderSettings(
                  // The player's colour vision, from the settings panel: a
                  // correction for what their eyes run together; in photo
                  // mode the filter over it, except while the picture itself
                  // is drawn, which puts the filter on its own.
                  look: _photoLook(
                    _vision?.of(_config) ?? const LookSettings(),
                  ),
                  // The high-contrast look, from the settings panel's switch
                  // or, until the player touches it, the system's own.
                  highContrast: highContrastOf(_config, _system),
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
                  // A level's own decals and mirrors, when it placed any —
                  // the cistern's still water. Each costs a pass, so only
                  // where the document asks for one.
                  decals: DecalSettings(enabled: loaded.wantsDecals),
                  planarReflections: PlanarReflectionSettings(
                    enabled: loaded.reflectors.isNotEmpty,
                  ),
                  // From the document, held at its density at the eye and
                  // lying thicker on the floor — see `cryptFog`. A crypt
                  // without fog is a crypt with a visible far wall, and the
                  // far wall is the thing an author least wants seen.
                  fog: cryptFog(
                    loaded.level,
                    eye: body.halfExtents.y + _eyeOffset,
                    on: _fogOn,
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
                presentFrame: presentFrame,
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
              if (_playing.usesDragLook)
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) {
                      _keyboard.requestFocus();
                      _dragLook.begin();
                      if (!_playing.touch) {
                        _devices.pressPointer(ShooterActions.fire);
                        _pointerFiring = true;
                      }
                    },
                    onPointerMove: (PointerMoveEvent event) =>
                        _dragLook.moved(event.delta),
                    onPointerUp: (_) {
                      _dragLook.end();
                      if (!_playing.touch) {
                        _devices.releasePointer(ShooterActions.fire);
                        _pointerFiring = false;
                      }
                    },
                    onPointerCancel: (_) {
                      _dragLook.end();
                      if (!_playing.touch) {
                        _devices.releasePointer(ShooterActions.fire);
                        _pointerFiring = false;
                      }
                    },
                  ),
                ),
              // Above the drag layer, so a thumb on a control is not also a
              // turn of the view.
              //
              // **`TouchCrypt` rather than a bare stick and row.** The shared
              // layout offered this game two buttons, which was three quarters
              // of its arsenal and the whole of its automap out of reach on a
              // phone; the file it moved to says why six controls of four
              // different kinds needed a layout of their own.
              if (_playing.touch)
                TouchCrypt(
                  state: _input,
                  arsenal: _arsenal,
                  mapOn: _mapOn,
                  onMap: () => setState(() => _mapOn = !_mapOn),
                ),
              // Above the stick in turn, and only once the run is over: R and
              // a pad's Start were the whole of the way back in, and a phone
              // has neither. Over the stick because the stick is what a thumb
              // would land on otherwise, and a dead body does not walk.
              if (_playing.touch && _runIsOver)
                TapToRestart(onRestart: () => unawaited(_run.restart())),
              SettingsOverlay(
                settings: _settings,
                sections: SettingsSection.standard(
                  // Only the sliders this game's own sounds can be heard
                  // through. `busesIn` reads the bank, so a soundtrack
                  // arriving one day brings its slider with it.
                  buses: busesIn(Sounds.all),
                  padConnected: _pad.isConnected,
                  // The map's own section: every action the shooter
                  // declares, crouch and reload among them, and what a
                  // rebind took.
                  defaultActions: shooterActionMap,
                  // **This game had no credits screen at all**, and did not
                  // need one until the monsters arrived: everything else in
                  // it is generated by a script in `tool/`.
                  credits: CreditsSection(credits: credits.models),
                  // What the HUD's colours mean, each one the player can
                  // move.
                  colors: dungeonColours,
                  // Cloud saves and sending runs, both off until answered.
                  privacy: _cloud.consents,
                ),
                opening: _openSettings,
              ),
              if (_photo.isActive) PhotoBar(mode: _photo),
              if (!_photo.isActive)
                Hud(
                  // Nothing to capture in a browser, so nothing to prompt for.
                  captured: !_playing.capturesPointer || _devices.isCaptured,
                  fps: _frames.fps,
                  steps: _steps,
                  dropped: _loop.lostSteps,
                  behind: _pace.isBehind,
                  voices: _audio.voiceCount,
                  particles: _particles.aliveCount,
                  position: body.position,
                  grounded: body.isGrounded,
                  weapon: _arsenal.current,

                  hitFlash: _effects.hitFlash,
                  painFlash: _effects.painFlash,
                  health: _playerHealth,
                  kills: _run.run.crawl.kills,
                  monstersLeft: _actors?.aliveCount ?? 0,
                  message: _effects.message,
                  messageOpacity: (_effects.messageFor / 0.6).clamp(0.0, 1.0),
                  keys: _inventory.keys,
                  armor: _playerHealth.armor,
                  ammo: _arsenal.currentAmmo,
                  pouches: <AmmoType, int>{
                    for (final type in _arsenal.carrying)
                      if (type != AmmoType.none) type: _arsenal.ammoOf(type),
                  },
                  powers: _inventory.powers,
                  keyColours: <String, Color>{
                    for (final key in _inventory.keys)
                      key: dungeonColours.colorOf(
                        'key.$key',
                        _config,
                        fallback: keyPipColours[key] ?? Colors.white70,
                      ),
                  },
                ),
              if (_sim?.cutscene case final Cutscene cutscene)
                CutsceneOverlay(
                  fade: cutscene.player.fade(alpha: _loop.alpha),
                  subtitle: cutscene.player.subtitle,
                  skipHint: _playing.touch ? 'Skip' : 'Space to skip',
                  onSkip: () => _skipAsked = true,
                ),
              if (_treesOn && _actors != null)
                Positioned(
                  left: 12,
                  top: 96,
                  child: IgnorePointer(
                    child: Text(
                      BehaviorOverlay(_actors!).describe().join('\n'),
                      key: const ValueKey<String>('behaviour-overlay'),
                      style: const TextStyle(
                        color: Color(0xFFFFD27A),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
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
              // The end of the *game*, not of a level: the sanctum is the one
              // with nowhere to go next, which the document says and this
              // widget must not guess at.
              //
              // **This was three seconds of `You are out.` over a corridor.**
              // Five levels of crypt, and the reward was a caption that faded
              // and left the crosshair up on a level with nothing left in it.
              //
              // Last in the stack, because this game draws its HUD and its map
              // after its settings panel, and a sheet placed anywhere earlier
              // would have the crosshair, the ammunition count and possibly a
              // map over it. `IgnorePointer` for the same reason the
              // platformer's `Ending` is inside one: the tap layer that starts
              // the crawl again is underneath, and a scroll view covering the
              // screen would swallow the tap.
              if (_crawlIsOut)
                IgnorePointer(
                  child: CryptEnding(
                    kills: _run.run.crawl.kills,
                    seconds: _run.run.crawl.seconds,
                    levels: _run.run.crawl.levels,
                    bestStreak: _run.run.crawl.bestStreak,
                    touch: _playing.touch,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether the steps being run are a skipped cutscene's: stepped, and not
  /// performed. See [_skipCutscene].
  bool _skipping = false;

  /// Whether a skip was asked for since the last frame.
  bool _skipAsked = false;

  /// Steps the rest of the cutscene now, through the loop — so the tape
  /// being recorded gets every step and a replay steps them all — without
  /// the noise, sparks and flashes of seconds nobody watched, which would
  /// otherwise arrive in this one frame.
  void _skipCutscene() {
    final cutscene = _sim?.cutscene;
    if (cutscene == null || _loop.isPaused) return;
    _skipping = true;
    final from = _loop.step;
    try {
      _loop.runSteps(cutscene.player.remaining);
    } finally {
      _skipping = false;
      _skipped = (from, _loop.step);
    }
  }

  /// Where the depths begin: one sequence of them for every run, so two
  /// players who went down compare the same rooms.
  static const int _depthsSeed = 1;

  /// Whether the behaviour trees are drawn. See the B key.
  bool _treesOn = false;

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

    // A cutscene with a camera of its own has the view until it ends, drawn
    // between the two steps either side of this frame like everything else.
    final fovY = _sim?.cutscene?.player.cameraAt(
      _eye,
      _target,
      alpha: _loop.alpha,
    );
    if (fovY != null) {
      _camera
        ..projection = PerspectiveProjection(fovY: fovY)
        ..setPositionFrom(_eye)
        ..lookAt(_target);
      return;
    }
    _camera.projection = const PerspectiveProjection();

    if (_photo.isActive) {
      _photo.applyTo(_camera);
      return;
    }

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
