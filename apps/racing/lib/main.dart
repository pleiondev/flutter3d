/// An arcade racer, assembled from the engine, the genre and this game's own
/// content.
///
/// The same shape every application on this stack has — a device, a renderer, a
/// loop, a level, a camera — with the two things a racing game adds: a circuit
/// read from a file and turned into road, and a car that is drawn where the
/// simulation last put it.
///
/// The division is the one the whole repository keeps. Nothing here decides how
/// a car handles or when a lap counts; that is `flutter3d_racing`, and it is
/// tested without a device. What is here is which key means throttle, what
/// colour the tarmac is, and where the numbers go on the screen.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, rootBundle;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_racing/bridge.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter3d_ui/flutter3d_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gamepad/gamepad.dart' show PadButton;
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';
import 'src/circuits.dart';
import 'src/credits.dart';
import 'src/ghost_car.dart';
import 'src/hud.dart';
import 'src/looks.dart';
import 'src/reactions.dart';
import 'src/sounds.dart';
import 'src/staging.dart';
import 'src/touch_drive.dart';


void main() => runApp(const RacingApp());

class RacingApp extends StatelessWidget {
  const RacingApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        title: 'Ring',
        debugShowCheckedModeBanner: false,
        home: RaceScreen(),
      );
}

class RaceScreen extends StatefulWidget {
  const RaceScreen({super.key});

