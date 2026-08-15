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

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/hud.dart';
import 'src/looks.dart';
import 'src/scene_surface.dart';
import 'src/settings_file.dart';
import 'src/settings_panel.dart';
import 'src/sounds.dart';

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
  static const String _levelAsset = 'assets/levels/ascent.json';
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

  /// Whether the runner had its feet down last step, for the landing sound.
  bool _wasGrounded = true;

  bool _showSettings = false;
  late final GameLoop _loop;
  late final Ticker _ticker;

  final CameraNode _camera = CameraNode(
    projection: const PerspectiveProjection(fovYRadians: 1.05, far: 220.0),
  );
  late final RenderView _view;

  GpuRenderBackend? _device;
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

  /// The loaded model, held so that nothing collects it out from under the
  /// scene. `FixtureVisuals` keeps its assets in a cache for the same reason.
  // ignore: unused_field
  ModelAsset? _runnerAsset;

  /// How far below the body's centre the visual's origin sits.
  ///
  /// A body is a box about its middle; a model of somebody standing has its
  /// feet at the origin. The same two conventions that produced the respawn
  /// bug, reconciled in one number instead of by a parent node.
  double _runnerDrop = 0.0;

  /// Added to the runner's yaw, for a model that was exported facing the other
  /// way. A number rather than a re-authored mesh.
  double _runnerFacing = 0.0;

  Runner? _runner;
  PlatformerSimulation? _sim;
  FollowCamera? _followCamera;

  /// The runner's drawn position, one frame behind the simulation.
  ///
  /// Interpolated for the same reason the dungeon interpolates its camera: the
  /// step is 60 Hz and the display may not be, and a body drawn at the last
  /// step's position judders on a 120 Hz monitor even though the simulation is
  /// perfectly smooth.
  final InterpolatedVector3 _drawnAt = InterpolatedVector3();
  final InterpolatedAngle _drawnYaw = InterpolatedAngle();

  final Vector3 _scratch = Vector3.zero();
  Duration _lastTick = Duration.zero;
  double _elapsed = 0.0;
  int _deathsSeen = 0;

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
          : DesktopInput.defaultBindings(),
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

  Future<void> _openGraphics() async {
    final GpuRenderBackend device;
    try {
      device = await GpuRenderBackend.create();
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
      } catch (error) {
        _initError = error;
      }
    });

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
    _audio = AudioScene(backend: backend, mixer: _audio.mixer);
    await _audio.preload(Sounds.all);
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

  /// The seam where the engine, the genre and this game's content meet.
  Future<void> _loadLevel() async {
    final device = _device;
    if (device == null) return;

    // One registry validates the document and then spawns it. Two could
    // disagree about what a document may contain, which is the failure this
    // seam was built to remove — so the crate kind is told where bodies go
    // *after* there is a world, exactly as the shooter tells its monster kind
    // where the bestiary is.
    final kinds = platformerRegistry();
    final loaded = await LevelLoader().load(
      _levelAsset,
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
        // The authored point: feet on the floor. See Runner.reviveAt.
        startAt: start,
        mechanisms: mechanisms,
        dynamics: dynamics,
        levelNext: loaded.level.next,
      );
      _followCamera = FollowCamera(world: loaded.collision);
      unawaited(_dressRunner(device, loaded.scene, runner));
      _drawnAt.jumpTo(runner.body.position);
      _drawnYaw.jumpTo(runner.yaw);
    });
  }

  /// A box, right away, so the game can be played while the model loads.
  SceneNode _boxRunner(GpuRenderBackend device, Scene scene, Runner runner) {
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
  /// The asset is authored at the size the game wants (`tool/shrink_glb.py`
  /// bakes the scale into its root), so there is no `setScale` here either.
  Future<void> _dressRunner(
    GpuRenderBackend device,
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
        _runnerDrop = runner.body.halfExtents.y - asset.localBounds.min.y;
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
    _loop.paused = !_devices.isCaptured || _sim == null;
    _loop.advance(dt.clamp(0.0, 0.25));

    _placeCamera(dt);
    _fixtures?.sync(_elapsed);
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
      _drawnAt.push(runner.body.position);
    }
    _drawnYaw.push(runner.yaw);
  }

  /// Turns a step's events into sounds. Nothing here decides anything.
  void _hear(PlatformerSimulation sim, Runner runner) {
    final at = runner.position;
    if (runner.jumpedThisStep) {
      _audio.play(runner.airJumpsLeft < 1 ? Sounds.airJump : Sounds.jump, at);
    }
    if (runner.dashedThisStep) _audio.play(Sounds.dash, at);
    for (var i = 0; i < sim.takenThisStep.length; i++) {
      _audio.play(Sounds.coin, sim.takenThisStep[i].origin);
    }
    if (sim.reachedCheckpointThisStep) _audio.play(Sounds.checkpoint, at);
    if (sim.deaths != _deathsSeen) _audio.play(Sounds.death, at);

    // Landing is a transition rather than an event the simulation reports,
    // because nothing in the simulation cares — only the ears do.
    if (runner.isGrounded && !_wasGrounded) _audio.play(Sounds.land, at);
    _wasGrounded = runner.isGrounded;
  }

  void _placeCamera(double dt) {
    final camera = _followCamera;
    final node = _runnerNode;
    if (camera == null || node == null) return;

    camera.look(_input.lookDelta);
    _drawnAt.read(_loop.alpha, _scratch);
    camera.follow(_scratch, dt);

    node
      ..setPosition(_scratch.x, _scratch.y - _runnerDrop, _scratch.z)
      ..setRotation(
        Quaternion.axisAngle(
          Vector3(0.0, 1.0, 0.0),
          _drawnYaw.read(_loop.alpha) + _runnerFacing,
        ),
      );

    _camera
      ..setPositionFrom(camera.eye)
      ..lookAt(camera.target);

    // Along the camera's own forward rather than through a yaw: `aimAt` reads
    // an angle as a first-person camera's, and this one is not.
    _ears.aimAlong(camera.eye, camera.target - camera.eye);
    _audio.update(_ears);
  }

  @override
  void dispose() {
    _audio.stopAll();
    unawaited(_soloud?.dispose());
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
        autofocus: true,
        onKeyEvent: (_, KeyEvent event) => _devices.handleKeyEvent(event),
        child: Listener(
          onPointerDown: (_) {
            _devices.pressPointer(PlatformerActions.dash);
            if (!_devices.isCaptured) unawaited(_devices.captureMouse());
          },
          onPointerUp: (_) => _devices.releasePointer(PlatformerActions.dash),
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
              if (sim != null)
                Hud(
                  coins: _runner?.purse['coin'] ?? 0,
                  deaths: sim.deaths,
                  state: sim.state,
                  captured: _devices.isCaptured,
                ),
              if (_showSettings)
                SettingsPanel(
                  mixer: _audio.mixer,
                  bindings: _devices.bindings,
                  onVolume: _setVolume,
                  onClose: () => setState(() => _showSettings = false),
                )
              else
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
