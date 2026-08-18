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
import 'package:flutter/services.dart' show LogicalKeyboardKey, rootBundle;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_racing/bridge.dart';
import 'package:flutter3d_racing/flutter3d_racing.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';
import 'src/hud.dart';
import 'src/looks.dart';
import 'src/scene_surface.dart';
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
  /// The view, with a sky rather than a void behind it.
  ///
  /// `RenderView` clears to a very dark blue by default, which is right for a
  /// dungeon and wrong for anywhere outdoors: it put the horizon of a circuit
  /// against something darker than the tarmac, so the road and the sky were the
  /// same colour and the track appeared to end at the fog. Matched to the fog,
  /// so the far side of the lap fades into the sky instead of into a hole.
  late final RenderView _view = RenderView(
    camera: _camera,
    clearColor: Vector4(_sky.x, _sky.y, _sky.z, 1.0),
  );

  static final Vector3 _sky = Vector3(0.62, 0.71, 0.82);

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
  final FixedStep _step = FixedStep();

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

      setState(() {
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

    final simulation = _simulation;
    final race = _race;
    if (simulation == null || race == null) return;

    final steps = _step.advance(dt.clamp(0.0, 0.25));
    for (var i = 0; i < steps; i++) {
      _readDriver(simulation);
      _driveTheRest(simulation, race);
      simulation.step(_step.stepSeconds);
    }

    _place(dt);
    _listen(race);
    setState(() {});
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
        onKeyEvent: (FocusNode node, KeyEvent event) =>
            _devices.handleKeyEvent(event),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            SceneSurface(
              renderer: renderer,
              scene: scene,
              view: _view,
              // Matched to the sky the level was written with, and dense enough
              // that the far side of a kilometre of circuit fades rather than
              // ending in mid-air.
              fog: FogSettings(color: _sky, density: 0.0016),
              onBeforeFrame: () {},
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