  @override
  State<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends State<RaceScreen>
    with SingleTickerProviderStateMixin {
  Renderer? _renderer;

  /// Kept because a season has a second circuit to build, and building it means
  /// uploading meshes to the device the first one was built on.
  GraphicsDevice? _device;
  Ticker? _ticker;
  Object? _initError;

  /// The scene, empty until the circuit is read, and **drawn from the first
  /// frame either way**.
  ///
  /// Not a nullable field with a spinner in front of it, which is what this was
  /// and which cost an afternoon. Flutter GPU's context does not know what
  /// colour format its surface is until something has been drawn through it: an
  /// application that waits for its content before its first `render` gets
  /// `PixelFormat.unknown` back, fails to allocate the frame's own targets, and
  /// then fails again every frame after — a window that stays the clear colour
  /// with no error anywhere except a Metal validation line. The platformer
  /// starts with `Scene()` for the same reason, which is how this was found.
  Scene _scene = Scene();
  static const PerspectiveProjection _lens =
      PerspectiveProjection(fovYRadians: 1.05, near: 0.3, far: 1600.0);
  final CameraNode _camera = CameraNode(projection: _lens);
  /// The view, and the one colour behind the sky.
  ///
  /// Nearly nothing shows this now: the sky is drawn per pixel and covers every
  /// pixel the scene did not. It still matters for the frames before the
  /// circuit has loaded — the application draws from the first frame on
  /// purpose, and a window that opens black and turns blue a second later reads
  /// as a fault.
  ///
  /// `RenderView` clears to a very dark blue by default, which is right for a
  /// dungeon and wrong for anywhere outdoors. Kept in step with the sky's own
  /// horizon by [_skyColour], though it is authored in sRGB and the sky is not
  /// — see [_skySettings].
  late final RenderView _view = RenderView(
    camera: _camera,
    // Daylight from the first frame. This is `late` and so is worked out when
    // the first frame is built, which is before any circuit has loaded — and a
    // window that opens black and turns blue a second later reads as a fault.
    clearColor: _skyColour(),
  );

  /// The preset, as the renderer's own sky.
  ///
  /// One model rather than two: the gradient the shader evaluates per pixel is
  /// the gradient `SkyPreset.colourAt` computes on the CPU, so the haze the far
  /// side of the circuit fades into and the sky above it cannot drift apart.
  /// What the shader adds is the sun's own disc, which is half a degree across
  /// and could not be drawn on any dome this game could afford.
  ///
  /// The colours go across untouched, because both sides of this are linear:
  /// vertex colours, fog and now the sky are all scene-referred, and only
  /// `RenderView.clearColor` is sRGB — which is why the clear colour is now
  /// only what shows before the first circuit has loaded.
  SkySettings _skySettings() => SkySettings(
        enabled: true,
        zenith: _sky.zenith,
        horizon: _sky.horizon,
        nadir: _sky.belowHorizon,
        directionToSun: _sky.directionToSun,
        sunColor: _sky.sunColor,
        glowExponent: _sky.glowWide,
        glowStrength: _sky.glowStrength,
        sunIntensity: _sky.sunDisc,
      );

  Vector4 _skyColour() {
    final colour = _sky.colourAt(_gaze);
    return Vector4(colour.x, colour.y, colour.z, 1.0);
  }

  /// The hour this circuit is raced at, and everything that follows from it.
  ///
  /// Replaced when the track file is read; the default is here so that the
  /// first frames — drawn before the circuit has loaded, on purpose — are drawn
  /// in daylight rather than in a black void.
  SkyPreset _sky = SkyPresets.morning;

  /// Which way the camera is looking, kept between [_place] and [build].
  final Vector3 _gaze = Vector3(0.0, 0.0, 1.0);

  TrackSpline? _track;
  RaceState? _race;
  RacingSimulation? _simulation;
  ChaseCamera? _chase;
  AiDriver? _ai;
  final List<SphereVehicle> _cars = <SphereVehicle>[];
  final List<SceneNode> _carNodes = <SceneNode>[];

  /// What the cars throw into the air, and what decides it.
  ///
  /// **This game showed nothing at all**: no smoke off a locked wheel, no dirt
  /// off the grass, no sparks down a barrier. One pool for every car, because
  /// it is one draw call whatever is in it.
  final ParticleSystem _particles = ParticleSystem(capacity: 1200);
  final Reactions _reactions = Reactions();

  /// Which circuit is being raced, and how far into the season that is.
  ///
  /// **The game had one `const` asset path and no idea that anything ever
  /// ended.** A race could be won and nothing happened: no next circuit,
  /// nothing that remembered having been anywhere, and a car going round a
  /// finished race forever.
  late final SeasonProgress _season =
      SeasonProgress(storage: defaultStorage('racing'));
  late Circuit _circuit = _season.read();

  /// What is said across the screen between circuits, and at the end.
  String? _notice;

  /// How long the record line goes on saying it has just been beaten.
  ///
  /// Seconds rather than laps: a driver who has just set one is looking at the
  /// corner in front of them, and a line that changed for one frame changed for
  /// nobody. It runs on the clock rather than on the simulation because it is
  /// something being read, not something being driven.
  double _celebrateFor = 0.0;

  /// The best lap driven here, and the car it is drawn as.
  ///
  /// **Written, tested and never used**: the ghost has been in the racing
  /// package since it existed and this game called none of it. Rebuilt with the
  /// circuit, because a lap of one circuit means nothing on another.
  late GhostKeeper _ghosts = _keeperFor(_circuit);
  GhostCar? _ghostCar;

  GhostKeeper _keeperFor(Circuit circuit) => GhostKeeper(
        storage: defaultStorage('racing'),
        track: circuit.track,
      );

  /// How far above the body's own origin each car is drawn, in metres.
  ///
  /// A car is simulated as a sphere whose centre floats `rideHeight` above the
  /// road, and a model's origin is wherever the person who exported it put it —
  /// this one's is at the top of the bodywork, so drawn at the sphere's centre
  /// the car was buried half a metre into the tarmac. The lift is worked out
  /// from the asset's own bounds rather than typed in, because the next model
  /// will have its origin somewhere else again.
  final List<double> _carLift = <double>[];

  final InputState _input = InputState();

  /// What the player has changed, and where it is kept.
  ///
  /// **This game had none of it**: no volumes, no rebinding, no way to turn
  /// anything down — the only settings it has ever had were the ones its author
  /// compiled in. The panel is shared with the other two games; what is here is
  /// the wiring and the two lists that are this game's own.
  final SettingsFile _settingsFile = SettingsFile(appName: 'racing');
  late final GameConfig _config;
  late final SettingsCubit _settings;

  /// What a player can move, in the order the panel lists it.
  ///
  /// A driver's words rather than a walker's: this game has a throttle and a
  /// brake where the others have a forward and a back.
  static const List<GameAction> _rebindable = <GameAction>[
    _Drive.throttle,
    _Drive.brake,
    _Drive.left,
    _Drive.right,
    _Drive.handbrake,
  ];

  /// What the player has already told the operating system.
  Accommodations _system = const Accommodations();
  late final DesktopInput _devices =
      DesktopInput(state: _input, bindings: ownedBindings(_config, _keys));

  /// The controller, which this game did not read.
  ///
  /// **Everything it needs was already written.** `VehicleInput` has held a
  /// throttle, a brake and a steering angle as `double` since the genre package
  /// existed, and `PadRoutes.driving` was written for a game that never asked
  /// for it — so a wheel that is half over and a trigger that is a third down
  /// went to a game reading `held ? 1.0 : 0.0`.
  late final PadInput _pad = PadInput(
    state: _input,
    // One table for both devices, because a player's bindings are one file.
    bindings: _devices.bindings,
    // The stick steers; the pedals are bound like the buttons they also are, so
    // a player can move them. Which way the stick turns the car is not
    // something anybody rebinds.
    routes: PadRoutes.driving(
      steerLeft: _Drive.left,
      steerRight: _Drive.right,
    ),
  )..applySettings(_config);
  /// The loop, rather than a bare `FixedStep`.
  ///
  /// **This game drove the clock itself and got none of the loop's services**:
  /// no pause, no `beginStep`/`endStep` around a step — so `InputState.pressed`
  /// never worked here at all — and no reading of the simulated time the clock
  /// refused to run.
  late final GameLoop _loop = GameLoop(input: _input, onStep: _driveOneStep);

  /// Whether the machine is keeping up, and what it cost when it was not.
  final Pace _pace = Pace();

  List<Vector2> _outline = const <Vector2>[];
  final Vector3 _drawAt = Vector3.zero();

  /// The ears, and what they hear.
  ///
  /// Absent until the device opens, and absent for good if it will not: a game
  /// that refuses to start because there is no sound card is worse than a quiet
  /// one, which is why every use of this is behind a null check rather than a
  /// try.
  SoLoudBackend? _speakers;

  /// Silent until the device opens, and the **mixer survives the swap**: the
  /// settings panel turns volumes before there is a sound card, and a mixer
  /// built with the backend would lose whatever the player had set.
  AudioScene _audio = AudioScene(backend: SilentBackend());
  final AudioListener _ears = AudioListener();

  /// Held so the keyboard can be given back after a click.
  ///
  /// A web build draws through a platform view, and clicking one moves the
  /// browser's focus to the canvas element. After that Flutter sees no key
  /// events, which in a game driven entirely by the keyboard reads as a car
  /// that will not start. `autofocus` only covers the first frame.
  final FocusNode _keyboard = FocusNode(debugLabel: 'drive');
  final List<CarVoice> _voices = <CarVoice>[];
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    // Settings before devices: the bindings a player saved are the ones the
    // keyboard should read from the first key press, not from the first rebind.
    _config = _settingsFile.read();
    // A config saved before this game read a controller has no `pad:` in it,
    // and nobody should have to delete their settings to plug one in. The
    // rebindings they did make are left alone.
    if (!PadInput.knowsPad(_devices.bindings)) _padBindings(_devices.bindings);
    _settings = SettingsCubit(
      config: _config,
      file: _settingsFile,
      apply: _applyConfig,
    );
    super.initState();
    unawaited(_open());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _system = Accommodations.of(context);
    _applyAccessibility();
  }

