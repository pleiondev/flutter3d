/// A third-person platformer, assembled from the engine, the genre and this
/// game's own content.
///
/// The assembly is the dungeon's, minus everything that was a shooter's: no
/// weapons, no arsenal, no monsters, no view model with its own field of view.
/// What is left is the shape every application on this stack has — a device, a
/// renderer, a loop, a level, a camera — and it is short enough to read in one
/// sitting, which the dungeon's 898 lines are not.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart'
    show DeviceOrientation, SystemChrome, SystemUiMode;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:gamepad/gamepad.dart' show PadButton;
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';
import 'src/credits.dart';
import 'src/soundtrack.dart';
import 'src/effects.dart';
import 'src/hud.dart';
import 'src/lens.dart';
import 'src/looks.dart';
import 'src/pace.dart';
import 'src/pause_gate.dart';
import 'src/reactions.dart';
import 'src/runner_looks.dart';
import 'src/save_file.dart';
import 'src/scene_surface.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'src/sounds.dart';
import 'src/staging.dart';
import 'src/title_card.dart';

void main() {
  // A phone is held the way the level is shaped, and the level is wide. Locked
  // rather than allowed to rotate, because a third-person camera reframed
  // mid-jump is a death the player did not earn.
  //
  // `ensureInitialized` because both calls below are platform channels, and a
  // channel before the binding exists is an assertion rather than an effect.
  if (Playing.touch) {
    WidgetsFlutterBinding.ensureInitialized();
    unawaited(SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]));
    // The status bar over a game is a strip of the level nobody can see, and
    // the navigation bar is a place to lose a thumb. `immersiveSticky` rather
    // than `edgeToEdge`: the bars go away and a swipe brings them back as an
    // overlay that fades, rather than pushing the game's layout about every
    // time somebody reaches for the corner.
    //
    // The comment here used to argue for `edgeToEdge` while the call said
    // `immersiveSticky`, which is worse than either being wrong — the next
    // reader trusts the sentence.
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  }
  runApp(const PlatformerApp());
}

class PlatformerApp extends StatelessWidget {
  const PlatformerApp({super.key, this.openGraphics});

