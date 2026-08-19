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
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey, rootBundle;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_racing/bridge.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';
import 'src/hud.dart';
import 'src/looks.dart';
import 'src/sounds.dart';

const String _trackAsset = 'assets/tracks/ring.json';
const String _levelAsset = 'assets/tracks/ring_level.json';

/// How many cars line up, the player included.
const int _fieldSize = 4;
const int _lapsInARace = 3;

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
  late final DesktopInput _devices =
      DesktopInput(state: _input, bindings: _keys());
  /// The loop, rather than a bare `FixedStep`.
  ///
  /// **This game drove the clock itself and got none of the loop's services**:
  /// no pause, no `beginStep`/`endStep` around a step — so `InputState.pressed`
  /// never worked here at all — and no reading of the simulated time the clock
  /// refused to run.
  late final GameLoop _loop = GameLoop(input: _input, onStep: _driveOneStep);

  /// Whether the player has asked the game to stand still.
  ///
  /// Fed to [shouldPause] as its menu clause, because that is what it is: a
  /// statement about the player's attention that does not depend on any device.
  /// When this game grows a settings panel, the panel sets the same flag.
  bool _paused = false;

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
  AudioScene? _audio;
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
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _keyboard.dispose();
    _ticker?.dispose();
    for (final voice in _voices) {
      voice.stop();
    }
    unawaited(_speakers?.dispose());
    super.dispose();
  }

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
    final speakers = SoLoudBackend();
    try {
      await speakers.open();
    } catch (error) {
      debugPrint('audio: could not start SoLoud, playing silent ($error)');
      return;
    }
    if (!mounted) return;

    final scene = AudioScene(backend: speakers, maxVoices: 24);
    await scene.preload(Sounds.all);
    if (!mounted) return;

    setState(() {
      _speakers = speakers;
      _audio = scene;
      // Any cars that were built while the device was opening.
      for (final car in _cars) {
        _voices.add(CarVoice(scene: scene, vehicle: car));
      }
    });
  }

  Future<void> _loadCircuit(GraphicsDevice device) async {
    try {
      // The circuit and the scenery are two halves of one document, written by
      // one script and read by two loaders: the spline is this genre's and the
      // level is the engine's, which has read brushes since the first game.
      final text = await rootBundle.loadString(_trackAsset);
      final document = TrackDocument.fromJson(
        jsonDecode(text) as Map<String, Object?>,
      );
      final loaded = await const LevelLoader().load(
        _levelAsset,
        device: device,
        // This circuit places no entities — the scenery is brushes — so the
        // registry is empty rather than absent: the loader validates against
        // it, and an empty one is the statement that nothing is expected.
        registry: EntityRegistry(const <EntityKind>[]),
      );

      final track = document.track;
      final scene = loaded.scene;
      addTrackTo(scene, track, device: device);
      scene.add(_camera);

      final field = TrackField(track: track, world: loaded.collision);
      final race = RaceState(
        mode: RaceMode.race,
        track: track,
        racers: _fieldSize,
        laps: _lapsInARace,
      );

      final position = Vector3.zero();
      final forward = Vector3.zero();
      for (var i = 0; i < _fieldSize; i++) {
        track.startSlot(i, position, forward);
        final car = SphereVehicle(
          world: loaded.collision,
          ground: field,
          position: position.clone()..y += 0.6,
          headingYaw: math.atan2(forward.x, forward.z),
        );
        car.placeAt(
          car.position,
          car.headingYaw,
          trackDistance: track.centre.wrap(track.grid.s),
        );
        _cars.add(car);

        final node = carBox(device, Looks.rival(i), name: 'car-$i');
        scene.add(node);
        _carNodes.add(node);
        // The box is a metre tall and centred on its origin.
        _carLift.add(0.5 - car.tuning.rideHeight);
      }

      final audio = _audio;
      if (audio != null) {
        for (final car in _cars) {
          _voices.add(CarVoice(scene: audio, vehicle: car));
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
        _race = race;
        _outline = trackOutline(track);
        _simulation = RacingSimulation(
          collision: loaded.collision,
          vehicles: _cars,
          race: race,
        );
        _chase = ChaseCamera(world: loaded.collision, track: track);
        _ai = AiDriver(track: track);
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

    final race = _race;
    if (_simulation == null || race == null) return;

    _loop.paused = shouldPause(
      ready: _simulation != null,
      menuOpen: _paused,
      // This game never captures the pointer — it is driven from the keyboard —
      // so the pointer is not the gate here and saying otherwise would freeze
      // it on every desktop build.
      pointerIsTheGate: false,
      pointerHeld: false,
      padConnected: false,
    );
    _loop.advance(dt.clamp(0.0, 0.25));
    _pace.note(
      dropped: _loop.clock.droppedSteps,
      dt: dt,
      stepSeconds: _loop.clock.stepSeconds,
    );

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
  }

  /// The player's keys, as a car's controls.
  void _readDriver(RacingSimulation simulation) {
    final input = simulation.inputs[0];
    input
      ..throttle = _input.held(_Drive.throttle) ? 1.0 : 0.0
      ..brake = _input.held(_Drive.brake) ? 1.0 : 0.0
      ..handbrake = _input.held(_Drive.handbrake)
      ..steer = (_input.held(_Drive.right) ? 1.0 : 0.0) -
          (_input.held(_Drive.left) ? 1.0 : 0.0);
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
    final audio = _audio;
    if (audio == null) return;

    for (var i = 0; i < _voices.length && i < race.progress.length; i++) {
      _voices[i].update(offRoad: race.progress[i].offRoad);
    }

    final player = race.progress[0];
    if (race.countdownTickThisStep) {
      audio.play(race.countdown > 0.0 ? Sounds.count : Sounds.go, _ears.position);
    }
    if (player.bestLapThisStep) {
      audio.play(Sounds.best, _ears.position);
    } else if (player.lapCompletedThisStep) {
      audio.play(Sounds.lap, _ears.position);
    }
    if (player.checkpointThisStep) {
      audio.play(Sounds.checkpoint, _ears.position);
    }

    // Along the camera's own forward rather than through a yaw: `aimAt` reads
    // an angle as a first-person camera's, and a chase camera is not one.
    final chase = _chase;
    if (chase != null) {
      _ears.aimAlong(chase.eye, chase.target - chase.eye);
    }
    audio.update(_ears);
  }

  RaceReadout _readout() {
    final race = _race!;
    final player = race.progress[0];
    return RaceReadout(
                behind: _pace.behind,
                paused: _paused,
      speed: _cars[0].speed,
      lap: player.lap,
      laps: race.laps,
      position: race.positionOf(0),
      racers: race.progress.length,
      lapTime: player.lapTime,
      bestLap: player.bestLap,
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
          // **This game could not be paused at all.** Escape does it now, and
          // it is the same clause a settings panel will set when there is one:
          // a statement about where the player's attention is, which does not
          // depend on any device.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            setState(() => _paused = !_paused);
            // The keys the car was holding are let go, or it comes back
            // accelerating into a wall.
            _input.clear();
            return KeyEventResult.handled;
          }
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
