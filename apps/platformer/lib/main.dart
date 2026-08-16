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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';
import 'src/soundtrack.dart';
import 'src/effects.dart';
import 'src/hud.dart';
import 'src/lens.dart';
import 'src/looks.dart';
import 'src/pace.dart';
import 'src/runner_looks.dart';
import 'src/save_file.dart';
import 'src/scene_surface.dart';
import 'src/settings_file.dart';
import 'src/settings_panel.dart';
import 'src/sounds.dart';
import 'src/title_card.dart';

void main() {
  runApp(const PlatformerApp());
}

class PlatformerApp extends StatelessWidget {
  const PlatformerApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        title: 'Ascent',
        debugShowCheckedModeBanner: false,
        home: GameScreen(),
      );
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

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

  final SettingsFile _settingsFile = SettingsFile();
  late final GameConfig _config;

  final InputState _input = InputState();
  late final DesktopInput _devices;

  AudioScene _audio = AudioScene(backend: SilentBackend());
  final AudioListener _ears = AudioListener();
  SoLoudBackend? _soloud;

  bool _showSettings = false;
  late final GameLoop _loop;
  late final Ticker _ticker;

  final CameraNode _camera = CameraNode(projection: Lens.base);
  late final RenderView _view;

  GraphicsDevice? _device;
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
  int _deathsSeen = 0;

  final SaveFile _saveFile = SaveFile();

  /// What a step sounds like. See `soundtrack.dart` for why this is a class
  /// and not a method: a decision can be tested, an effect inside a widget
  /// cannot.
  final Soundtrack _soundtrack = Soundtrack();

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
    _applyVolumes();
    _loop = GameLoop(
      input: _input,
      onStep: _step,
      drainLook: _devices.drainLook,
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
    if (kIsWeb) {
      // The pointer is the dash on desktop, and on the web it is the only way
      // to look around — a drag cannot also be a dash without every turn of
      // the camera spending one. So the web build gives the dash a key.
      bindings.bind(
        InputSource.key(LogicalKeyboardKey.keyQ.keyId),
        PlatformerActions.dash,
      );
    }
    return bindings;
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
      device = await openDevice(width: kRenderWidth, height: kRenderHeight);
    } catch (error) {
      if (mounted) setState(() => _initError = error);
      return;
    }
    if (!mounted) return;
    _device = device;

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
    unawaited(_openAudio());

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

  /// Loads [asset], and shows why if it cannot.
  ///
  /// **A level that will not read used to be a black screen for ever.** There
  /// was no `catch` here at all and `_initError` covers only the device and the
  /// renderer, so a malformed document, a missing texture or a save naming a
  /// level that no longer exists left the game drawing nothing, saying nothing,
  /// and offering nothing to do about it. Every one of those is a *content*
  /// mistake — the failure a person editing a level makes, which is to say the
  /// most likely failure this game has.
  Future<void> _loadLevel(String asset, {Snapshot? resume}) async {
    try {
      await _readLevel(asset, resume: resume);
    } catch (error, trace) {
      debugPrint('level: could not load $asset: $error\n$trace');
      if (mounted) {
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
    final device = _device;
    if (device == null) return;
    _levelAsset = asset;
    _levelError = null;
    // A load takes far longer than a frame and drops simulated time every time.
    // Counting that against the machine would light the slow-machine warning on
    // every level of every run, which is the same as not having one.
    _pace.reset(_loop.clock.droppedSteps);

    // One registry validates the document and then spawns it. Two could
    // disagree about what a document may contain, which is the failure this
    // seam was built to remove — so the crate kind is told where bodies go
    // *after* there is a world, exactly as the shooter tells its monster kind
    // where the bestiary is.
    final kinds = platformerRegistry();
    final loaded = await LevelLoader().load(
      asset,
      device: device,
      registry: kinds,
      rules: platformerRules(),
    );
    if (!mounted) return;

    final dynamics = Dynamics(world: loaded.collision);
    (kinds[PlatformerEntities.crate] as CrateKind?)?.dynamics = dynamics;

    final actors = ActorSystem(world: loaded.collision);
    final mechanisms = MechanismWorld(loaded.collision);
    final fixtures = FixtureVisuals(
      loaded.scene,
      loaded,
      appearance: const PlatformerLooks(),
      device: device,
    )..bindLights();

    loaded.level.spawnInto(
      SpawnContext(
        world: loaded.collision,
        actors: actors,
        mechanisms: mechanisms,
        onFixture: fixtures.add,
      ),
      registry: kinds,
    );

    // The authored point is where the feet go; the body is a box about its
    // middle.
    final start = loaded.level.playerStart?.position ?? Vector3.zero();
    final runner = Runner(
      body: CharacterController(
        world: loaded.collision,
        position: start + Vector3(0.0, 0.9, 0.0),
      ),
      // What this game's floors are made of. The names live in the level
      // document, on the brushes, beside the material that paints them.
      surfaces: Surfaces.common(),
    );

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
      _sim = PlatformerSimulation(
        runner: runner,
        collision: loaded.collision,
        input: _input,
        // Built since this game began and stepped by nobody, which is why a
        // platformer carrying a whole actor system had no enemies in it.
        actors: actors,
        // The authored point: feet on the floor. See Runner.reviveAt.
        startAt: start,
        mechanisms: mechanisms,
        dynamics: dynamics,
        levelNext: loaded.level.next,
        lives: _lives,
      );
      _followCamera = FollowCamera(world: loaded.collision);
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
      _deathsSeen = _sim?.deaths ?? 0;
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
    if (next == null) return;

    // A beat on the results screen before the next level: arriving in a new
    // place in the same frame the last one ended reads as a glitch.
    Future<void>.delayed(const Duration(milliseconds: 1400), () async {
      if (!mounted) return;
      await _loadLevel(next);
      if (mounted) _movingOn = false;
    });
  }

  /// Takes the title card down, the first time the player asks to play.
  ///
  /// Once per session and never again: a card that comes back every time the
  /// pointer is released is a card in the middle of a run.
  void _begin() {
    if (_started) return;
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
      if (!mounted) return;

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
    _loop.paused = _sim == null || (!kIsWeb && !_devices.isCaptured);
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
    _hear(sim, runner);

    if (sim.deaths != _deathsSeen) {
      _deathsSeen = sim.deaths;
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

  /// Turns a step's events into sounds. Nothing here decides anything.
  void _hear(PlatformerSimulation sim, Runner runner) {
    final at = runner.position;
    final camera = _followCamera;

    // **What to play is decided in `Ears` and only performed here.** It used to
    // be decided here too, inside a widget, where nothing could ask what a step
    // ought to sound like without a device and a window — so the game being
    // mute was undetectable. See `ears.dart`.
    for (final Heard heard in _soundtrack.listen(sim, runner)) {
      _audio.play(heard.sound, heard.at);
    }

    // What the level said. It has been saying things since the engine had
    // signals, into a list this game never drained.
    for (final String said in sim.saidThisStep) {
      _said = said;
      _sayFor = 3.0;
    }

    if (runner.dashedThisStep) {
      _particles.burst(Effects.dash, at);
      camera?.widen(0.1);
    }
    if (runner.wallJumpedThisStep) _particles.burst(Effects.dust, at);

    // **Three flags the runner has always set and nobody has ever read**, which
    // is the same shape of gap as the silent coin: the simulation was right and
    // the game said nothing. Each one is a moment a player commits to something
    // and deserves to be told it landed.
    if (runner.longJumpedThisStep) {
      // A long jump is a commitment — low, far, and no steering. It gets a wide
      // skirt of dust, because it is the slide it came out of, launched.
      _particles.burst(Effects.dust, at);
      camera?.widen(0.08);
    }
    if (runner.grabbedThisStep) {
      // Catching a rope or a ladder: the camera settles rather than kicking,
      // because the runner has just stopped falling.
      _particles.burst(Effects.dust, at);
    }
    if (runner.bouncedThisStep) {
      // The hop off something stomped. `sim.stompedThisStep` says an enemy
      // died; this says the runner was thrown by it, and they are not the same
      // event — a bounce off a held jump goes higher, and that is what the kick
      // is scaled by.
      camera?.kick(Vector3(0.0, 0.05, 0.0));
      _particles.burst(Effects.spring, at, direction: _up);
    }
    for (var i = 0; i < sim.takenThisStep.length; i++) {
      _particles.burst(Effects.coin, sim.takenThisStep[i].origin);
    }
    if (sim.stompedThisStep) {
      _particles.burst(Effects.slam, at);
      camera?.kick(Vector3(0.0, -0.12, 0.0));
    }
    if (sim.reachedCheckpointThisStep) {
      _particles.burst(Effects.checkpoint, at, direction: _up);
    }
    if (sim.deaths != _deathsSeen) {
      _particles.burst(Effects.death, at);
      camera?.shake(0.5, seconds: 0.4);
    }

    // Everything the level's own machinery did this step. A spring that throws
    // somebody and a shelf that gives way are both events nobody was watching
    // for until there was something to show for them.
    for (final Mechanism mechanism in sim.mechanisms?.all ?? const <Mechanism>[]) {
      if (mechanism is Spring && mechanism.firedThisStep) {
        _particles.burst(Effects.spring, mechanism.origin, direction: _up);
      }
      if (mechanism is Crumbling && mechanism.crumbledThisStep) {
        _particles.burst(Effects.crumble, mechanism.origin);
      }
      if (mechanism is Breakable && mechanism.brokeThisStep) {
        _particles.burst(Effects.slam, mechanism.origin);
      }
    }

    // Landing is an event the simulation reports now, and it reports how hard:
    // the application used to work it out from whether the runner was grounded
    // last frame, which cannot know the speed.
    if (runner.landedThisStep) {
      _audio.play(Sounds.land, at);
      _feelLanding(runner.landingSpeed, pounded: runner.poundedThisStep);
      if (runner.poundedThisStep) {
        _particles.burst(Effects.slam, at);
      } else if (runner.landingSpeed > 6.0) {
        _particles.burst(Effects.dust, at);
      }
    }
  }

  /// What a landing does to the camera. The pose is `RunnerLooks`' business.
  void _feelLanding(double speed, {required bool pounded}) {
    final camera = _followCamera;
    if (camera == null) return;
    // Below walking pace nothing happens: a camera that dips every time the
    // player steps off a kerb is a camera nobody can look at.
    if (speed < 6.0 && !pounded) return;
    final hardness = (speed / 20.0).clamp(0.0, 1.0);
    camera.kick(Vector3(0.0, -0.18 * hardness, 0.0));
    if (pounded) camera.shake(0.22, seconds: 0.3);
  }

  void _placeCamera(double dt) {
    final camera = _followCamera;
    final node = _runnerNode;
    if (camera == null || node == null) return;

    // A captured pointer reports through the loop; a drag reports here.
    // A captured pointer reports through the loop; a drag reports here.
    camera.look(kIsWeb ? _takeDragLook() : _input.lookDelta);
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
    _ticker.dispose();
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
          return _devices.handleKeyEvent(event);
        },
        child: Listener(
          // Desktop only. The web build reads its pointer from the layer
          // above the platform view — see the stack below — and handling it
          // here as well doubled every look delta.
          onPointerDown: (_) {
            _keyboard.requestFocus();
            _begin();
            if (kIsWeb) return;
            _devices.pressPointer(PlatformerActions.dash);
            if (!_devices.isCaptured) unawaited(_devices.captureMouse());
          },
          onPointerUp: (_) {
            if (kIsWeb) return;
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
              if (kIsWeb)
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
                  captured: kIsWeb || _devices.isCaptured,
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
              if (!_started)
                TitleCard(
                  prompt: kIsWeb ? 'Click to begin.' : 'Click to take the mouse.',
                  resuming: _resumed,
                ),
              if (_showSettings)
                SettingsPanel(
                  mixer: _audio.mixer,
                  bindings: _devices.bindings,
                  onVolume: _setVolume,
                  onClose: () => setState(() => _showSettings = false),
                )
              // Not over the title card, which carries the same settings on it
              // and is the one screen a stray gear icon has nothing to add to.
              else if (_started)
                Positioned(
                  right: 18,
                  top: 16,
                  child: IconButton(
                    onPressed: () {
                      // Letting the mouse go first: a settings panel you cannot
                      // point at is a settings panel with no way out of it.
                      unawaited(_devices.release());
                      setState(() => _showSettings = true);
                    },
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