  @override
  void dispose() {
    unawaited(_settings.close());
    _keyboard.dispose();
    _ticker?.dispose();
    for (final voice in _voices) {
      voice.stop();
    }
    unawaited(_speakers?.dispose());
    super.dispose();
  }

  /// Puts the config onto everything that is playing.
  void _applyConfig(GameConfig config) {
    applySavedVolumes(config, _audio.mixer);
    _applyAccessibility();
  }

  /// Puts the accessibility settings where they take effect.
  ///
  /// **A racing camera moves more than either of the other two**: it leans into
  /// corners, widens with speed and is kicked by every kerb. Somebody who has
  /// turned reduce-motion on has said something about exactly that, and this
  /// game was not listening.
  void _applyAccessibility() {
    _chase?.motion =
        _config.settingOf('a11y.cameraMotion', _system.cameraMotion);
  }

  /// The driving pad.
  ///
  /// The triggers where every racing game has put them for twenty years, the
  /// handbrake on the face button a thumb is already resting on, and the
  /// engine's own defaults left out: this game does not walk, and a d-pad bound
  /// to `moveForward` here would be a control that means nothing.
  static Bindings _padBindings(Bindings bindings) => bindings
    ..bind(InputSource.pad(PadButton.triggerRight.id), _Drive.throttle)
    ..bind(InputSource.pad(PadButton.triggerLeft.id), _Drive.brake)
    ..bind(InputSource.pad(PadButton.faceSouth.id), _Drive.handbrake)
    ..bind(InputSource.pad(PadButton.dpadLeft.id), _Drive.left)
    ..bind(InputSource.pad(PadButton.dpadRight.id), _Drive.right);