  /// How to obtain the device this game draws with.
  ///
  /// **Null in the application, and the only reason it exists is that nothing
  /// could ever mount this game.** `main.dart` opened the backend its build was
  /// compiled for — `flutter_gpu` on the desktop — so a widget test had no way
  /// past the first frame, and every screen, gate and wire in this file was
  /// covered by nothing but an analyser and a pair of eyes. A test hands in a
  /// `CpuDevice`, which is a `GraphicsDevice` with no GPU under it.
  ///
  /// One field, and it changes nothing about how the game runs: an application
  /// that passes nothing gets exactly what it got before.
  final Future<GraphicsDevice> Function()? openGraphics;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Ascent',
        debugShowCheckedModeBanner: false,
        home: GameScreen(openGraphics: openGraphics),
      );
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.openGraphics});

  /// See [PlatformerApp.openGraphics].
  final Future<GraphicsDevice> Function()? openGraphics;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  /// Where a new game begins: the level that teaches the verbs.
  ///
  /// `ascent.json` is no longer the first thing a player sees — it is what
  /// `first_steps.json` names as its `next`, and the chain is authored in the
  /// documents rather than listed here. A game that keeps its own order of
  /// levels has two orders, and the second one is always the wrong one.
  static const String _firstLevel = 'assets/levels/first_steps.json';

  /// How many falls a run survives. Negative would mean "endless", which is
  /// what the package defaults to and what every test written before
  /// progression existed relies on.
  static const int _lives = 3;
  /// Who the player is looking at.
  ///
  /// **Back to the penguin.** `hero.glb` is rigged and carries eighteen clips,
  /// which is why it was picked; on screen it draws as a loose fan of triangles
  /// — four skinned meshes sharing one armature, and something between the file
  /// and this renderer does not agree about them. That is a bug worth finding,
  /// and finding it is not worth shipping an unreadable player in the meantime.
  /// The clip machinery below stays wired: a model with clips still gets them,
  /// and this one has none, so the pose is `RunnerLooks` alone — which is what
  /// it was written for.
  static const String _runnerModel = 'assets/models/penguin.glb';

  /// Which way the model faces when nothing has turned it.
  ///
  /// A number rather than a rotated asset: whichever way an exporter happened
  /// to point it is not worth re-authoring a mesh over, and the alternative —
  /// building the offset into the yaw the *simulation* holds — would make the
  /// runner's facing depend on what it is wearing.
  ///
  /// Zero, checked by walking: half a turn was the guess, and the penguin went
  /// backwards. There is no way to read this off the file — a bounding box is
  /// symmetric about the thing it contains — so it is one of the few numbers
  /// here that only somebody looking at the screen can settle.
  static const double _modelFacing = 0.0;

  final SettingsFile _settingsFile = SettingsFile(appName: 'platformer');
  late final GameConfig _config;

  final InputState _input = InputState();
  late final DesktopInput _devices;
  late final PadInput _pad;
  late final Rebinding _rebinding = Rebinding(bindings: _devices.bindings);

  AudioScene _audio = AudioScene(backend: SilentBackend());
  final AudioListener _ears = AudioListener();
  SoLoudBackend? _soloud;

  bool _showSettings = false;
  late final GameLoop _loop;
  /// Nullable, because the device may never open.
  ///
  /// It used to be `late final`, assigned only on the success path of
  /// `_openGraphics` — and `dispose` called it unconditionally. So a player who
  /// met "The renderer did not start", read it, and closed the screen got a
  /// `LateInitializationError` thrown over the top of the real error, which is
  /// the one moment a game can least afford a second failure.
  Ticker? _ticker;

  final CameraNode _camera = CameraNode(projection: Lens.base);
  late final RenderView _view;

  /// The device, for whoever needs it before it exists.
  ///
  /// **A level used to be dropped on the floor if it got here first.**
  /// `_readLevel` began `if (device == null) return;` — silently, with nothing
  /// to retry it — and the game only ever worked because opening a GPU happened
  /// to finish before `initState` reached the first load. Lose that race and the
  /// result is a black screen with no error and no way to ask why: a `flutter
  /// test` loses it every time, which is how it was found, and a cold driver or
  /// a slow machine is the same race with worse luck.
  final Completer<GraphicsDevice> _deviceReady = Completer<GraphicsDevice>();
  Renderer? _renderer;
  Object? _initError;

  /// The scene being drawn. Empty until the level arrives, and **never null**.
  ///
  /// That is the whole point of it: the renderer must get to build its frame
  /// targets before anything else has taken device memory, and waiting for the
  /// level to load meant fifteen textures were uploaded first. On this machine
  /// that combination fails to allocate — every frame, from the first — which
  /// is the same trap the runner's model fell into and is documented on
  /// `_dressRunner`.
  Scene _scene = Scene();

  LoadedLevel? _loaded;
  FixtureVisuals? _fixtures;

  /// What the player sees themselves as. A model when one loads, a box when it
  /// does not — the game is playable either way, and a missing asset should not
  /// be the difference between playing and staring at an error.
  SceneNode? _runnerNode;

  /// The clips on the runner's model, when it has any.
  AnimationPlayer? _runnerAnimation;

  /// What is playing now, so a crossfade is asked for once rather than sixty
  /// times a second.
  String? _clip;

  /// The loaded model, held so that nothing collects it out from under the
  /// scene. `FixtureVisuals` keeps its assets in a cache for the same reason.
  // ignore: unused_field
  ModelAsset? _runnerAsset;

  /// The model's own lowest point, in its local space.
  ///
  /// A body is a box about its middle; a model of somebody standing has its
  /// feet at or near the origin. The same two conventions that produced the
  /// respawn bug — reconciled every frame rather than once at load, because a
  /// crouch moves the body's middle and a fixed offset does not follow it.
  double _modelFloor = 0.0;

  /// Added to the runner's yaw, for a model that was exported facing the other
  /// way. A number rather than a re-authored mesh.
  double _runnerFacing = 0.0;

  Runner? _runner;
  PlatformerSimulation? _sim;
  FollowCamera? _followCamera;

  /// Dust, sparks and flame. One pool for the whole game, one draw call.
  final ParticleSystem _particles = ParticleSystem(capacity: 2000);

  /// How the runner is drawn, from what it is doing. See `RunnerLooks`.
  final RunnerLooks _pose = RunnerLooks();

  /// The runner's drawn position, one frame behind the simulation.
  ///
  /// Interpolated for the same reason the dungeon interpolates its camera: the
  /// step is 60 Hz and the display may not be, and a body drawn at the last
  /// step's position judders on a 120 Hz monitor even though the simulation is
  /// perfectly smooth.
  ///
  /// Replaced when a level loads, because that is when there is a runner to ask
  /// how tall a step it climbs — and the camera follows this, so a level of
  /// stairs is a level of the horizon pitching until it is smoothed.
  InterpolatedVector3 _drawnAt = InterpolatedVector3();
  final InterpolatedAngle _drawnYaw = InterpolatedAngle();

  /// Whether the machine is keeping up, and what it cost when it was not.
  final Pace _pace = Pace();

  /// Whether the player has asked to play yet, which takes the title card down.
  bool _started = false;

  /// Whether the music loop has been started. Once per session.
  bool _musicPlaying = false;

  /// Whether the run behind the title card came off the disk.
  bool _resumed = false;

  /// Why the level would not load, and which one it was.
  ///
  /// Separate from `_initError`, which is the renderer's, because the two want
  /// different words: one is a build that is missing its shaders, and this is a
  /// document somebody has just edited.
  Object? _levelError;
  String? _levelErrorAsset;

  final Vector3 _scratch = Vector3.zero();
  Duration _lastTick = Duration.zero;
  double _elapsed = 0.0;

  final SaveFile _saveFile = SaveFile();

  /// What a step sounds like. See `soundtrack.dart` for why this is a class
  /// and not a method: a decision can be tested, an effect inside a widget
  /// cannot.
  final Soundtrack _soundtrack = Soundtrack();

  /// What a step looks like. A class for the same reason [Soundtrack] is one.
  final Reactions _reactions = Reactions();

  /// The last thing the level said, and how much longer to say it for.
  ///
  /// Three seconds, and replaced rather than queued: a player who walks into a
  /// gate twice wants the second answer, not both of them in order.
  String? _said;
  double _sayFor = 0.0;

  /// Which level is being played. Written by [_loadLevel], read by the save.
  String _levelAsset = _firstLevel;

  /// Where the run was standing when it was last written to disk.
  ///
  /// A save is worth writing when the respawn point *moves* — that is what
  /// passing a checkpoint means — and at no other time. Writing every frame
  /// would put a file write in the frame budget; writing only on quit loses the
  /// whole run to a crash.
  Vector3? _savedFrom;

  /// Guards the one-way trip out of a finished run: the state stays `finished`
  /// for every frame until the next level is up, and without this each of them
  /// would start loading it.
  bool _movingOn = false;


  @override
  void initState() {
    super.initState();

    // Settings before devices: the bindings a player saved are the ones the
    // keyboard should be reading from the first key press, not from the first
    // rebind.
    _config = _settingsFile.read();
    _devices = DesktopInput(
      state: _input,
      bindings: _config.bindings.length > 0
          ? _config.bindings
          : _bindings(),
    );
    // A saved config written before the gamepad existed has no `pad:` in it, and
    // a player should not have to delete their settings to use a controller. The
    // rebindings they did make are left alone.
    if (!PadInput.knowsPad(_devices.bindings)) _padBindings(_devices.bindings);
    // One table for both devices, because a player's bindings are one file.
    _pad = PadInput(state: _input, bindings: _devices.bindings)
      ..applySettings(_config);
    _applyVolumes();
    _applyAccessibility();
    _loop = GameLoop(
      input: _input,
      onStep: _step,
      drainLook: _drainLook,
    );
    _view = RenderView(camera: _camera);
    unawaited(_openGraphics());
  }

  /// The engine's table plus this game's own two keys.
  ///
  /// The dash was already the pointer's; drop-through is control, which is
  /// where a player looks for crouch and is what it becomes when crouching
  /// exists.
  static Bindings _bindings() {
    final bindings = DesktopInput.defaultBindings()
      ..bind(
        InputSource.key(LogicalKeyboardKey.controlLeft.keyId),
        PlatformerActions.dropThrough,
      )
      ..bind(
        InputSource.key(LogicalKeyboardKey.keyC.keyId),
        PlatformerActions.dropThrough,
      );
    if (!Playing.capturesPointer) {
      // The pointer is the dash on the desktop. Anywhere else a press is
      // something else — a drag that turns the camera, or a finger — and a
      // press that also dashed would spend one on every look. So those builds
      // give the dash a key, and on a phone a button as well.
      bindings.bind(
        InputSource.key(LogicalKeyboardKey.keyQ.keyId),
        PlatformerActions.dash,
      );
    }
    return _padBindings(bindings);
  }

  /// The pad's half of the same table.
  ///
  /// The engine's defaults — the d-pad walks, the south face button jumps, the
  /// left stick clicks to sprint — plus this game's two verbs. The dash goes on
  /// the east face button, where a thumb already is; dropping through goes on
  /// the left shoulder rather than a second face button, because it is held
  /// while the other hand is doing something and a thumb cannot be in two
  /// places.
  static Bindings _padBindings(Bindings bindings) {
    return PadInput.addDefaultsTo(bindings)
      ..bind(InputSource.pad(PadButton.faceEast.id), PlatformerActions.dash)
      ..bind(
        InputSource.pad(PadButton.shoulderLeft.id),
        PlatformerActions.dropThrough,
      );
  }

  /// The mouse's motion, plus the pad's.
  ///
  /// Two devices and one callback: `DesktopInput` assigns and `PadInput` adds,
  /// in that order, so moving both at once turns the view by the sum rather than
  /// by whichever ran last.
  void _drainLook(Vector2 out) {
    _devices.drainLook(out);
    _pad.drainLook(out);
  }

  /// Mouse motion picked up from a drag, for a build with no pointer lock.
  ///
  /// Drained rather than read, and zeroed on the way out, because the loop asks
  /// for the motion *since the last step* — leaving it in place would turn one
  /// flick of the mouse into a camera that keeps turning.
  /// Held so the keyboard can be given back after a click.
  ///
  /// The web build draws through a platform view, and clicking one moves the
  /// browser's focus to the canvas element — after which Flutter sees no key
  /// events at all and the game looks frozen while its clock keeps running.
  /// `autofocus` only covers the first frame.
  final FocusNode _keyboard = FocusNode(debugLabel: 'game');

  final Vector2 _dragLook = Vector2.zero();
  bool _dragging = false;

  /// Takes the drag accumulated since the last frame.
  ///
  /// Read by the camera rather than handed to [GameLoop], and the reason is
  /// worth knowing: the loop gives its delta to [InputState], and `endStep`
  /// clears that at the end of every step — so by the time a frame draws, the
  /// motion has already been thrown away. On the captured-pointer path the
  /// simulation is the only reader and that is fine; here the camera is.
  Vector2 _takeDragLook() {
    final taken = _dragLook.clone();
    _dragLook.setZero();
    return taken;
  }

  Future<void> _openGraphics() async {
    final GraphicsDevice device;
    try {
      // Which backend this is was decided at compile time by
      // `src/backend.dart`. The size is ignored by a backend that sizes itself
      // per frame, and is the canvas for one that does not.
      device = await (widget.openGraphics?.call() ??
          openDevice(width: kRenderWidth, height: kRenderHeight));
    } catch (error) {
      // Told to whoever is waiting as well, or a level load blocks for ever on
      // a device that is never coming.
      if (!_deviceReady.isCompleted) _deviceReady.completeError(error);
      if (mounted) setState(() => _initError = error);
      return;
    }
    if (!mounted) return;
    if (!_deviceReady.isCompleted) _deviceReady.complete(device);

    setState(() {
      try {
        _renderer = Renderer.create(
          device: device,
          fallbackAlbedo: SolidColorTexture.white.upload(device),
          fallbackNormal: SolidColorTexture.flatNormal.upload(device),
        );
        // One pool, one draw call, added once. Everything this game throws
        // into the air goes through it.
        _renderer?.addContributor(ParticleContributor(_particles));
      } catch (error) {
        _initError = error;
      }
    });

    _ticker = createTicker(_onTick)..start();

    // A run in progress beats a fresh one, and the file says which level it was
    // in — see `SaveFile`, which refuses to hand back a snapshot without one.
    final saved = _saveFile.read();
    _resumed = saved != null;
    unawaited(
      saved == null
          ? _loadLevel(_firstLevel)
          : _loadLevel(saved.level, resume: saved.run),
    );
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
    _audio = AudioScene(backend: backend, mixer: _audio.mixer);
    await _audio.preload(Sounds.all);
    _startMusic();
  }

  /// Starts the loop, once, whichever of the two arrives second.
  ///
  /// The audio device and the first level open in parallel and either may win,
  /// so both call this and the flag decides. Once only: a looping sound played
  /// twice is the same sound out of phase with itself.
  void _startMusic() {
    if (_musicPlaying || _sim == null || _soloud == null) return;
    _musicPlaying = true;
    // Position is immaterial — the track carries [NoAttenuation] — and the
    // listener is where a sound with no place in the world belongs.
    _audio.play(Sounds.music, _ears.position);
  }

  /// Copies the saved volumes into the mixer the scene is reading.
  void _applyVolumes() {
    for (final bus in <AudioBus>[AudioBus.master, AudioBus.music, AudioBus.sfx]) {
      _audio.mixer.setVolume(bus, _config.volumeOf(bus.name));
    }
  }

  void _setVolume(AudioBus bus, double volume) {
    setState(() {
      _audio.mixer.setVolume(bus, volume);
      _config.setVolume(bus.name, volume);
    });
    _settingsFile.write(_config);
  }

  /// Everything that has to happen before a settings panel is on screen.
  ///
  /// Letting the mouse go, because a panel you cannot point at has no way out of
  /// it — and **letting go of the keys**, which used to happen only as a side
  /// effect of releasing the pointer. On the web and on a phone there is no
  /// pointer to release, so a key held as the panel opened stayed held, and
  /// closing the panel sent the runner walking off on their own.
  void _openSettings() {
    unawaited(_devices.release());
    _input.clear();
  }

  /// What a player can move, in the order the panel lists it.
  ///
  /// The game's list rather than the engine's `GameAction.common`: this one has
  /// a dash and a drop-through in it, and a screen that could not rebind those
  /// two would be a screen that could not rebind the moves the levels ask for.
  static const List<GameAction> _rebindable = <GameAction>[
    GameAction.moveForward,
    GameAction.moveBack,
    GameAction.moveLeft,
    GameAction.moveRight,
    GameAction.jump,
    GameAction.sprint,
    PlatformerActions.dash,
    PlatformerActions.dropThrough,
    GameAction.use,
  ];

  /// Takes a control the player has just offered for the waiting action.
  ///
  /// Saves immediately: a rebinding that survived only until the next launch
  /// would be worse than none, because a player would set it, believe it, and
  /// find out during a run.
  bool _capture(InputSource source) {
    if (!_rebinding.capture(source)) return false;
    setState(() {});
    _settingsFile.write(_config);
    return true;
  }

  /// Puts the accessibility settings where they take effect.
  ///
  /// Called after the config is read and again whenever a slider moves, because
  /// **an accommodation a player cannot feel while setting it cannot be set**:
  /// how much camera movement is too much is a question you answer by moving the
  /// slider and looking, not by reading a number and relaunching.
  void _applyAccessibility() {
    // The system answer is the **default**, not an override: somebody who turned
    // reduce-motion on years ago should not have to find the slider, and
    // somebody who has moved the slider should not be argued with.
    _followCamera?.motion =
        _config.settingOf('a11y.cameraMotion', _system.cameraMotion);
    _input.setToggled(
      GameAction.sprint,
      toggled: _config.settingOf('a11y.toggleSprint', 0.0) >= 0.5,
    );
  }

  /// Records a number that is not a volume, and acts on it at once.
  ///
  /// Applied before it is written, because the point of a dead-zone slider is
  /// that the player moves it and feels the stick change — a setting that took
  /// effect on the next launch could not be chosen at all.
  void _setSetting(String name, double value) {
    setState(() {
      _config.setSetting(name, value);
      _pad.applySettings(_config);
      _applyAccessibility();
    });
    _settingsFile.write(_config);
  }

  /// Loads [asset], and shows why if it cannot.
  ///
  /// **A level that will not read used to be a black screen for ever.** There
  /// was no `catch` here at all and `_initError` covers only the device and the
  /// renderer, so a malformed document, a missing texture or a save naming a
  /// level that no longer exists left the game drawing nothing, saying nothing,
  /// and offering nothing to do about it. Every one of those is a *content*
  /// mistake — the failure a person editing a level makes, which is to say the
  /// most likely failure this game has.
  /// What a run has come to so far, carried from one level into the next.
  ///
  /// **Three lives used to mean three lives per level**, and the clock on the
  /// summit read as the time for the last climb: every level built a fresh
  /// simulation with the constant, and the tally of the run before it went
  /// nowhere. A run spans levels and a simulation does not — only this file
  /// knows what the level after this one is, so only this file can carry it.
  ///
  /// Null for a run that is starting. Cleared when one ends, either way.
  ({int lives, int deaths, double elapsed, int coins})? _carried;

  Future<void> _loadLevel(String asset, {Snapshot? resume}) async {
    try {
      await _readLevel(asset, resume: resume);
    } catch (error, trace) {
      debugPrint('level: could not load $asset: $error\n$trace');
      // A device that never opened is reported as itself, once, by
      // `_openGraphics` — not a second time here as a level that would not load.
      if (mounted && _initError == null) {
        setState(() {
          _levelError = error;
          _levelErrorAsset = asset;
        });
      }
    }
  }

  /// The seam where the engine, the genre and this game's content meet.
  ///
  /// [asset] is which level; [resume] is a run to put back into it, which is
  /// only ever a snapshot saved from *this* level — [SaveFile] refuses to hand
  /// over one from another.
  Future<void> _readLevel(String asset, {Snapshot? resume}) async {
    // Waited for rather than given up on — see [_deviceReady].
    final device = await _deviceReady.future;
    if (!mounted) return;
    _levelAsset = asset;
    _levelError = null;
    // A load takes far longer than a frame and drops simulated time every time.
    // Counting that against the machine would light the slow-machine warning on
    // every level of every run, which is the same as not having one.
    _pace.reset(_loop.clock.droppedSteps);

    // One registry validates the document and then spawns it — see `stage`,
    // which is where the rest of this used to be written out longhand, in this
    // file and in four test harnesses that each had their own copy.
    final kinds = platformerRegistry();
    final loaded = await LevelLoader().load(
      asset,
      device: device,
      registry: kinds,
      rules: platformerRules(),
    );
    if (!mounted) return;

    final fixtures = FixtureVisuals(
      loaded.scene,
      loaded,
      appearance: const PlatformerLooks(),
      device: device,
    )..bindLights();

    final staged = stage(
      loaded.level,
      loaded.collision,
      input: _input,
      registry: kinds,
      onFixture: fixtures.add,
      coins: _carried?.coins ?? 0,
      lives: _carried?.lives ?? _lives,
      deaths: _carried?.deaths ?? 0,
      elapsed: _carried?.elapsed ?? 0.0,
    );
    final runner = staged.runner;

    // A box now, the model when it arrives. `FixtureVisuals` does the same for
    // a modelled fixture, and doing it any other way is what turned out to
    // matter: awaiting the model here puts it in the scene before the renderer
    // has ever built its frame targets, and on this machine that combination
    // fails to allocate them — every frame, from the first.
    final node = _boxRunner(device, loaded.scene, runner);

    setState(() {
      _loaded = loaded;
      _scene = loaded.scene;
      _fixtures = fixtures;
      _runnerNode = node;
      _runner = runner;
      _sim = staged.sim;
      _followCamera = FollowCamera(world: loaded.collision);
      // A camera is built per level, so the setting has to be put back on it.
      _applyAccessibility();
      unawaited(_dressRunner(device, loaded.scene, runner));
      _drawnAt = InterpolatedVector3(
        initial: runner.body.position,
        stepLimit: runner.body.tuning.stepHeight,
      );
      _drawnYaw.jumpTo(runner.yaw);
    });

    // After the scene is built rather than during it: `restore` moves bodies
    // and re-indexes the broadphase, and doing that while the fixtures are
    // still being added would leave the grid describing a world that has since
    // changed.
    if (resume != null) {
      _sim?.restore(resume);
      _followCamera?.cut();
      _drawnAt.jumpTo(runner.body.position);
    }
    _savedFrom = null;
    _soundtrack.reset();
    // The other of the two racers: the device may have opened before there was
    // anything to play under.
    _startMusic();
  }

  /// Writes the run out when it has reached somewhere new to come back to.
  void _keepSaved() {
    final sim = _sim;
    if (sim == null) return;
    final at = sim.respawnPoint;
    if (_savedFrom != null && _savedFrom!.distanceToSquared(at) < 1e-6) return;
    _savedFrom = at.clone();
    _saveRun();
  }

  /// Puts the run on disk. Called on a checkpoint and when the window closes.
  ///
  /// Cheap enough to do on every checkpoint and nowhere near cheap enough to do
  /// every frame, which is what `_sinceSaved` is for.
  void _saveRun() {
    final sim = _sim;
    if (sim == null) return;
    if (sim.state == RunState.finished || sim.state == RunState.lost) return;
    _saveFile.write(_levelAsset, sim.save());
  }

  /// What happens when a level is finished or a run is lost.
  ///
  /// Finished with somewhere to go loads it; finished with nowhere to go and
  /// lost both stop, and the save is cleared either way — a run that has ended
  /// is not one to resume into.
  void _endOfRun() {
    final sim = _sim;
    if (sim == null || _movingOn) return;
    if (sim.state != RunState.finished && sim.state != RunState.lost) return;

    _movingOn = true;
    _saveFile.clear();
    final next = sim.state == RunState.finished ? sim.nextLevel : null;
    if (next == null) {
      // The run is over, whichever way. The next one starts from nothing.
      _carried = null;
      return;
    }
    _carried = (
      lives: sim.lives,
      deaths: sim.deaths,
      elapsed: sim.elapsed,
      coins: _runner?.purse['coin'] ?? 0,
    );

    // A beat on the results screen before the next level: arriving in a new
    // place in the same frame the last one ended reads as a glitch.
    Future<void>.delayed(const Duration(milliseconds: 1400), () async {
      if (!mounted) return;
      await _loadLevel(next);
      if (mounted) _movingOn = false;
    });
  }

  /// What the pad means to a screen rather than to the runner.
  ///
  /// Two things the simulation has no verb for: taking down the title card, and
  /// starting over once the run is finished. Read as edges here rather than
  /// bound to invented actions, so the binding table holds only words the game
  /// logic actually reads.
  void _padScreenButtons() {
    final pressing = _pad.heldButtons.isNotEmpty;
    final wasPressing = _padPressing;
    _padPressing = pressing;
    if (!pressing || wasPressing) return;

    // A pad button offered to a waiting rebinding, so a controller can be
    // remapped from the controller rather than from the keyboard — which is the
    // whole point for a player who has only one of the two.
    if (_rebinding.waitingFor != null) {
      _capture(InputSource.pad(_pad.heldButtons.first.id));
      return;
    }

    // Any button begins, which is also how a browser reveals the pad to the
    // page in the first place: it stays invisible until one is pressed.
    if (!_started) {
      _begin();
      return;
    }
    if (_runIsOver && _pad.heldButtons.contains(PadButton.start)) _restart();
  }

  /// Whether the pad was holding anything last frame, for the edge above.
  bool _padPressing = false;

  /// What the player has already told the operating system.
  Accommodations _system = const Accommodations();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Here rather than in `initState`, because this is the one place a
    // `MediaQuery` is guaranteed to exist and to be re-read when it changes —
    // and it does change: a player can turn reduce-motion on without leaving
    // the game.
    _system = Accommodations.of(context);
    _applyAccessibility();
  }

  /// Takes the title card down, the first time the player asks to play.
  ///
  /// Once per session and never again: a card that comes back every time the
  /// pointer is released is a card in the middle of a run.
  void _begin() {
    if (_started) return;
    // **The audio starts here rather than at launch**, and that is the browser's
    // rule rather than a preference: a page may not make a sound until the
    // player has done something, and a build that opened its audio in
    // `initState` spent that permission before the player had given it — so the
    // first sound of the game was the one that got refused. This is the first
    // click, touch or pad button in every build, which is exactly the gesture
    // the browser is waiting for.
    unawaited(_openAudio());
    setState(() => _started = true);
  }

  /// Whether the run has ended and nothing else is going to happen.
  ///
  /// Finishing a level that *has* a next one is not over: the game is about to
  /// load it, and a restart during that beat would throw away a level the
  /// player has just won.
  bool get _runIsOver {
    final sim = _sim;
    if (sim == null) return false;
    if (sim.state == RunState.lost) return true;
    return sim.state == RunState.finished && sim.nextLevel == null;
  }

  /// Starts the run over, from the top of the level being played.
  void _restart() {
    _saveFile.clear();
    // A new run, not a continuation of the one that ended.
    _carried = null;
    _movingOn = false;
    unawaited(_loadLevel(_levelAsset));
  }

  /// Back to the beginning, from a level that would not load.
  ///
  /// Not [_restart], which reloads the level that has just failed: the saved
  /// level is the usual reason a run cannot be resumed, so the only thing that
  /// helps is throwing the save away and going back to the first one.
  void _startOver() {
    _saveFile.clear();
    _movingOn = false;
    setState(() {
      _levelError = null;
      _levelErrorAsset = null;
    });
    unawaited(_loadLevel(_firstLevel));
  }

  /// A box, right away, so the game can be played while the model loads.
  SceneNode _boxRunner(GraphicsDevice device, Scene scene, Runner runner) {
    final box = MeshNode(
      SharedMeshes(device).box(runner.body.halfExtents * 2.0),
      Material(
        name: 'runner',
        baseColor: Vector4(0.90, 0.42, 0.28, 1.0),
        lighting: LightingModel.pbr,
      )..roughness = 0.5,
      name: 'runner box',
    );
    scene.add(box);
    return box;
  }

  /// Swaps the box for the model once it has been read and uploaded.
  ///
  /// **Not awaited before the first frame, and that is the whole point.** The
  /// model in the scene before the renderer has ever built its frame targets is
  /// the arrangement that fails here: `_ensureTargets` cannot allocate, every
  /// frame, from the first, and the picture is an error screen. The same file
  /// through `FixtureVisuals` is fine, and the difference is that a modelled
  /// fixture arrives *after* the frames have started — so this does too.
  ///
  /// The asset is authored at the size the game wants (`tool/prepare_models.py`
  /// bakes the scale into its root), so there is no scale set at load either —
  /// what `setScale` carries is the pose, and nothing else.
  Future<void> _dressRunner(
    GraphicsDevice device,
    Scene scene,
    Runner runner,
  ) async {
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: const BundleAssetSource(_runnerModel)),
      );
      final asset = await ModelAsset.fromDocument(
        document,
        device: device,
        fallbackAlbedo: SolidColorTexture.white.upload(device),
        name: _runnerModel,
      );
      // **`mounted` is not enough, and the gap is a whole level.** Reading and
      // uploading eighteen clips takes long enough that the player can finish
      // the level, die into a reload, or press restart while it is happening —
      // and every one of those builds a new scene and a new runner, leaving
      // this call holding the old pair. The widget is still mounted, so the
      // model went into a scene nobody draws, `_runnerNode` was pointed at it,
      // and `_runnerAnimation` drove it: the level being played kept the
      // orange box it started with, permanently, and the pose logic ran
      // against a node in the dark.
      //
      // Compared by identity against the scene the game is showing, because
      // that is what `setState` at the end of `_readLevel` swaps — one field,
      // written in the same batch as the runner this was given.
      if (!mounted || !identical(scene, _scene)) return;

      final instance = asset.instantiate(scene, name: 'runner');
      final box = _runnerNode;
      setState(() {
        _runnerAsset = asset;
        _runnerNode = instance.root;
        // **The line three stages of this game were waiting for.** The player
        // has always been built by `instantiate` when the model has clips; the
        // penguin had none, so it was thrown away and nobody noticed. This one
        // has eighteen.
        _runnerAnimation = instance.player;
        _modelFloor = asset.localBounds.min.y;
        _runnerFacing = _modelFacing;
      });
      if (box != null) scene.remove(box);
    } catch (error) {
      debugPrint('runner: could not load $_runnerModel, staying a box ($error)');
    }
  }

  void _onTick(Duration now) {
    final dt = _lastTick == Duration.zero
        ? 1.0 / 60.0
        : (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;
    _elapsed += dt;

    // Paused whenever the mouse is not ours: a game that keeps running behind
    // a menu is a game that kills the player while they are reading it.
    // Paused whenever the mouse is not ours: a game that keeps running
    // behind a menu is a game that kills the player while they are reading
    // it. There is no pointer to own in a browser, so there the gate is
    // only whether the level has loaded.
    // Before the loop, so the frame that reads the pad is the frame it moves in.
    _pad.tick(dt);
    _padScreenButtons();

    // Four facts and no devices — see `pause_gate.dart`, which carries the three
    // ways this line has been wrong and a test for each.
    _loop.paused = shouldPause(
      ready: _sim != null,
      menuOpen: _showSettings,
      pointerIsTheGate: Playing.capturesPointer,
      pointerHeld: _devices.isCaptured,
      padConnected: _pad.isConnected,
    );
    _loop.advance(dt.clamp(0.0, 0.25));
    // The loop has always counted the simulated time it could not run. Nobody
    // read it, so a machine that could not keep up ran the game slowly and said
    // nothing about it.
    _pace.note(
      dropped: _loop.clock.droppedSteps,
      dt: dt,
      stepSeconds: _loop.clock.stepSeconds,
    );

    if (_sayFor > 0.0) {
      _sayFor -= dt;
      if (_sayFor <= 0.0) _said = null;
    }
    _particles.advance(dt);
    _animateRunner(dt);
    _placeCamera(dt);
    _fixtures?.sync(_elapsed);
    _burnLamps();
    _keepSaved();
    _endOfRun();
    if (mounted) setState(() {});
  }

  /// One simulation step. Nothing here draws.
  void _step(double dt) {
    final sim = _sim;
    final runner = _runner;
    final camera = _followCamera;
    if (sim == null || runner == null || camera == null) return;

    // The camera owns "forward", and the simulation takes it as a number.
    sim.cameraYaw = camera.yaw;
    sim.step(dt);
    _react(sim, runner);

    if (sim.diedThisStep) {
      // A cut rather than a chase: easing from where they died to where they
      // came back is a second of the level flying past for no reason.
      camera.cut();
      _drawnAt.jumpTo(runner.body.position);
    } else {
      _drawnAt.push(
        runner.body.position,
        dt: dt,
        steppedUp: runner.body.steppedUp,
      );
    }
    _drawnYaw.push(runner.yaw);
  }

  /// Picks the runner's clip and advances it.
  ///
  /// Once a frame rather than once a step, because this is presentation: the
  /// simulation runs at sixty hertz and the animation should run at whatever
  /// the display does. The state machine itself is `RunnerClips.forRunner`,
  /// which is a pure function and tested as one.
  void _animateRunner(double dt) {
    final player = _runnerAnimation;
    final runner = _runner;
    if (player == null || runner == null) return;

    final wanted = RunnerClips.forRunner(runner);
    if (wanted != _clip) {
      // A short fade, and shorter still into a jump: a quarter of a second of
      // blending into a take-off is a quarter of a second of the runner still
      // standing there while the body is already in the air.
      player.crossFadeToNamed(
        wanted,
        duration: wanted == RunnerClips.jump ? 0.06 : 0.14,
      );
      _clip = wanted;
    }

    final speed = math.sqrt(
      runner.body.velocity.x * runner.body.velocity.x +
          runner.body.velocity.z * runner.body.velocity.z,
    );
    player
      ..speed = RunnerClips.rateFor(wanted, speed)
      ..update(dt);
  }

  /// Keeps every lamp's flame alight.
  ///
  /// Restated every frame rather than started once, because that is what
  /// `ParticleSystem.emit` wants: a rate that is not restated goes out, which
  /// is how a torch that was destroyed stops smoking without anybody telling
  /// it to.
  void _burnLamps() {
    final flames = _fixtures?.flames;
    if (flames == null) return;
    for (final MapEntry<LightFixture, TorchFire> lamp in flames.entries) {
      final fire = lamp.value;
      _particles.emit(
        fire,
        Effects.flame,
        fire.originInto(_flameAt),
        perSecond: 34.0 * lamp.key.brightness,
        direction: _up,
      );
    }
  }

  static final Vector3 _up = Vector3(0.0, 1.0, 0.0);
  final Vector3 _flameAt = Vector3.zero();

  /// Turns a step's events into sound and spectacle. Nothing here decides.
  ///
  /// Both halves are somebody else's: `Soundtrack` says what a step sounds
  /// like and `Reactions` says what it looks like, because a decision inside a
  /// widget needs a device, a renderer and a window to ask about — and this
  /// game shipped mute, and then shipped without a particle for a collected
  /// coin, with nothing red either time.
  void _react(PlatformerSimulation sim, Runner runner) {
    final camera = _followCamera;

    for (final Heard heard in _soundtrack.listen(sim, runner)) {
      _audio.play(heard.sound, heard.at);
    }

    // What the level said. It has been saying things since the engine had
    // signals, into a list this game never drained.
    for (final String said in sim.saidThisStep) {
      _said = said;
      _sayFor = 3.0;
    }

    // Everything the step showed, decided in `Reactions` and only performed
    // here — the same split as the sound above, and for the same reason: what
    // a coin looks like when it is taken was a private method of a widget
    // nothing can mount, so nothing checked that it looked like anything.
    final reaction = _reactions.listen(sim, runner);
    for (final Shown shown in reaction.bursts) {
      _particles.burst(shown.effect, shown.at, direction: shown.direction);
    }
    if (camera != null) {
      for (final Felt felt in reaction.jolts) {
        felt.applyTo(camera);
      }
    }
  }

  void _placeCamera(double dt) {
    final camera = _followCamera;
    final node = _runnerNode;
    if (camera == null || node == null) return;

    // A captured pointer reports through the loop; a drag reports here.
    // A captured pointer reports through the loop; a drag reports here.
    camera.look(Playing.dragLook ? _takeDragLook() : _input.lookDelta);
    _drawnAt.read(_loop.alpha, _scratch);
    // The way the runner is *going*, so the camera drifts round behind them
    // over a long level instead of having to be steered by hand at every
    // corner. Velocity rather than facing: a runner sliding backwards off a
    // ledge is going one way and looking another, and the camera should show
    // where they are about to land.
    camera.follow(_scratch, dt, travelling: _runner?.body.velocity);

    // The pose: squash, stretch, lean, and the flip a double jump turns. Built
    // from what the runner did this step and applied here, because this is the
    // one place that draws.
    final runner = _runner;
    if (runner != null) _pose.advance(runner, dt);
    final scale = _pose.scale;

    // Placed by its feet rather than by a fixed drop from the body's centre.
    // A crouching body's centre falls by half of what the body lost, so a fixed
    // drop buries the model in the floor for exactly as long as the crouch —
    // see `RunnerLooks.drawnHeight`, which is where the arithmetic is tested.
    final feet = runner == null
        ? _scratch.y
        : _pose.drawnHeight(
            bodyY: _scratch.y,
            halfHeight: runner.body.halfExtents.y,
            modelFloor: _modelFloor,
          );

    node
      ..setPosition(_scratch.x, feet, _scratch.z)
      ..setScale(scale.x, scale.y, scale.z)
      ..setRotation(
        Quaternion.axisAngle(
              Vector3(0.0, 1.0, 0.0),
              _drawnYaw.read(_loop.alpha) + _runnerFacing + _pose.spin,
            ) *
            Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), _pose.lean) *
            Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), _pose.roll),
      );

    // Speed widens the view a little, which is the cheapest way to make fast
    // feel fast. Read off the drawn body rather than the simulated one so it
    // moves at the display's rate.
    if (runner != null) {
      final speed = runner.body.velocity.length;
      if (speed > 9.0) camera.widen(((speed - 9.0) / 14.0).clamp(0.0, 0.12));
    }

    _camera
      ..setPositionFrom(camera.eye)
      ..lookAt(camera.target)
      ..projection = Lens.widened(camera.extraFov);

    // Along the camera's own forward rather than through a yaw: `aimAt` reads
    // an angle as a first-person camera's, and this one is not.
    _ears.aimAlong(camera.eye, camera.target - camera.eye);
    _audio.update(_ears);
  }

  @override
  void dispose() {
    _saveRun();
    _audio.stopAll();
    unawaited(_soloud?.dispose());
    _keyboard.dispose();
    _ticker?.dispose();
    unawaited(_devices.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _initError;
    if (error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'The renderer did not start.\n\n$error\n\n'
              'The shader bundle is built by '
              'packages/flutter3d_impeller/tool/build_shaders.sh and is not '
              'in the repository.',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    final levelError = _levelError;
    if (levelError != null) {
      return LevelErrorScreen(
        asset: _levelErrorAsset ?? _levelAsset,
        error: levelError,
        onStartOver: _startOver,
      );
    }

    final renderer = _renderer;
    if (renderer == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final scene = _scene;
    final sim = _sim;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _keyboard,
        autofocus: true,
        onKeyEvent: (_, KeyEvent event) {
          // R starts a finished run over. Handled here rather than through a
          // binding because it is not a verb the runner has: the simulation it
          // would be asking is the one that has stopped.
          //
          // **Both ways a run ends, not just the losing one.** A player who
          // reached the summit was offered nothing at all and had to quit the
          // application to climb it again.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyR &&
              _runIsOver) {
            _restart();
            return KeyEventResult.handled;
          }
          // A rebinding takes the next key, before anything else looks at it —
          // including Escape below, which is how a player says "not that one".
          if (event is KeyDownEvent && _rebinding.waitingFor != null) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              setState(_rebinding.cancel);
            } else {
              _capture(InputSource.key(event.logicalKey.keyId));
            }
            return KeyEventResult.handled;
          }
          // Escape opens the settings, which the title card has been promising
          // and nothing was doing. Before `DesktopInput` sees it, because that
          // is where Escape gives the pointer back, and giving it back is half
          // of what opening a panel means: a settings panel you cannot point at
          // has no way out of it.
          //
          // Only once the game has started. The title card carries the same
          // credits and is the one screen a panel over the top of it adds
          // nothing to.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              _started) {
            if (!_showSettings) _openSettings();
            setState(() => _showSettings = !_showSettings);
            return KeyEventResult.handled;
          }
          // **With the panel open the keys belong to the panel.** Handing them
          // to the game costs two things at once: Flutter's focus traversal
          // never sees Tab or the arrows, so a player with no mouse cannot
          // reach a slider at all — and a key held as the panel opened stays
          // held in the `InputState`, so closing it sends the player walking
          // off on their own.
          if (_showSettings) return KeyEventResult.ignored;
          return _devices.handleKeyEvent(event);
        },
        child: Listener(
          // Desktop only. The web build reads its pointer from the layer
          // above the platform view — see the stack below — and handling it
          // here as well doubled every look delta.
          onPointerDown: (_) {
            _keyboard.requestFocus();
            _begin();
            if (!Playing.capturesPointer) return;
            _devices.pressPointer(PlatformerActions.dash);
            if (!_devices.isCaptured) unawaited(_devices.captureMouse());
          },
          onPointerUp: (_) {
            if (!Playing.capturesPointer) return;
            _devices.releasePointer(PlatformerActions.dash);
          },
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              SceneSurface(
                renderer: renderer,
                scene: scene,
                view: _view,
                fog: FogSettings(
                  color: _loaded?.level.fogColor ?? Vector3(0.05, 0.07, 0.12),
                  density: _loaded?.level.fogDensity ?? 0.0,
                ),
                onBeforeFrame: () {},
              ),
              // The web build draws into a platform view, and a platform view
              // takes every pointer event over it — the `Listener` outside this
              // stack never sees the drag that turns the camera. A transparent
              // layer *above* the view does, because it is an ordinary Flutter
              // widget again. Nothing below it is interactive, so opaque hit
              // testing costs nothing.
              if (Playing.dragLook)
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) {
                      _keyboard.requestFocus();
                      _begin();
                      _dragging = true;
                    },
                    onPointerMove: (PointerMoveEvent event) {
                      if (!_dragging) return;
                      _dragLook.add(Vector2(event.delta.dx, event.delta.dy));
                    },
                    onPointerUp: (_) => _dragging = false,
                    onPointerCancel: (_) => _dragging = false,
                  ),
                ),
              // Not behind the title card: the tallies and its own "Click to
              // play" banner showed through it, saying the same thing twice
              // and counting a run the player has not started.
              if (sim != null && _started)
                Hud(
                  coins: _runner?.purse['coin'] ?? 0,
                  deaths: sim.deaths,
                  lives: sim.lives,
                  elapsed: sim.elapsed,
                  state: sim.state,
                  // Nothing to capture in a browser, so nothing to prompt for.
                  captured: !Playing.capturesPointer || _devices.isCaptured,
                  levelName: _loaded?.level.name ?? '',
                  keys: _runner?.keys ?? const <String>{},
                  message: _said,
                  behind: _pace.behind,
                  lost: _pace.lost,
                  // The end of the *game*, not of a level: the last level is
                  // the one with nowhere to go next, which the document says
                  // and this widget must not guess at.
                  finale: sim.nextLevel == null,
                ),
              // Above the drag layer on purpose: a widget higher in the stack
              // takes the pointers that land on it, so a thumb on the stick is
              // never also a turn of the camera. Everything the drag layer
              // still sees is screen the controls are not on.
              if (Playing.touch && _started && !_showSettings)
                TouchControls(
                  state: _input,
                  buttons: const <TouchAction>[
                    TouchAction(PlatformerActions.dropThrough, 'drop'),
                    TouchAction(PlatformerActions.dash, 'dash'),
                    TouchAction(GameAction.jump, 'jump'),
                  ],
                ),
              if (!_started)
                TitleCard(
                  prompt: Playing.touch
                      ? 'Touch to begin.'
                      : Playing.capturesPointer
                          ? 'Click to take the mouse, or press a button on the '
                              'pad.'
                          : 'Click to begin, or press a button on the pad.',
                  dashOnPointer: Playing.capturesPointer,
                  touch: Playing.touch,
                  resuming: _resumed,
                ),
              if (_showSettings)
                SettingsPanel(
                  mixer: _audio.mixer,
                  bindings: _devices.bindings,
                  config: _config,
                  padConnected: _pad.isConnected,
                  onVolume: _setVolume,
                  onSetting: _setSetting,
                  onClose: () {
                    // A rebinding left waiting would eat the next key press in
                    // the game, which reads as the game ignoring the player.
                    _rebinding.cancel();
                    setState(() => _showSettings = false);
                  },
                  actions: _rebindable,
                  waitingFor: _rebinding.waitingFor,
                  onRebind: (GameAction? action) => setState(() {
                    action == null
                        ? _rebinding.cancel()
                        : _rebinding.start(action);
                  }),
                  credits: const CreditsSection(),
                  onResetControls: () {
                    setState(() => _rebinding.reset(_bindings()));
                    _settingsFile.write(_config);
                  },
                )
              // Not over the title card, which carries the same settings on it
              // and is the one screen a stray gear icon has nothing to add to.
              else if (_started)
                Positioned(
                  right: 18,
                  top: 16,
                  child: IconButton(
                    onPressed: () {
                      _openSettings();
                      setState(() => _showSettings = true);
                    },
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings, color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
