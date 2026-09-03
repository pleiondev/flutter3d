/// An arcade racer, assembled from the engine, the genre and this game's own
/// content.
///
/// The same shape every application on this stack has — a device, a renderer, a
/// loop, a level, a camera — with the two things a racing game adds: a circuit
/// read from a file and turned into road, and a car that is drawn where the
/// simulation last put it.
///
/// The division is the one the whole repository keeps. Nothing here decides how
/// a car handles or when a lap counts; that is `flutter3d_game_racing`, and it is
/// tested without a device. What is here is which key means throttle, what
/// colour the tarmac is, and where the numbers go on the screen.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/bridge.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';
import 'src/circuits.dart';
import 'src/controls.dart';
import 'src/credits.dart';
import 'src/ghost_car.dart';
import 'src/hud.dart';
import 'src/looks.dart';
import 'src/race_cubit.dart';
import 'src/race_readout.dart';
import 'src/reactions.dart';
import 'src/sounds.dart';
import 'src/staging.dart';
import 'src/touch_drive.dart';

void main() {
  // **This game had none of it.** The other two locked to landscape and hid
  // the system bars on a handset; this one, which has touch controls and is
  // meant to be played on a phone, did neither — so a tilt reframed the chase
  // camera mid-corner and the status bar sat over the lap counter.
  configureForTouch();
  runApp(const RacingApp());
}

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
  static const PerspectiveProjection _lens = PerspectiveProjection(
    fovYRadians: 1.05,
    near: 0.3,
    far: 1600.0,
  );
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

  /// Which circuit is being raced, how far into the season that is, and
  /// whether the screen is loading, racing, between one circuit and the next,
  /// or looking at a circuit — or a device — that would not open.
  ///
  /// **The game had one `const` asset path and no idea that anything ever
  /// ended.** A race could be won and nothing happened: no next circuit,
  /// nothing that remembered having been anywhere, and a car going round a
  /// finished race forever. See `race_cubit.dart` for why this is a cubit
  /// rather than fields beside this one, the way it used to be.
  late final RaceCubit _raceCubit = RaceCubit(RaceProgress());

  Circuit get _circuit => _raceCubit.circuit;

  /// What is said across the screen between circuits, and at the end.
  ///
  /// Read from [_raceCubit] rather than held here: a [RaceOver] status is
  /// exactly "a circuit and what, if anything, comes after it", which is
  /// this line and nothing more.
  String? get _notice {
    final status = _raceCubit.state;
    return switch (status) {
      RaceOver(:final next) =>
        next == null ? 'Season complete' : '${next.title} next',
      _ => null,
    };
  }

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

  GhostKeeper _keeperFor(Circuit circuit) =>
      GhostKeeper(storage: defaultStorage('racing'), track: circuit.track);

  /// How far above the body's own origin each car is drawn, in metres.
  ///
  /// A car is simulated as a sphere whose centre floats `rideHeight` above the
  /// road, and a model's origin is wherever the person who exported it put it —
  /// this one's is at the top of the bodywork, so drawn at the sphere's centre
  /// the car was buried half a metre into the tarmac. The lift is worked out
  /// from the asset's own bounds rather than typed in, because the next model
  /// will have its origin somewhere else again.
  final List<double> _carLift = <double>[];

  /// Where each car is *drawn*, which is not where it last stepped to.
  ///
  /// The race steps sixty times a second and this display draws a hundred and
  /// twenty, so reading `car.position` puts every simulated position on screen
  /// for two frames and then jumps a whole step — the stutter
  /// [InterpolatedVector3] exists for. On a car it does not read as a stutter:
  /// the chase camera eases along the direction of travel every drawn frame and
  /// so absorbs the lengthwise part of it, leaving the vertical — suspension
  /// settling, camber, kerbs — strobing on its own. It looks like the car has
  /// two of itself, one slightly above the other.
  ///
  /// Only the position is blended. The basis is still taken from the newest
  /// step, because the heading turns slowly next to the way the body moves over
  /// its springs, and slerping a basis here would mean a second copy of the
  /// vehicle's own frame-building living in the application.
  final List<InterpolatedVector3> _carDraw = <InterpolatedVector3>[];

  final InputState _input = InputState();

  /// What the player has changed, and where it is kept.
  ///
  /// **This game had none of it**: no volumes, no rebinding, no way to turn
  /// anything down — the only settings it has ever had were the ones its author
  /// compiled in. The panel is shared with the other two games; what is here is
  /// the wiring and the two lists that are this game's own.
  /// **Routed to the screen, which it was not.** The seam has existed since
  /// `Storage` did and only the platformer used it; the default prints to a
  /// console no player has, so a settings document that would not read reset
  /// every binding in silence.
  late final SettingsFile _settingsFile = SettingsFile(
    appName: 'racing',
    onIssue: (String issue) {
      printIssue(issue);
      _issue = issue;
    },
  );

  /// The last thing that went wrong where a player could see it.
  String? _issue;
  late final GameConfig _config;
  late final SettingsCubit _settings;

  /// What the player has already told the operating system.
  Accommodations _system = const Accommodations();
  late final DesktopInput _devices = DesktopInput(
    state: _input,
    bindings: ownedBindings(_config, driveKeys),
  );

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
    routes: PadRoutes.driving(steerLeft: Drive.left, steerRight: Drive.right),
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

  /// How long since the last frame, and how long since the first.
  final FrameClock _frames = FrameClock();

  /// What a frame costs, printed when `FLUTTER3D_TIMINGS` asks. This is the
  /// game the player's probe is measured in — see `kPlayerProbe`.
  final FrameTimingLog _timings = FrameTimingLog(label: 'race');

  @override
  void initState() {
    // Settings before devices: the bindings a player saved are the ones the
    // keyboard should read from the first key press, not from the first rebind.
    _config = _settingsFile.read();
    // A config saved before this game read a controller has no `pad:` in it,
    // and nobody should have to delete their settings to plug one in. The
    // rebindings they did make are left alone.
    if (!PadInput.knowsPad(_devices.bindings)) padBindings(_devices.bindings);
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
    // Closed like [_settings], and the cubit unhooks itself from the season's
    // progress first — see `RaceCubit.close` for why the order matters.
    unawaited(_raceCubit.close());
    // **The line this one was missing.** The other two applications close
    // their devices here; without it the `PointerLock` state subscription
    // `DesktopInput` opens outlives the screen, and a hot restart leaves the
    // old one listening.
    unawaited(_devices.dispose());
    _keyboard.dispose();
    _ticker?.dispose();
    _timings.stop();
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
    _chase?.motion = _config.settingOf(
      'a11y.cameraMotion',
      _system.cameraMotion,
    );
  }

  Future<void> _open() async {
    final GraphicsDevice device;
    try {
      device = await openDevice(width: kRenderWidth, height: kRenderHeight);
    } catch (error) {
      if (mounted) _raceCubit.failed(error);
      return;
    }
    if (!mounted) return;
    _device = device;

    setState(() {
      try {
        _renderer = Renderer.create(device: device);
      } catch (error) {
        _raceCubit.failed(error);
      }
    });
    if (_renderer == null) return;

    _renderer?.addContributor(ParticleContributor(_particles));

    unawaited(_openAudio());

    // The ticker before the circuit, not after. Drawing has to start at once —
    // see [_scene] — and there is nothing to step until the circuit is read, so
    // the loop simply returns early until it is.
    _ticker = createTicker(_onTick)..start();
    _timings.start();
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
    if (speakers == null) return;
    if (!mounted) {
      // The screen is gone and `dispose` has already run past `_speakers`, so
      // the backend has to go down here — its own doc warns that an engine
      // left initialized blocks a later open().
      unawaited(speakers.backend.dispose());
      return;
    }

    setState(() {
      _speakers = speakers.backend;
      _audio = speakers.scene;
      // Any cars that were built while the device was opening got their voices
      // on the silent scene, and those are **replaced, not joined**: this used
      // to only add, so a circuit that loaded first ended up with two looping
      // sets — `_listen` driving the silent one and the real one playing an
      // idle nobody was updating.
      for (final voice in _voices) {
        voice.stop();
      }
      _voices.clear();
      for (final car in _cars) {
        _voices.add(CarVoice(scene: _audio, vehicle: car));
      }
    });
  }

  Future<void> _loadCircuit(GraphicsDevice device) async {
    try {
      // Started here and awaited below, so the model decodes while the circuit
      // is being read: the wait is the longer of the two rather than the sum.
      // Awaited before any car reaches the scene, which is what keeps a box
      // from ever being drawn — see [_loadCarModel].
      final carModel = _loadCarModel(device);

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
      // device: the road mesh, the cars and the scene they go in.
      final staged = stage(document, loaded.collision);
      final track = staged.track;
      final scene = loaded.scene;
      addTrackTo(scene, track, device: device);
      scene.add(_camera);

      // **Before the grid is formed, not after.** The field used to be lined up
      // as boxes and re-dressed when the model arrived, and on a cold start
      // that is a second or so of four parallelepipeds on the grid. Waiting
      // costs the same second, spent on a loading screen where a wait belongs.
      final asset = await carModel;
      // One asset, so one measurement of where the bodywork ends; the ride
      // height it is offset against is per car, because tuning is.
      final floor = asset == null ? 0.0 : -asset.localBounds.min.y;

      _cars.addAll(staged.cars);
      for (var i = 0; i < _cars.length; i++) {
        final SceneNode node;
        if (asset == null) {
          node = carBox(device, Looks.rival(i), name: 'car-$i');
          scene.add(node);
          _carLift.add(liftFor(_cars[i]));
        } else {
          // The player alone keeps the asset's own materials. Rivals ask for
          // copies, because [Looks.paint] writes a colour into them and shared
          // materials would paint the whole field — the player's car included —
          // whatever colour the last rival happened to wear.
          final instance = asset.instantiate(
            scene,
            name: i == 0 ? 'player' : 'rival-$i',
            shareMaterials: i == 0,
          );
          if (i != 0) Looks.paint(instance.meshes, Looks.carPaint(i));
          // `instantiate` has already put it in the scene.
          node = instance.root;
          // Put the model's lowest point on the road: the sphere's centre is a
          // ride height above the tarmac, and the model hangs from wherever its
          // own origin is.
          _carLift.add(floor - _cars[i].tuning.rideHeight);
          // **The player's bodywork reflects the track going past.** A probe
          // under the car's own node, so it goes where the car goes, refreshed
          // one face a frame so the cube is six frames behind at worst; the
          // car's own meshes are left out of it, or the probe would capture
          // the inside of the car. Rivals keep the sky alone: a probe per car
          // is a view of the circuit per car per frame, and nobody looks at a
          // rival's door closely enough to pay for it.
          if (i == 0 && kPlayerProbe) {
            final centre = (asset.localBounds.min + asset.localBounds.max)
              ..scale(0.5);
            final probe = ReflectionProbeNode(
              name: 'player probe',
              refreshFaceEveryFrame: true,
              // Reaches the player's own panels — the car is under four and
              // a half metres long — and not a rival lined up beside it.
              radius: 2.5,
              // Past the bodywork the exclusion already leaves out, so a
              // wheel arch a few centimetres from the probe does not fill a
              // face either.
              near: 0.5,
            )..setPosition(centre.x, centre.y, centre.z);
            probe.excluded.addAll(instance.meshes);
            node.add(probe);
          }
        }
        _carNodes.add(node);
        // Both endpoints start on the grid slot. Left at zero the first drawn
        // frame would blend from the origin, which is a car arriving at the
        // start line from under the scenery.
        _carDraw.add(InterpolatedVector3(initial: _cars[i].position));
      }

      _ghosts = _keeperFor(_circuit)..load();
      _ghostCar = GhostCar.build(device, scene, model: asset);

      {
        for (final car in _cars) {
          _voices.add(CarVoice(scene: _audio, vehicle: car));
        }
      }

      // The one light in the level was written from this same preset by the
      // generator, so the sun the shadows fall from and the sun the sky glows
      // around are the same sun by construction rather than by agreement.
      scene.ambientIntensity = document.sky.ambientIntensity;

      // **The circuit reflects the sky it is raced under, and costs nothing to
      // do it.** A sky is already a function from direction to colour, which is
      // exactly what an environment map holds — so there is no photograph to
      // ship and no asset to author. Built from the preset the document names,
      // so a circuit raced at dawn reflects dawn.
      //
      // The car is the reason: it is a metal, and a metal has no diffuse
      // response at all, so before this it was lit by the sun alone and read as
      // very nearly black wherever the sun was not.
      //
      // Built here, once per circuit, because it is a convolution over six
      // faces and belongs at a load rather than in a frame.
      _sky = document.sky;
      final environment = EnvironmentMap.fromSky(device, _skySettings());
      if (environment != null) {
        scene
          ..environment = environment.texture
          ..environmentLevels = environment.levels;
      }

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
      // After the render fields are in place, not before: a status of
      // `Racing` is a promise that there is something to draw.
      _raceCubit.ready();
    } catch (error, stack) {
      debugPrint('circuit: $error\n$stack');
      if (mounted) _raceCubit.failed(error);
    }
  }

  /// Swaps the player's box for the model, if it loads.
  ///
  /// If it does not, the game is still playable as a box — a car that will not
  /// start because an asset moved is worse than a car that is a rectangle.
  /// The player has finished the race. On to the next circuit, or that was the
  /// season.
  void _finishedHere() {
    // Deciding what comes next and saying so are both `_raceCubit.finish()`'s
    // job now — see `RaceProgress.finish` for the season-complete clause this
    // used to hold directly.
    final next = _raceCubit.finish();
    if (next != null) unawaited(_moveOn(next));
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
    _carDraw.clear();
    _ghostCar = null;

    // Leaves the circuit that was just won and starts reading `next` — which
    // is also what clears [_notice], by moving the status out of `RaceOver`.
    _raceCubit.moveOn(next);

    setState(() {
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

  /// Decodes and uploads the car every car on the grid is drawn from.
  ///
  /// **One asset, four instances.** A rival is another
  /// [ModelAsset.instantiate] of this, which shares the uploaded meshes and
  /// textures. Loading the file per car would put four copies of the same forty
  /// meshes on the GPU to draw the same shape four times.
  ///
  /// **Returns null rather than throwing.** The circuit load awaits this before
  /// it puts a car anywhere, so a model that cannot be read has to leave a race
  /// that still runs — as a grid of boxes, which is now the failure case and
  /// not something anybody sees on the way to a normal start.
  Future<ModelAsset?> _loadCarModel(GraphicsDevice device) async {
    try {
      final document = await decodeModelInIsolate(
        ModelLoadRequest(source: const BundleAssetSource(kCarModel)),
      );
      return await ModelAsset.fromDocument(
        document,
        device: device,
        name: kCarModel,
      );
    } catch (error) {
      debugPrint('cars: no model, so boxes ($error)');
      return null;
    }
  }

  void _onTick(Duration _) {
    // The ticker's argument is the frame's scheduled time, not the present;
    // `FrameClock` says why the wall is measured instead.
    final dt = _frames.tick();

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
    _loop.advance(dt);
    _pace.note(
      dropped: _loop.clock.droppedSteps,
      dt: dt,
      stepSeconds: _loop.clock.stepSeconds,
    );

    if (_celebrateFor > 0.0) {
      _celebrateFor = (_celebrateFor - dt).clamp(0.0, 4.0);
    }
    if (_refusedFor > 0.0) _refusedFor = (_refusedFor - dt).clamp(0.0, 2.0);

    // **What the loop accepted, not what the clock said.** A frame longer than
    // the loop's own limit is a window that was dragged or a laptop that was
    // shut; the simulation refuses it, and anything drawn beside the simulation
    // has to refuse the same amount or it ends up showing a world that has not
    // happened yet.
    _particles.advance(_loop.lastFrame);
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
    _readPitStop();
    _driveTheRest(simulation, race);
    simulation.step(stepSeconds);

    // Where the step left each car, kept beside where the step before left it,
    // so the frames drawn between the two have something to blend. Here rather
    // than in `_place`: this runs once per simulated step, and `_place` runs
    // once per drawn frame — pushing there would overwrite the previous value
    // with the current one and blend a step against itself.
    for (var i = 0; i < _cars.length; i++) {
      _carDraw[i].push(_cars[i].position);
    }

    // Recorded always, not only when the lap is going to be a good one:
    // whether it was the best is knowable when it ends, and by then it is too
    // late to have been writing it down. **Against the record, not against the
    // session's best.** A race begins with no laps in it, so
    // the lap somebody drives while getting used to the car was the best one by
    // definition, and it used to take the place of a record that stood from
    // another evening. The keeper compares against the disk now, and says when
    // the disk changed.
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
  void _padRebinding() => _presses.offer(
    _pad,
    _settings,
    menuButton: PadButton.start,
    // The same clause Escape and the gear run — the keys the car was holding
    // are let go, or it comes back accelerating into a wall.
    opening: _input.clear,
  );

  /// The pad's presses, told apart from its holds.
  final PadPresses _presses = PadPresses();

  /// The player's keys, as a car's controls.
  /// The pit stop: fresh tyres and a car put back together.
  ///
  /// Read on the step rather than in the key handler, because whether it is
  /// allowed depends on how fast the car is going — which is a fact the
  /// simulation owns and a widget would have to go and fetch.
  ///
  /// One key for both, because a car that has stopped for repairs is a car that
  /// gets tyres. A driver who wants the set they are already on presses it
  /// three times, which is free while standing still.
  void _readPitStop() {
    if (!_input.pressed(Drive.tyres)) return;
    final car = _cars[0];
    if (car.pitStop(Tyres.after(car.tyres))) {
      _audio.play(Sounds.checkpoint, _ears.position);
      _refusedFor = 0.0;
    } else {
      // Said rather than ignored. A key that does nothing and says nothing is a
      // key a player decides is broken.
      _refusedFor = 2.0;
    }
  }

  /// How long the tyre line goes on saying the car has to stop first.
  double _refusedFor = 0.0;

  void _readDriver(RacingSimulation simulation) {
    // **How hard, not whether.** `value` is a key's full press and a trigger's
    // actual travel, so the same three lines drive a car from a keyboard and
    // from a controller — and a wheel a third over asks for a third of the
    // lock, which is the whole reason `VehicleInput` holds doubles.
    final input = simulation.inputs[0];
    input
      ..throttle = _input.value(Drive.throttle)
      ..brake = _input.value(Drive.brake)
      ..handbrake = _input.held(Drive.handbrake)
      ..steer = _input.value(Drive.right) - _input.value(Drive.left);
  }

  void _driveTheRest(RacingSimulation simulation, RaceState race) {
    final ai = _ai;
    final track = _track;
    if (ai == null || track == null) return;

    final player = race.progress[0];
    for (var i = 1; i < _cars.length; i++) {
      // How far the player is up the road from this car, wrapped, which is what
      // the rubber band reads.
      var gap =
          player.progressAlong(track.length) -
          race.progress[i].progressAlong(track.length);
      if (gap.abs() > track.length / 2) {
        gap -= gap.sign * track.length;
      }
      ai.drive(_cars[i], simulation.inputs[i], others: _cars, playerGap: gap);
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
      // The blend of the last two steps, not the last one: see [_carDraw].
      _carDraw[i].read(_loop.alpha, _drawAt);
      _drawAt.addScaled(car.visualBasis.getColumn(1), _carLift[i]);
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
      _audio.play(
        race.countdown > 0.0 ? Sounds.count : Sounds.go,
        _ears.position,
      );
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
      tyres: _cars[0].tyres.name,
      tyresRefused: _refusedFor > 0.0,
      damage: _cars[0].damage,
      wrongWay: player.wrongWay,
      countdown: race.phase == RacePhase.countdown ? race.countdown : null,
      mode: race.mode,
      outline: _outline,
      carsOnMap: <Vector2>[
        for (final car in _cars) Vector2(car.position.x, car.position.z),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<RaceCubit, RaceStatus>(
    bloc: _raceCubit,
    builder: (BuildContext context, RaceStatus status) {
      if (status is RaceFailed) return DidNotStart(status.error);
      return _screen();
    },
  );

  /// Everything [build] used to return directly, once there is neither a
  /// cubit failure to show instead nor — see the check below — a renderer to
  /// draw this through yet.
  Widget _screen() {
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
          final settingsSay = settingsKeys(
            event,
            _settings,
            opening: _input.clear,
          );
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
            if (_race != null) RaceHud(readout: _readout(), issue: _issue),
            // A phone has no keyboard and this game had nothing else to offer
            // it: the wheel and the pedals, above the frame and below the
            // panel. Hidden while the settings are open, or a thumb reaching
            // for a slider holds the throttle down behind it.
            if (Playing.touch && _race != null && !_settings.state.isOpen)
              TouchDrive(
                state: _input,
                steerLeft: Drive.left,
                steerRight: Drive.right,
                throttle: Drive.throttle,
                brake: Drive.brake,
                handbrake: Drive.handbrake,
              ),
            SettingsOverlay(
              settings: _settings,
              mixer: _audio.mixer,
              bindings: _devices.bindings,
              config: _config,
              // Asked, not assumed. This said `false` while the same widget in
              // the other two games asked the pad — so a driver with a
              // controller plugged in read "Gamepad (none connected)" over the
              // sliders that set its dead zone.
              padConnected: _pad.isConnected,
              actions: rebindableActions,
              defaultBindings: driveKeys,
              opening: _input.clear,
              // **The licence asks for this and the game did not do it.** The
              // car is CC BY 4.0, whose text says attribution must appear
              // wherever the work does.
              credits: const CreditsSection(credits: Credits.models),
            ),
          ],
        ),
      ),
    );
  }
}