  /// The driving keys.
  ///
  /// A table of its own rather than the engine's defaults, which name walking:
  /// a car has a throttle and a brake, not a forward and a back. The arrows are
  /// bound alongside the letters because half the people who sit down at a
  /// racing game reach for them first.
  static Bindings _keys() {
    final bindings = Bindings(<InputSource, GameAction>{});
    void bind(LogicalKeyboardKey key, GameAction action) =>
        bindings.bind(InputSource.key(key.keyId), action);

    bind(LogicalKeyboardKey.keyW, _Drive.throttle);
    bind(LogicalKeyboardKey.arrowUp, _Drive.throttle);
    bind(LogicalKeyboardKey.keyS, _Drive.brake);
    bind(LogicalKeyboardKey.arrowDown, _Drive.brake);
    bind(LogicalKeyboardKey.keyA, _Drive.left);
    bind(LogicalKeyboardKey.arrowLeft, _Drive.left);
    bind(LogicalKeyboardKey.keyD, _Drive.right);
    bind(LogicalKeyboardKey.arrowRight, _Drive.right);
    bind(LogicalKeyboardKey.space, _Drive.handbrake);
    return bindings;
  }

  Future<void> _open() async {
    final GraphicsDevice device;
    try {
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
      } catch (error) {
        _initError = error;
      }
    });
    if (_renderer == null) return;

    _renderer?.addContributor(ParticleContributor(_particles));

    unawaited(_openAudio());

    // The ticker before the circuit, not after. Drawing has to start at once —
    // see [_scene] — and there is nothing to step until the circuit is read, so
    // the loop simply returns early until it is.
    _ticker = createTicker(_onTick)..start();
    await _loadCircuit(device);
  }

  /// Opens the sound device, or leaves the game silent.
  ///
  /// The trap this repository has paid for twice: a plugin added to an already
  /// built application does not bring its native framework with it, and the
  /// only symptom is one line about "no available native assets" and then
  /// nothing. If that is what this prints, the answer is `flutter clean`.
  Future<void> _openAudio() async {
    // Opened by `flutter3d_audio` — see `openSpeakers`, which holds the trap
    // this game's own comment used to: a plugin added to an already built
    // application does not bring its native framework with it, and the only
    // symptom is one line about native assets and then silence.
    final speakers = await openSpeakers(
      bank: Sounds.all,
      mixer: _audio.mixer,
      maxVoices: 24,
    );
    if (speakers == null || !mounted) return;

    setState(() {
      _speakers = speakers.backend;
      _audio = speakers.scene;
      // Any cars that were built while the device was opening.
      for (final car in _cars) {
        _voices.add(CarVoice(scene: _audio, vehicle: car));
      }
    });
  }

  Future<void> _loadCircuit(GraphicsDevice device) async {
    try {
      // The circuit and the scenery are two halves of one document, written by
      // one script and read by two loaders: the spline is this genre's and the
      // level is the engine's, which has read brushes since the first game.
      final text = await rootBundle.loadString(_circuit.track);
      final document = TrackDocument.fromJson(
        jsonDecode(text) as Map<String, Object?>,
      );
      final loaded = await const LevelLoader().load(
        _circuit.level,
        device: device,
        // This circuit places no entities — the scenery is brushes — so the
        // registry is empty rather than absent: the loader validates against
        // it, and an empty one is the statement that nothing is expected.
        registry: EntityRegistry(const <EntityKind>[]),
      );

      // The one assembly this game has. What is left here is what needs a
      // device: the road mesh, the car boxes and the scene they go in.
      final staged = stage(document, loaded.collision);
      final track = staged.track;
      final scene = loaded.scene;
      addTrackTo(scene, track, device: device);
      scene.add(_camera);

      _cars.addAll(staged.cars);
      for (var i = 0; i < _cars.length; i++) {
        final node = carBox(device, Looks.rival(i), name: 'car-$i');
        scene.add(node);
        _carNodes.add(node);
        _carLift.add(liftFor(_cars[i]));
      }

      _ghosts = _keeperFor(_circuit)..load();
      _ghostCar = GhostCar.build(device, scene);

      {
        for (final car in _cars) {
          _voices.add(CarVoice(scene: _audio, vehicle: car));
        }
      }

      // The one light in the level was written from this same preset by the
      // generator, so the sun the shadows fall from and the sun the sky glows
      // around are the same sun by construction rather than by agreement.
      scene.ambientIntensity = document.sky.ambientIntensity;


      setState(() {
        _sky = document.sky;
        _scene = scene;
        _track = track;
        _race = staged.race;
        _outline = trackOutline(track);
        _simulation = staged.sim;
        _chase = staged.chase;
        _ai = staged.ai;
      });

      unawaited(_dressPlayer(device, scene));
    } catch (error, stack) {
      debugPrint('circuit: $error\n$stack');
      if (mounted) setState(() => _initError = error);
    }
  }

  /// Swaps the player's box for the model, if it loads.
  ///
  /// If it does not, the game is still playable as a box — a car that will not
  /// start because an asset moved is worse than a car that is a rectangle.
  /// The player has finished the race. On to the next circuit, or that was the
  /// season.
  ///
  /// Saved before the next circuit is loaded rather than after: the moment a
  /// save is for is the one where the machine might not reach the end of the
  /// load, and a player who is put back on the circuit they have just won has
  /// lost the race they won.
  void _finishedHere() {
    final next = Season.after(_circuit);
    if (next == null) {
      // The season starts again next launch. A deliberate clear rather than a
      // name meaning "done": a saved file naming a circuit this build does not
      // ship already reads as the first one, and one meaning is easier to keep
      // true than two.
      _season.clear();
      setState(() => _notice = 'Season complete');
      return;
    }

    _season.reached(next);
    setState(() => _notice = '${next.title} next');
    unawaited(_moveOn(next));
  }

  /// How long the finished circuit stays on screen before the next one.
  ///
  /// The same pause the platformer takes between levels, for the same reason: a
  /// race that cuts away on the frame it is won reads as a crash rather than as
  /// a result.
  static const Duration _pauseBetweenCircuits = Duration(milliseconds: 1800);

  Future<void> _moveOn(Circuit next) async {
    final device = _device;
    if (device == null) return;
    await Future<void>.delayed(_pauseBetweenCircuits);
    if (!mounted) return;

    // Everything that belonged to the circuit just raced. The voices are
    // stopped rather than dropped: a car that is no longer in the world still
    // has an engine running in the mixer.
    for (final voice in _voices) {
      voice.stop();
    }
    _voices.clear();
    _cars.clear();
    _carNodes.clear();
    _carLift.clear();
    _ghostCar = null;

    setState(() {
      _circuit = next;
      _notice = null;
      // An empty scene rather than none: the surface has to keep drawing
      // through the load or Flutter GPU never learns its own pixel format —
      // see [_scene].
      _scene = Scene()..add(_camera);
      _race = null;
      _simulation = null;
      _track = null;
      _chase = null;
      _ai = null;
    });

    await _loadCircuit(device);
  }

  Future<void> _dressPlayer(GraphicsDevice device, Scene scene) async {
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: const BundleAssetSource(kCarModel)),
      );
      final asset = await ModelAsset.fromDocument(
        document,
        device: device,
        fallbackAlbedo: SolidColorTexture.white.upload(device),
        name: kCarModel,
      );
      if (!mounted) return;

      final instance = asset.instantiate(scene, name: 'player');
      final box = _carNodes[0];
      setState(() {
        _carNodes[0] = instance.root;
        // Put the model's lowest point on the road: the sphere's centre is a
        // ride height above the tarmac, and the model hangs from wherever its
        // own origin is.
        _carLift[0] = -asset.localBounds.min.y - _cars[0].tuning.rideHeight;
      });
      scene.remove(box);
    } catch (error) {
      debugPrint('car: staying a box ($error)');
    }
  }

  void _onTick(Duration now) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;

    // Before the loop advances, so a step and the intent it is stepping with
    // belong to the same frame — see [PadInput].
    _pad.tick(dt);
    _padRebinding();

    final race = _race;
    if (_simulation == null || race == null) return;

    _loop.paused = shouldPause(
      ready: _simulation != null,
      menuOpen: _settings.state.isOpen,
      // This game never captures the pointer — it is driven from the keyboard —
      // so the pointer is not the gate here and saying otherwise would freeze
      // it on every desktop build.
      pointerIsTheGate: false,
      pointerHeld: false,
      padConnected: _pad.isConnected,
    );
    _loop.advance(dt.clamp(0.0, 0.25));
    _pace.note(
      dropped: _loop.clock.droppedSteps,
      dt: dt,
      stepSeconds: _loop.clock.stepSeconds,
    );

    if (_celebrateFor > 0.0) _celebrateFor = (_celebrateFor - dt).clamp(0.0, 4.0);

    _particles.advance(dt);
    _place(dt);
    _listen(race);
    setState(() {});
  }

  /// One step of the race. Called by the loop, once per fixed step.
  void _driveOneStep(double stepSeconds) {
    final simulation = _simulation;
    final race = _race;
    if (simulation == null || race == null) return;
    _readDriver(simulation);
    _driveTheRest(simulation, race);
    simulation.step(stepSeconds);

    // Recorded always, not only when the lap is going to be a good one:
    // whether it was the best is knowable when it ends, and by then it is too
    // late to have been writing it down.
    // **The record, not the session's best.** A race begins with no laps in
    // it, so the lap somebody drives while getting used to the car was the
    // best one by definition — and it used to take the place of a record that
    // stood from another evening. The keeper compares against the disk now,
    // and says when the disk changed.
    if (_ghosts.stepped(race.progress[0], _cars[0])) _celebrateFor = 4.0;

    // What this step looks like, decided by something a test can call and
    // performed here. Per car: a rival locking up in front is as worth seeing
    // as the player doing it.
    for (final shown in _reactions.listen(race, _cars).bursts) {
      _particles.burst(shown.effect, shown.at, direction: shown.direction);
    }
    if (race.progress[0].finishedThisStep) _finishedHere();
  }

  /// A pad button offered to a waiting rebinding.
  ///
  /// So a controller can be remapped from the controller, which is the whole
  /// point for a player who has one of the two devices. There is nothing else
  /// on screen here for a pad button to mean — no title card to take down and
  /// no run to start over — so what `PadPresses` hands back is dropped.
  void _padRebinding() => _presses.offer(_pad, _settings);

  /// The pad's presses, told apart from its holds.
  final PadPresses _presses = PadPresses();

  /// The player's keys, as a car's controls.
  void _readDriver(RacingSimulation simulation) {
    // **How hard, not whether.** `value` is a key's full press and a trigger's
    // actual travel, so the same three lines drive a car from a keyboard and
    // from a controller — and a wheel a third over asks for a third of the
    // lock, which is the whole reason `VehicleInput` holds doubles.
    final input = simulation.inputs[0];
    input
      ..throttle = _input.value(_Drive.throttle)
      ..brake = _input.value(_Drive.brake)
      ..handbrake = _input.held(_Drive.handbrake)
      ..steer = _input.value(_Drive.right) - _input.value(_Drive.left);
  }

  void _driveTheRest(RacingSimulation simulation, RaceState race) {
    final ai = _ai;
    final track = _track;
    if (ai == null || track == null) return;

    final player = race.progress[0];
    for (var i = 1; i < _cars.length; i++) {
      // How far the player is up the road from this car, wrapped, which is what
      // the rubber band reads.
      var gap = player.progressAlong(track.length) -
              race.progress[i].progressAlong(track.length);
      if (gap.abs() > track.length / 2) {
        gap -= gap.sign * track.length;
      }
      ai.drive(
        _cars[i],
        simulation.inputs[i],
        others: _cars,
        playerGap: gap,
      );
    }
  }

  /// Moves everything the renderer draws to where the simulation left it.
  void _place(double dt) {
    for (var i = 0; i < _cars.length; i++) {
      final node = _carNodes[i];
      final car = _cars[i];
      // Lifted along the car's own up rather than the world's, so that a car on
      // a cambered corner sits on the road instead of hovering over the inside
      // of it.
      _drawAt
        ..setFrom(car.position)
        ..addScaled(car.visualBasis.getColumn(1), _carLift[i]);
      node
        ..setPositionFrom(_drawAt)
        ..setRotation(Quaternion.fromRotation(car.visualBasis));
    }

    // The lap somebody already drove, where it was at this point of the lap
    // being driven now. Hidden when there is nothing to race against, and when
    // the recording has run out — a ghost that stops where the tape ended reads
    // as a car parked on the racing line.
    final tape = _ghosts.best;
    final race = _race;
    if (tape != null && race != null) {
      _ghostCar?.showAt(race.progress[0].lapTime, tape, _carLift[0]);
    } else {
      _ghostCar?.node.visible = false;
    }

    final chase = _chase;
    if (chase == null) return;
    chase.follow(_cars[0], dt);
    _camera
      ..setPositionFrom(chase.eye)
      ..lookAt(chase.target)
      ..projection = _lens.copyWith(fovYRadians: chase.fov);

    // The sky, once a frame, from where the camera ended up. The engine's fog
    // is one colour with no idea of direction; giving it the colour of the air
    // *along this view* is what stops distance being the same grey whichever
    // way the car is pointing.
    _gaze
      ..setFrom(chase.target)
      ..sub(chase.eye);
    _view.clearColor = _skyColour();
  }

  /// What the race sounds like this frame.
  ///
  /// Read from the same flags the display reads, once, after the steps: a sound
  /// played from inside a step is a sound played several times on a slow frame.
  void _listen(RaceState race) {
    for (var i = 0; i < _voices.length && i < race.progress.length; i++) {
      _voices[i].update(offRoad: race.progress[i].offRoad);
    }

    final player = race.progress[0];
    if (race.countdownTickThisStep) {
      _audio.play(race.countdown > 0.0 ? Sounds.count : Sounds.go, _ears.position);
    }
    if (player.bestLapThisStep) {
      _audio.play(Sounds.best, _ears.position);
    } else if (player.lapCompletedThisStep) {
      _audio.play(Sounds.lap, _ears.position);
    }
    if (player.checkpointThisStep) {
      _audio.play(Sounds.checkpoint, _ears.position);
    }

    // Along the camera's own forward rather than through a yaw: `aimAt` reads
    // an angle as a first-person camera's, and a chase camera is not one.
    final chase = _chase;
    if (chase != null) {
      _ears.aimAlong(chase.eye, chase.target - chase.eye);
    }
    _audio.update(_ears);
  }

  RaceReadout _readout() {
    final race = _race!;
    final player = race.progress[0];
    return RaceReadout(
                behind: _pace.behind,
                paused: _settings.state.isOpen,
                notice: _notice,
      speed: _cars[0].speed,
      lap: player.lap,
      laps: race.laps,
      position: race.positionOf(0),
      racers: race.progress.length,
      lapTime: player.lapTime,
      bestLap: player.bestLap,
      record: _ghosts.record,
      recordJustSet: _celebrateFor > 0.0,
      wrongWay: player.wrongWay,
      countdown:
          race.phase == RacePhase.countdown ? race.countdown : null,
      mode: race.mode,
      outline: _outline,
      carsOnMap: <Vector2>[
        for (final car in _cars) Vector2(car.position.x, car.position.z),
      ],
    );
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
              '$error',
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _keyboard,
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          // **This game could not be paused at all**, and had no settings to
          // pause into. Escape opens them, and opening them is what stops the
          // race — the same clause `shouldPause` calls a menu. The order the
          // three clauses go in is `settingsKeys`; what is this game's is the
          // opening itself: the keys the car was holding are let go, or it
          // comes back accelerating into a wall.
          final settingsSay =
              settingsKeys(event, _settings, opening: _input.clear);
          if (settingsSay != null) return settingsSay;
          return _devices.handleKeyEvent(event);
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            SceneSurface(
              renderer: renderer,
              scene: scene,
              view: _view,
              onBeforeFrame: () {},
              settings: () => RenderSettings(
                // Not a colour anybody typed: the haze at the horizon,
                // brightened towards the sun along the direction the camera is
                // looking. It is the same arithmetic the sky above is drawn
                // with, so the far side of the lap fades into the background
                // instead of into a band of a slightly different grey.
                fog: FogSettings(
                  color: _sky.inScatterAlong(_gaze),
                  density: _sky.fogDensity,
                ),
                // The hour of the day changes it: a low sun puts far less light
                // on a circuit than a high one, and one exposure through both is
                // either a washed-out noon or a dusk nobody can see the road in.
                exposure: _sky.exposure,
                sky: _skySettings(),
                // Three cascades over a circuit a kilometre round. One map over
                // that is metres of world per texel, which draws a car's own
                // shadow as a slab beside it; three tiles put the near one over
                // the part of the track anybody is looking at.
                shadows: const ShadowSettings(
                  cascades: kShadowCascades,
                  resolution: kShadowResolution,
                ),
              ),
            ),
            // A platform view takes the pointer events over it, so the click
            // that hands the keyboard back has to be caught above the frame
            // rather than around it. Nothing else here wants the pointer.
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _keyboard.requestFocus(),
              ),
            ),
            if (_race != null) RaceHud(readout: _readout()),
            // A phone has no keyboard and this game had nothing else to offer
            // it: the wheel and the pedals, above the frame and below the
            // panel. Hidden while the settings are open, or a thumb reaching
            // for a slider holds the throttle down behind it.
            if (Playing.touch && _race != null && !_settings.state.isOpen)
              TouchDrive(
                state: _input,
                steerLeft: _Drive.left,
                steerRight: _Drive.right,
                throttle: _Drive.throttle,
                brake: _Drive.brake,
                handbrake: _Drive.handbrake,
              ),
            // The panel and the gear are the same piece of state seen twice, so
            // they are built from it rather than from two flags that have to be
            // kept opposite.
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
                        _input.clear();
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
                  padConnected: false,
                  actions: _rebindable,
                  waitingFor: settings.waitingFor,
                  onVolume: (AudioBus bus, double volume) =>
                      _settings.setVolume(bus.name, volume),
                  onSetting: _settings.setSetting,
                  onRebind: _settings.rebind,
                  onResetControls: () => _settings.resetControls(_keys()),
                  onClose: _settings.hide,
                  // **The licence asks for this and the game did not do it.**
                  // The car is CC BY 4.0, whose text says attribution must
                  // appear wherever the work does.
                  credits: const CreditsSection(credits: Credits.models),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// What this game lets a driver ask for.
///
/// Its own actions rather than the engine's `moveForward` and friends: a car
/// has a throttle and a brake, not a forward and a back, and `GameAction` is a
/// string for exactly this reason.
abstract final class _Drive {
  static const GameAction throttle = GameAction('throttle');
  static const GameAction brake = GameAction('brake');
  static const GameAction left = GameAction('steerLeft');
  static const GameAction right = GameAction('steerRight');
  static const GameAction handbrake = GameAction('handbrake');
}
