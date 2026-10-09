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

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey, rootBundle;
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_kit/ghost.dart' show Ghost;
import 'package:flutter3d_game_kit/soundtrack.dart'
    show CueSheet, SoundtrackPlugin;
import 'package:flutter3d_game_racing/bridge.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_game_ui/flutter3d_game_ui.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show preparePhysics, usePhysics;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart' as stereo;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pad_input/pad_input.dart';

import 'src/backend.dart';
import 'src/circuits.dart';
import 'src/controls.dart';
import 'src/credits.dart';
import 'src/elements.dart';
import 'src/ending.dart';
import 'src/ghost_car.dart';
import 'src/hud.dart';
import 'src/looks.dart';
import 'src/net_race_screen.dart';
import 'src/photo_mode.dart';
import 'src/race_cubit.dart';
import 'src/race_readout.dart';
import 'src/reactions.dart';
import 'src/roadside.dart';
import 'src/sounds.dart';
import 'src/staging.dart';
import 'src/title_card.dart';

/// `net-03`'s relay — `bin/relay.dart` in `flutter3d_net`, wherever one is
/// actually running. Defaults to a loopback address because no relay ships
/// deployed anywhere this game can name for itself; a real one is a
/// `--dart-define=relay=ws://host:port/` away, the same override pattern
/// `apps/flutter3d_editor`'s `kLevelPath` already uses for "something only
/// the person launching this build knows".
final Uri kRelayBase = Uri.parse(
  const String.fromEnvironment('relay', defaultValue: 'ws://127.0.0.1:8199/'),
);

/// `rp-04`'s own build stamp, the same convention `flutter3d_demo_dungeon`
/// established: whatever the release process passes in, `dev` otherwise.
const String _buildStamp = String.fromEnvironment(
  'FLUTTER3D_BUILD_STAMP',
  defaultValue: 'dev',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The run's physics, chosen once: the core, which the browser fetches as
  // WebAssembly, or the reference where it will not start. Every track's
  // world is put on it as it loads.
  await preparePhysics();
  // **This game had none of it.** The other two locked to landscape and hid
  // the system bars on a handset; this one, which has touch controls and is
  // meant to be played on a phone, did neither — so a tilt reframed the chase
  // camera mid-corner and the status bar sat over the lap counter.
  lockLandscapeForTouch(_playing);
  // Settings before the screen: the bindings a player saved are the ones the
  // keyboard should read from the first key press, not from the first rebind.
  final unread = <Issue>[];
  final config = await SettingsFile(
    appName: 'racing',
    defaultActions: driveActionMap,
    onIssue: (Issue reported) {
      printIssue(reported);
      unread.add(reported);
    },
  ).read();
  runApp(RacingApp(config: config, configIssue: unread.lastOrNull?.message));
}

/// How this build is played — fingers or keys, a pointer that can be taken
/// — asked of the platform once, for the whole game.
final Playing _playing = Playing.ofPlatform();

class RacingApp extends StatelessWidget {
  const RacingApp({super.key, this.config, this.configIssue});

  /// What the player changed, read before the first frame; defaults when
  /// null.
  final GameSettings? config;

  /// Why [config] could not be read, if it could not.
  final String? configIssue;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Ring',
    debugShowCheckedModeBanner: false,
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      Flutter3dGameLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    home: RaceScreen(config: config, configIssue: configIssue),
  );
}

class RaceScreen extends StatefulWidget {
  const RaceScreen({super.key, this.config, this.configIssue});

  /// See [RacingApp.config].
  final GameSettings? config;

  /// See [RacingApp.configIssue].
  final String? configIssue;

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

  /// The grid the next circuit starts on — null for the first one of a
  /// season, and for one started over, both of which start level. Computed
  /// in [_finishedHere] from the circuit that just ended, while its
  /// [RaceState] is still the one this screen holds and before [_leaveCircuit]
  /// lets it go.
  List<int>? _nextGridOrder;

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
    fovY: 1.05,
    near: 0.3,
    far: 1600.0,
  );
  final CameraNode _camera = CameraNode(projection: _lens);

  /// `ls-x-02`: `?stereo=1` opens the same race in `StereoViewer` instead of
  /// on the flat screen — [_camera] is still built either way (an unused one
  /// costs nothing, `flutter3d_template_app`'s own attempt at this same
  /// pattern already made that call), but only one of [_camera]/[_rig] is
  /// ever the stage a frame is actually drawn from. `near`/`far` match
  /// [_lens]'s own — the rig's own defaults (0.05/500.0) would clip this
  /// circuit's own kilometre-round track well before the horizon.
  late final stereo.StereoRig? _rig = Uri.base.queryParameters['stereo'] == '1'
      ? stereo.StereoRig(near: _lens.near, far: _lens.far)
      : null;

  /// Whichever of [_camera]/[_rig]'s own stage is the one actually driven
  /// every frame — added to the scene, moved by the chase camera, and (in
  /// stereo) the anchor the HUD panel rides along with.
  SceneNode get _stage => _rig?.stage ?? _camera;

  /// `ls-x-02`'s own showcase: [StereoHudPanel] on a `WidgetSurface`, a child of
  /// [_rig]'s own stage — null in flat mode, where [RaceHud] stays the
  /// ordinary Flutter overlay it always was. Built once [_loadCircuit] has a
  /// device to build it with.
  WidgetSurface? _hudPanel;
  final ValueNotifier<RaceReadout?> _hudReading = ValueNotifier<RaceReadout?>(
    null,
  );

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
    clearColorSrgb: _skyColour(),
  );

  /// The air the circuit is raced under: the Earth's, as the engine's
  /// physical sky has it.
  static const PhysicalSky _air = PhysicalSky();

  /// The sky over the circuit: the air, lit by the sun where the preset's
  /// hour puts it. One model for everything that shows the air — the sky
  /// drawn behind the circuit, the haze its far side fades into
  /// ([_haze]), the sunlight on it ([_sunlight]) and what the car reflects
  /// — so none of them can drift from the others.
  SkySettings _skySettings() => SkySettings(
    enabled: true,
    physical: _air,
    directionToSun: _sky.directionToSun,
  );

  /// The haze along the camera's gaze: the air's own light at the horizon
  /// that way, which the far side of the circuit fades into.
  Vector3 _haze() => _skySettings().sample(Vector3(_gaze.x, 0.0, _gaze.z));

  /// Gives the circuit's sun the colour the air leaves of sunlight at the
  /// hour it is raced: white at noon, gold at dawn.
  void _sunlight(Scene scene) {
    final color = _air.sunlight(_sky.directionToSun);
    for (final light in scene.lights) {
      if (light.type == LightType.directional) {
        light.color = color.toLinearColor();
      }
    }
  }

  Vector4 _skyColour() {
    final color = _sky.colorAt(_gaze);
    return Vector4(color.x, color.y, color.z, 1.0);
  }

  /// The one [RenderSettings] this game draws with — pulled out of `build`
  /// so [_rig]'s own [StereoSurface] and the flat [SceneSurface] read the
  /// same fog, exposure, sky and shadows rather than two settings blocks a
  /// future edit could quietly let drift apart. `.forStereo()` is applied by
  /// each caller separately, not here: only the stereo path wants it.
  RenderSettings _raceSettings() => RenderSettings(
    // Not a colour anybody typed: the haze at the horizon, brightened
    // towards the sun along the direction the camera is looking. It is the
    // same arithmetic the sky above is drawn with, so the far side of the
    // lap fades into the background instead of into a band of a slightly
    // different grey.
    fog: FogSettings(color: _haze().toLinearColor(), density: _sky.fogDensity),
    // The hour of the day changes it: a low sun puts far less light on a
    // circuit than a high one, and one exposure through both is either a
    // washed-out noon or a dusk nobody can see the road in.
    exposure: _sky.exposure,
    sky: _skySettings(),
    // Three cascades over a circuit a kilometre round. One map over that is
    // metres of world per texel, which draws a car's own shadow as a slab
    // beside it; three tiles put the near one over the part of the track
    // anybody is looking at.
    //
    // Both faces recorded, the engine's default. The dark ribbons along the
    // far verges under a low sun are the barriers' shadows: traced against
    // the circuit's own triangles they are where the sun is blocked, and
    // recording only the faces turned to the sun lost them, since a barrier
    // is one-sided and faces the road.
    shadows: const ShadowSettings(
      cascades: kShadowCascades,
      resolution: kShadowResolution,
    ),
    // The player's colour vision, from the settings panel.
    look: _vision?.of(_config) ?? const LookSettings(),
  );

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

  /// P stops the race and hands the player a camera — see `photo_mode.dart`.
  final PhotoMode _photo = chasePhotoMode();
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

  /// The water in the circuit's low spots, the wrecks a hard crash leaves
  /// burning and the dust and smoke the cars throw up — in a world of its
  /// own, which reads the race and never writes to it. One a circuit; null
  /// between circuits.
  TrackElements? _elements;

  /// Whether this is a phone, which draws less of the water and the fires.
  static bool get _handheld =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

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

  /// Where this game keeps what it keeps between launches: the ghosts, and
  /// the player's answers about their data. Not the season, which is one
  /// sitting — see `season_test.dart`.
  final Storage _storage = defaultStorage('racing');

  /// What the player is asked about their data. No run to keep in the
  /// cloud — a season is one sitting — so that question says so; finished
  /// races go to the server only if the player says yes.
  late final GameCloud _cloud = GameCloud(
    game: 'racing',
    storage: _storage,
    server: const String.fromEnvironment('FLUTTER3D_CLOUD'),
    policy: '2026-10',
  );

  Circuit get _circuit => _raceCubit.circuit;

  /// What is said across the screen between circuits, and at the end.
  ///
  /// Read from [_raceCubit] rather than held here: a [RaceOver] status is
  /// exactly "a circuit and what, if anything, comes after it", which is
  /// this line and nothing more.
  ///
  /// The precedence between the two is `raceNotice`, in `race_readout.dart`,
  /// so that it can be asserted without a window. A caption rather than a
  /// sound for the respawn because there is no asset for one — nothing
  /// `tool/make_sounds.py` writes would do.
  /// **The end of the season is no longer one of them.** It used to be the
  /// second half of this switch — `seasonCompleteNotice` written across a race
  /// that kept running underneath — and it is a whole screen now, `SeasonEnding`,
  /// which is where the same sentence is read from. A caption behind it would
  /// be the game saying it twice.
  String? get _notice => raceNotice(
    betweenCircuits: switch (_raceCubit.state) {
      RaceOver(next: final Circuit next) => '${next.title} next',
      _ => null,
    },
    justRespawned: _respawnFor > 0.0,
  );

  /// Whether the season has been finished and the last race is only still
  /// running because nothing stops it.
  ///
  /// What R and the tap layer are gated on. `RaceOver` with somewhere to go
  /// next is not this: the screen is already on its way to the next circuit,
  /// and a restart offered for that second and a half throws away four won
  /// circuits by accident.
  bool get _seasonIsOver => switch (_raceCubit.state) {
    RaceOver(:final next) => next == null,
    _ => false,
  };

  /// Whether the player has asked to drive yet, which takes the title card
  /// down.
  ///
  /// Once a session and never again: a card that comes back every time the
  /// keyboard is let go is a card in the middle of a race. See [TitleCard] for
  /// why the race waits behind it rather than running under it.
  bool _started = false;

  /// Takes the title card down, the first time the player asks to drive.
  void _begin() {
    if (_started) return;
    // **The audio opens here rather than at launch**, which is the browser's
    // rule rather than a preference: a page may not make a sound until the
    // player has done something, and this game spent that permission in
    // `_open` before the player had given it — so the first engine note of the
    // first race was the one that got refused. This is the first key, touch or
    // pad button in every build, which is the gesture the browser waits for.
    unawaited(_openAudio());
    setState(() => _started = true);
  }

  /// How long the respawn caption stays up.
  ///
  /// Two seconds, on the wall clock like [_celebrateFor] and for the same
  /// reason: it is something being read, not something being driven.
  double _respawnFor = 0.0;

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
  Ghost? _ghostCar;

  GhostKeeper _keeperFor(Circuit circuit) =>
      GhostKeeper(storage: _storage, track: circuit.track);

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

  /// `rp-04`'s last ten seconds, every step of them — the same window and the
  /// same reasoning as `flutter3d_demo_dungeon`'s own `_rewind`.
  final RewindBuffer _rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);

  /// `rp-02`'s door onto this run, over the VM service: through the loop
  /// and its snapshots, so whichever race the plugin is stepping is the one
  /// rewound.
  late final RunTimeline _timeline = RunTimeline(rewind: _rewind, loop: _loop);

  /// `rp-04`'s "send this run", called remotely rather than from a button
  /// this game draws itself — the last few seconds `_rewind` has kept, as
  /// plain JSON. Null (and the extension answers with an error) when there
  /// is nothing to report yet, the same case `bugReportTape` itself returns
  /// null for.
  ///
  /// **The `levelHash` is the demo's, not one computed here.** `TrackDocument`
  /// does not write JSON back and does not give a `Level` the way the other
  /// genres' `Demo` rows hash — `rp-01`'s own finding — and reading the raw
  /// track document again just to hash it would make this callback
  /// asynchronous. [_beginDemo] is handed the digest of the JSON
  /// `_loadCircuit` had already decoded, so this names the same circuit the
  /// same way for nothing; empty only before the first circuit is ready.
  Map<String, Object?> _remoteBugReport() {
    // The start as the run's own snapshot, which is what a `.f3drun` holds.
    final report = bugReportTape(_rewind, part: RacingPlugin.id);
    if (report == null) {
      throw StateError('nothing has been recorded yet');
    }
    return <String, Object?>{
      'level': _circuit.track,
      'levelHash': _circuitHash ?? '',
      'start': report.start.toJson(),
      'tape': report.tape.toJson(),
      'buildStamp': _buildStamp,
      'platform': defaultTargetPlatform.name,
    };
  }

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
    defaultActions: driveActionMap,
    onIssue: (Issue reported) {
      printIssue(reported);
      _issue = reported.message;
    },
  );

  /// The last thing that went wrong where a player could see it.
  String? _issue;

  /// The player's settings as they are now: replaced on every change, by
  /// [_applyConfig].
  late GameSettings _config;

  /// The colour table for the player's colour vision. See
  /// `ColorVisionLook`.
  ColorVisionLook? _vision;
  late final GameSettingsController _settings;

  /// What the player has already told the operating system.
  Accommodations _system = const Accommodations();
  late final DesktopInput _devices = DesktopInput(
    state: _input,
    // The player's map, or the game's own: the one map the keyboard, the
    // pad and the settings screen hold.
    actions: _config.actionsOr(_firstLaunchControls),
  );

  /// What a first launch starts with: the keys alone, as before, because
  /// [initState] adds the pad's half to any table that has none — a fresh
  /// one and one saved before the pad existed alike.
  static ActionMap _firstLaunchControls() =>
      ActionMap(actions: driveActions, buttons: driveKeys());

  /// The controller, which this game did not read.
  ///
  /// **Everything it needs was already written.** `VehicleInput` has held a
  /// throttle, a brake and a steering angle as `double` since the genre package
  /// existed, and the pad's driving bindings were written for a game that
  /// never asked for them — so a wheel that is half over and a trigger that is a third down
  /// went to a game reading `held ? 1.0 : 0.0`.
  late final PadInput _pad = PadInput(
    state: _input,
    // One map for both devices, because a player's bindings are one file.
    actions: _devices.actions,
  )..applySettings(_config);

  /// `rp-01`/`rp-04`: this game's own `.f3drun` files, on disk. The dungeon's
  /// and the platformer's own field, mirrored — see either's `_beginDemo`/
  /// `_endDemo` for the mechanism this repeats rather than reinvents.
  DemoFile? _demos;

  /// The circuit being written down: its start, the loop's input, journal
  /// and event digests ([DemoRecording.attach]), its checkpoints and where
  /// the cars were.
  DemoRecording? _demo;

  /// The digest of the circuit raced now, kept past its recording for
  /// [_remoteBugReport].
  String? _circuitHash;

  /// Starts writing the circuit down, from the grid.
  ///
  /// **No mid-circuit resume to start it later from**, unlike the other two
  /// games: a season has no snapshot of its own (see [RaceProgress]'s own
  /// doc comment for why), so a circuit always begins here, once, right after
  /// [_loadCircuit] puts a simulation in [_simulation].
  void _beginDemo(String circuit, String circuitHash, RacingSimulation sim) {
    _endRecording();
    _circuitHash = circuitHash;
    final start = sim.save();
    _demo = DemoRecording(
      physics: usePhysics(),
      level: circuit,
      levelHash: circuitHash,
      start: start,
      seed: start.data.integer('random'),
      simulation: racingSimulationVersion,
      // Beside the tape, where each car was every few steps: what a build on
      // another simulation still shows of the race.
      bodies: () => <BodyPose>[
        for (var i = 0; i < _cars.length; i++)
          BodyPose(
            'car#$i',
            _cars[i].position,
            Quaternion.fromRotation(_cars[i].visualBasis),
          ),
      ],
    )..attach(_loop);
  }

  /// Stops the demo's recording.
  DemoRecording? _endRecording() {
    final demo = _demo;
    demo?.detach();
    _demo = null;
    return demo;
  }

  /// Writes the circuit down once it is won.
  ///
  /// **Only once, and only here.** A circuit that is not raced to the flag —
  /// the season abandoned mid-lap for another one — is not a run anybody
  /// would replay, and this game has no restart that reaches one still in
  /// progress: [_startOver] is only ever offered once the season is over or a
  /// circuit failed to load, both moments after this has already run or
  /// never started.
  void _endDemo() {
    final recording = _endRecording();
    if (recording == null) return;
    final demo = recording.demo(
      buildStamp: _buildStamp,
      platform: defaultTargetPlatform.name,
    );
    unawaited(_demos?.write(demo));
    // To the server too, if the player said runs may go.
    unawaited(_cloud.send(demo));
  }

  /// What the race's moments sound like: the countdown, a checkpoint, a lap
  /// and a best lap — the player's, heard where the ears are.
  ///
  /// **Played by [_cueSounds] off the bus's frame channel**, once a frame
  /// after the frame's steps: the frame `_listen` played them in. Every step
  /// of the frame is heard now, where `_listen` read only the last step's
  /// events and lost a chime that landed on the first of two.
  ///
  /// A lap that set the best is heard as the best alone. [LapCompleted]
  /// comes before [BestLapSet] in the step, so the lap is only noted here
  /// and `_listen` plays it, in the same frame, when no best came with it.
  late final CueSheet _cues = CueSheet()
    ..on<CountdownTicked>(
      (CountdownTicked event, List<Heard> out) => out.add(
        Heard(event.remaining > 0 ? Sounds.count : Sounds.go, _ears.position),
      ),
    )
    ..on<CheckpointPassed>((CheckpointPassed event, List<Heard> out) {
      if (event.isPlayer) out.add(Heard(Sounds.checkpoint, _ears.position));
    })
    ..on<LapCompleted>((LapCompleted event, List<Heard> out) {
      if (event.isPlayer) _lapHeard = true;
    })
    ..on<BestLapSet>((BestLapSet event, List<Heard> out) {
      if (!event.isPlayer) return;
      _bestHeard = true;
      out.add(Heard(Sounds.best, _ears.position));
    })
    ..on<Respawned>((Respawned event, List<Heard> out) {
      if (event.isPlayer) _respawnHeard = true;
    });

  /// What [_cues] noted this frame, for `_listen` to act on.
  bool _lapHeard = false;
  bool _bestHeard = false;
  bool _respawnHeard = false;

  late final SoundtrackPlugin _cueSounds = SoundtrackPlugin(
    _cues,
    scene: () => _audio,
  );

  /// The race said to a screen reader: the count, the player's laps, a best
  /// lap and the flag.
  final SpokenEvents _spoken = SpokenEvents(<Spoken<BusEvent>>[
    Spoken<CountdownTicked>(
      (CountdownTicked event) =>
          event.remaining > 0 ? '${event.remaining}' : 'Go.',
    ),
    Spoken<LapCompleted>(
      (LapCompleted event) =>
          event.isPlayer ? 'Lap ${event.racer.lap} done.' : null,
    ),
    Spoken<BestLapSet>(
      (BestLapSet event) => event.isPlayer ? 'Best lap.' : null,
    ),
    Spoken<RacerFinished>(
      (RacerFinished event) => event.isPlayer ? 'Finished.' : null,
    ),
  ]);

  /// The genre, installed in [_loop]: it steps whichever race [_simulation]
  /// holds, and puts the race's events on the loop's bus.
  final RacingPlugin _racing = RacingPlugin();

  /// The engine's loop, which owns the frame.
  ///
  /// **This game drove the clock itself and got none of the loop's services**:
  /// no pause, no `beginStep`/`endStep` around a step — so `InputState.pressed`
  /// never worked here at all — and no reading of the simulated time the clock
  /// refused to run.
  ///
  /// A step runs, by phase, exactly what `_driveOneStep` ran in one call, in
  /// the same order, so a tape and a ghost recorded before replay to the bit:
  ///
  /// * `input` — `racing_app.drive`: the player's keys, the pit stop, the
  ///   rivals' AI (the rewind's keyframes are the loop's own captures, taken
  ///   by the buffer attached to it);
  /// * `physics` — `racing.step`, the plugin's: the race's own step;
  /// * `publish` — `racing_app.read`: the demo's checkpoint, the drain, the
  ///   wrecks, the cars' interpolation, the ghost, what the step showed and
  ///   sounded, and the flag.
  ///
  /// The frame's work after the steps runs in the frame phases, in the order
  /// `_onTick` ran it: the clocks and the particles in `animate`; in `camera`
  /// the cars and the camera placed, then the water and the wrecks from that
  /// eye, then what the step said heard from the ears placed with it.
  late final EngineLoop _loop = _buildLoop();

  EngineLoop _buildLoop() {
    final loop = EngineLoop(
      input: _input,
      plugins: <Flutter3dPlugin>[_racing, _cueSounds, _spoken],
      registries: <PluginRegistry>[EntityKinds()],
    );
    // The last ten seconds, kept as the loop's own captures.
    _rewind.attach(loop);
    // What the step said, read once at its end: see [_stepEnded].
    loop.onStepEnd(_stepEnded);
    loop
      ..addSystem('racing_app.drive', LoopPhase.input, _beforeStep)
      ..addSystem('racing_app.read', LoopPhase.publish, _afterStep)
      ..addSystem('racing_app.clocks', LoopPhase.animate, _clocks)
      ..addSystem(
        'racing_app.particles',
        LoopPhase.animate,
        (LoopContext frame) => _particles.advance(frame.dt),
        after: <String>['racing_app.clocks'],
      )
      ..addSystem(
        'racing_app.place',
        LoopPhase.camera,
        (LoopContext frame) => _place(frame.realDt),
      )
      ..addSystem(
        'racing_app.elements',
        LoopPhase.camera,
        _elementsFrame,
        after: <String>['racing_app.place'],
      )
      ..addSystem('racing_app.listen', LoopPhase.camera, (LoopContext frame) {
        final race = _race;
        if (race != null) _listen(race);
      }, after: <String>['racing_app.elements']);
    return loop;
  }

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
  AudioBackend? _speakers;

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
    _config = widget.config ?? const GameSettings();
    _issue = widget.configIssue;
    // A config saved before this game read a controller has no `pad:` in it,
    // and nobody should have to delete their settings to plug one in. The
    // rebindings they did make are left alone.
    if (!PadInput.knowsPad(_devices.actions)) {
      padBindings(_devices.actions.buttons);
    }
    // The stick steers through the steering's two halves, bound as buttons
    // with a magnitude, so a half-over stick steers half; a map saved before
    // the stick was a binding gains it here.
    PadInput.addDrivingDefaultsTo(
      _devices.actions,
      steerLeft: Drive.left,
      steerRight: Drive.right,
    );
    _settings = GameSettingsController(
      settings: _config,
      actions: _devices.actions,
      file: _settingsFile,
      apply: _applyConfig,
    );
    _demos = DemoFile(appName: 'racing', onIssue: printIssue);
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
    _settings.dispose();
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
    _elements?.dispose();
    unawaited(_speakers?.dispose());
    _hudPanel?.dispose();
    _hudReading.dispose();
    super.dispose();
  }

  /// Puts the config onto everything that is playing.
  void _applyConfig(GameSettings config) {
    _config = config;
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
        _config.chosenValueOf(GameSettingKeys.cameraMotion) ??
        _system.cameraMotion;
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
    _vision = ColorVisionLook(device);

    setState(() {
      try {
        _renderer = Renderer.create(device: device);
      } catch (error) {
        _raceCubit.failed(error);
      }
    });
    if (_renderer == null) return;

    _renderer?.renderSteps.addContributor(ParticleContributor(_particles));
    if (!mounted) return;

    // The ticker before the circuit, not after. Drawing has to start at once —
    // see [_scene] — and there is nothing to step until the circuit is read, so
    // the loop simply returns early until it is.
    _ticker = createTicker(_onTick)..start();
    _timings.start();
    // `rp-02`: harmless where the VM service is off — `registerExtension`
    // just adds an entry nothing ever asks for.
    registerTimelineExtensions(_timeline, bugReport: _remoteBugReport);
    // `P12`: the frame this game draws, pass by pass and draw by draw.
    registerRenderExtensions(() => _renderer);
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
    final Speakers speakers;
    try {
      speakers = await openSpeakers(
        // The game's own sounds and the water's and the fires'.
        bank: SoundBank(<SoundDef>[...Sounds.all, ...ElementSounds.all]),
        mixer: _audio.mixer,
        maxVoices: 32,
      );
    } on AudioDeviceException {
      return;
    }
    if (!mounted) {
      // The screen is gone and `dispose` has already run past `_speakers`, so
      // the backend has to go down here — its own doc warns that an engine
      // left initialized blocks a later open().
      unawaited(speakers.dispose());
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
    // Which of the circuit's two documents is being read, for the catch below
    // to name. A variable rather than a constant because there are two of
    // them: naming the spline while the scenery is what would not parse sends
    // the reader to a file that is fine.
    var reading = _circuit.track;
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
      // Kept rather than decoded twice: `rp-04`'s own demo names a circuit by
      // this same digest, and `TrackDocument` has no `toJson()` of its own to
      // take it from instead — see `test/demo_test.dart`'s identical comment.
      final trackJson = jsonDecode(text) as Map<String, Object?>;
      final document = TrackDocument.fromJson(trackJson);
      reading = _circuit.level;
      final loaded = await const LevelLoader().load(
        _circuit.level,
        device: device,
        physics: usePhysics(),
        // This circuit places no entities — the scenery is brushes — so the
        // registry is empty rather than absent: the loader validates against
        // it, and an empty one is the statement that nothing is expected.
        registry: EntityRegistry(const <EntityKind>[]),
        // No sidecars beside a circuit, and the measurement behind that is on
        // `LevelLoader.load`: a visibility table baked for this track sees
        // everything from everywhere, so asking for one is two 404s in the
        // console of every web build and nothing gained if it were there.
        sidecars: false,
      );

      // The one assembly this game has. What is left here is what needs a
      // device: the road mesh, the cars and the scene they go in.
      final staged = stage(
        document,
        loaded.collision,
        gridOrder: _nextGridOrder,
      );
      final track = staged.track;
      final scene = loaded.scene;
      // Dirt and sparks fall by the race's world, as the cars do.
      _particles.world = loaded.collision.properties;
      addTrackTo(scene, track, device: device);
      // Sheds and signs. The faces are widgets, drawn here rather than shipped
      // as images — one round trip each, before the first frame, and none
      // after. A device that refuses one gives a circuit with fewer signs.
      addRoadsideTo(
        scene,
        track,
        device: device,
        // The ground, so a shed stands on the field rather than over it: the
        // road is on an embankment and the centre line is metres above the
        // grass beside it.
        ground: loaded.collision,
        buildings: await loadBuildings(device),
        signs: await drawSignFaces(device),
      );
      scene.add(_stage);

      // `ls-x-02`: the same [RaceHud] drawn on a `WidgetSurface` in front of
      // the stereo camera instead of as a flat overlay — a child of [_rig]'s
      // own stage, so it rides along exactly the way `edu_annotation`'s own
      // `attachTo` already keeps a note in place on a moving anchor
      // (`packages/flutter3d_bridge/test/widget_surface_visuals_test.dart`'s
      // own "moves with its anchor node"). Positioned in local space — in
      // front of, and a little below, the eye — since that offset is what
      // "in front" means once this is a child rather than free-standing.
      if (_rig case final stereo.StereoRig rig) {
        final panel = WidgetSurface(
          device: device,
          width: 0.9,
          height: 0.32,
          name: 'race-hud',
          child: Transform.flip(
            flipX: true,
            flipY: true,
            child: StereoHudPanel<RaceReadout>(
              reading: _hudReading,
              builder: (context, readout) =>
                  RaceHud(readout: readout, issue: _issue),
            ),
          ),
        )..setPosition(Vector3(0.0, -0.28, -1.1));
        rig.stage.add(panel.node);
        _hudPanel = panel;
      }

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
          // Every car asks for copies, because [Looks.paint] writes a colour
          // into them and shared materials would paint the whole field
          // whatever colour the last car happened to wear.
          final instance = asset.instantiate(
            scene,
            name: i == 0 ? 'player' : 'rival-$i',
            shareMaterials: false,
          );
          Looks.paint(instance.meshes, Looks.carPaint(i));
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
            final center = (asset.localBounds.min + asset.localBounds.max)
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
            )..setPosition(center.x, center.y, center.z);
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

      final ghosts = _keeperFor(_circuit);
      _ghosts = ghosts;
      // Read in the background: the ghost appears once the lap is on hand.
      unawaited(ghosts.load());
      // The water and the fires, once the scene and the cars are there.
      final renderer = _renderer;
      if (renderer != null) {
        _elements = await TrackElements.open(
          device: device,
          scene: scene,
          renderer: renderer,
          track: track,
          cars: staged.cars,
          sky: document.sky,
          load: rootBundle.load,
          light: _handheld,
        );
      }
      _ghostCar = carGhost(device, scene, model: asset);

      {
        for (final car in _cars) {
          _voices.add(CarVoice(scene: _audio, vehicle: car));
        }
      }

      // The one light in the level was written from this same preset by the
      // generator, so the sun the shadows fall from and the sun the sky glows
      // around are the same sun by construction rather than by agreement.
      // The sky document's number is in the engine's old unit; lux here.
      scene.ambientIntensity =
          document.sky.ambientIntensity * Photometric.legacyUnit;

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
      _sunlight(scene);
      if (EnvironmentMap.isSupportedOn(device)) {
        final environment = EnvironmentMap.fromSky(device, _skySettings());
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
        // Stepped by the plugin from the next step on.
        _racing.simulation = staged.sim;
        _chase = staged.chase;
        _ai = staged.ai;
      });
      // After the render fields are in place, not before: a status of
      // `Racing` is a promise that there is something to draw.
      _raceCubit.ready();
      _beginDemo(_circuit.track, contentDigestHex(trackJson), staged.sim);
    } catch (error, stack) {
      debugPrint('circuit: $error\n$stack');
      // With the document's name: every failure here is a content mistake in
      // one of two files written by one script, and the screen this reaches
      // used to print the thrown object alone. "FormatException: Unexpected
      // character" over black names neither the circuit nor the half of it.
      // [reading] is the half, because naming the other one is worse than
      // naming none: it sends the reader to a file that parses.
      if (mounted) _raceCubit.failed(error, asset: reading);
    }
  }

  /// Swaps the player's box for the model, if it loads.
  ///
  /// If it does not, the game is still playable as a box — a car that will not
  /// start because an asset moved is worse than a car that is a rectangle.
  /// The player has finished the race. On to the next circuit, or that was the
  /// season.
  void _finishedHere() {
    // Written down the instant the circuit is won — see [_endDemo] for why
    // this is the only moment that calls it.
    _endDemo();
    // Deciding what comes next and saying so are both `_raceCubit.finish()`'s
    // job now — see `RaceProgress.finish` for the season-complete clause this
    // used to hold directly.
    //
    // The two numbers go in here because here is the last moment they exist:
    // `_moveOn` rebuilds the race, and with it every lap and every lap time
    // this circuit had. The race's own lap count rather than the player's
    // counter, which stops at the flag.
    final race = _race;
    // Read before `_leaveCircuit` clears `_race`, from the standing this
    // circuit actually ended on — the player has already crossed the line
    // here, so every racer's `positionOf` is a finish rather than a place in
    // a race still moving.
    _nextGridOrder = race == null ? null : gridOrderFrom(race);
    final next = _raceCubit.finish(
      laps: race?.laps ?? 0,
      bestLap: race?.progress[0].bestLap,
    );
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

    _leaveCircuit();
    // Leaves the circuit that was just won and starts reading `next` — which
    // is also what clears [_notice], by moving the status out of `RaceOver`.
    _raceCubit.moveOn(next);
    await _loadCircuit(device);
  }

  /// Throws the season away and races it again from the first circuit.
  ///
  /// **The way back into a game that had none.** The other two games each
  /// offer R and a pad's Start once a run is over; this one's key handler was
  /// two lines with no restart in it, so a completed season was a caption over
  /// a race that keeps running for ever, and a circuit that would not read was
  /// a screen with nothing on it to press. Both ends reach here.
  ///
  /// No pause, unlike [_moveOn]: nobody asked for this by winning, they asked
  /// for it by pressing something, and a game that waits two seconds after a
  /// keypress reads as one that missed it.
  Future<void> _startOver() async {
    final device = _device;
    if (device == null) return;
    _leaveCircuit();
    // A season raced again starts level, the same as the first one did — see
    // `RaceProgress.startOver`'s own reasoning for why the season itself
    // resets rather than only the circuit.
    _nextGridOrder = null;
    _raceCubit.startOver();
    await _loadCircuit(device);
  }

  /// Puts down everything that belonged to the circuit being left.
  ///
  /// The voices are stopped rather than dropped: a car that is no longer in
  /// the world still has an engine running in the mixer.
  void _leaveCircuit() {
    for (final voice in _voices) {
      voice.stop();
    }
    _voices.clear();
    _elements?.dispose();
    _elements = null;
    _cars.clear();
    _carNodes.clear();
    _carLift.clear();
    _carDraw.clear();
    _ghostCar = null;

    // `ls-x-02`: the HUD panel belongs to the circuit being left, same as
    // every car above — [_loadCircuit] builds a fresh one for whichever
    // circuit comes next, and a stale one kept alive here would be a second
    // `WidgetSurfacePipeline` nobody reads leaking beside it.
    _hudPanel?.dispose();
    _hudPanel = null;

    setState(() {
      // An empty scene rather than none: the surface has to keep drawing
      // through the load or Flutter GPU never learns its own pixel format —
      // see [_scene].
      _scene = Scene()..add(_stage);
      _race = null;
      _simulation = null;
      _racing.simulation = null;
      _track = null;
      _chase = null;
      _ai = null;
    });
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
      // `ap-12`: `kCarModel` names its `assets_src/` source; `loadModelAsset`
      // (`ap-11`) resolves the generated `.f3d`, falling back to the source
      // directly in debug if the hook has not run yet.
      final document = await loadModelAsset(kCarModel);
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

    _loop.isPaused = shouldPause(
      ready: _simulation != null,
      // The title card counts as a menu, and for the same reason `shouldPause`
      // gives that clause: it is a screen over the game and the clearest
      // statement of attention there is. Without it the lights go out and the
      // rivals leave the grid behind a card the player has not put down — see
      // [TitleCard], where that is the first of the three reasons this game
      // waits rather than running underneath.
      menuOpen: _settings.value.isOpen || !_started,
      // This game never captures the pointer — it is driven from the keyboard —
      // so the pointer is not the gate here and saying otherwise would freeze
      // it on every desktop build.
      pointerIsTheGate: false,
      pointerHeld: false,
      padConnected: _pad.isConnected,
      photoMode: _photo.isActive,
    );
    // The steps, then the frame's phases: see [_loop].
    _loop.frame(dt);
    _pace.note(
      dropped: _loop.lostSteps,
      dt: dt,
      stepSeconds: _loop.stepSeconds,
    );
    // Not while a photo is drawn: a rebuild draws a frame on the renderer the
    // tiles are drawn on — see `capturePhoto`.
    if (!_photo.isBusy) setState(() {});
  }

  /// The screen's own clocks: the celebration, the refusal, the respawn
  /// notice. Wall time, as a notice is read.
  void _clocks(LoopContext frame) {
    final dt = frame.realDt;
    if (_celebrateFor > 0.0) {
      _celebrateFor = (_celebrateFor - dt).clamp(0.0, 4.0);
    }
    if (_refusedFor > 0.0) _refusedFor = (_refusedFor - dt).clamp(0.0, 2.0);
    if (_respawnFor > 0.0) _respawnFor = (_respawnFor - dt).clamp(0.0, 2.0);
  }

  /// The water and the wrecks for this frame.
  ///
  /// **What the loop accepted, not what the clock said** — the frame's `dt`.
  /// A frame longer than the loop's own limit is a window that was dragged or
  /// a laptop that was shut; the simulation refuses it, and anything drawn
  /// beside the simulation has to refuse the same amount or it ends up
  /// showing a world that has not happened yet. After the camera has been
  /// placed, so the water's ripples fade with distance from where the eye is
  /// this frame.
  void _elementsFrame(LoopContext frame) {
    final chase = _chase;
    final race = _race;
    if (chase == null || race == null) return;
    _elements?.frame(frame.dt, eye: chase.eye, progress: race.progress);
  }

  /// Opens photo mode where the chase camera is, or closes it.
  void _togglePhoto() {
    if (_photo.isActive) {
      setState(_photo.leave);
      return;
    }
    final chase = _chase;
    final simulation = _simulation;
    if (chase == null || simulation == null || _cars.isEmpty) return;
    // The keys the car was holding are let go, as the settings let them go:
    // otherwise it comes back out of the picture still accelerating.
    _input.clear();
    setState(
      () => _photo.enter(
        world: simulation.collision,
        eye: chase.eye,
        target: chase.target,
        anchor: _cars[0].position,
        lens: _lens.copyWith(fovY: chase.fovY),
      ),
    );
  }

  /// Draws the photo at [scale] times the window and saves it.
  Future<void> _takePhoto(int scale) async {
    final renderer = _renderer;
    if (renderer == null || _photo.isBusy) return;
    final size =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    setState(() => _photo.isBusy = true);
    // The frame saying so is drawn first; after it nothing redraws until the
    // picture is done.
    await SchedulerBinding.instance.endOfFrame;
    final taken = await savePhoto(
      renderer: renderer,
      scene: _scene,
      camera: _camera,
      width: (size.width * scale).round(),
      height: (size.height * scale).round(),
      settings: _raceSettings(),
      filter: _photo.filter,
      clearColorSrgb: _view.clearColorSrgb,
      shelf: defaultPhotoShelf('racing'),
      name: 'racing-${DateTime.now().millisecondsSinceEpoch}.png',
    );
    if (!mounted) return;
    setState(() {
      _photo
        ..isBusy = false
        ..said = taken.saved.message;
    });
  }

  /// What the screen draws with: [_raceSettings], and in photo mode the
  /// chosen filter over the race's own look.
  RenderSettings _shownSettings() {
    final race = _raceSettings();
    return _photo.isActive ? race.copyWith(look: _photo.look(race.look)) : race;
  }

  /// The step's first half, in the `input` phase: who asks for what, before
  /// [RacingPlugin] steps the race in `physics`.
  void _beforeStep(LoopContext step) {
    final simulation = _simulation;
    final race = _race;
    if (simulation == null || race == null) return;
    _readDriver(simulation);
    _readPitStop();
    _driveTheRest(simulation, race);
  }

  /// The step's second half, in the `publish` phase: what the race the
  /// plugin just stepped did, read once.
  void _afterStep(LoopContext step) {
    final simulation = _simulation;
    final race = _race;
    if (simulation == null || race == null) return;
    final stepSeconds = step.dt;
    _demo?.observe(simulation.save);
    // Whether a car was struck hard enough to leave a wreck: read after the
    // step, which is the only moment the blow is there to read.
    _elements?.stepped(stepSeconds);

    // Where the step left each car, kept beside where the step before left it,
    // so the frames drawn between the two have something to blend. Here rather
    // than in `_place`: this runs once per simulated step, and `_place` runs
    // once per drawn frame — pushing there would overwrite the previous value
    // with the current one and blend a step against itself.
    for (var i = 0; i < _cars.length; i++) {
      _carDraw[i].push(_cars[i].position);
    }

    // What this step looks like, decided by something a test can call and
    // performed here. Per car: a rival locking up in front is as worth seeing
    // as the player doing it.
    final reaction = _reactions.listen(race, _cars)..showIn(_particles);
    // Here rather than in `_listen`, which reads flags once a frame: a bump is
    // an event and not a state, and it has to sound at the moment its sparks
    // are thrown or it arrives after the car has bounced off.
    for (final heard in reaction.heard) {
      _audio.play(heard.sound, heard.at);
    }
  }

  /// The step's end, after the step channel has handed out what the race
  /// published: the events of the step as a whole, which the `publish` phase
  /// is too early to read — they are delivered once every phase has run.
  void _stepEnded(StepEventSummary summary) {
    final race = _race;
    if (_simulation == null || race == null) return;
    final events = summary.events.whereType<GameEvent>().toList();
    // Recorded always, not only when the lap is going to be a good one:
    // whether it was the best is knowable when it ends, and by then it is too
    // late to have been writing it down. **Against the record, not against the
    // session's best.** A race begins with no laps in it, so
    // the lap somebody drives while getting used to the car was the best one by
    // definition, and it used to take the place of a record that stood from
    // another evening. The keeper compares against the disk now, and says when
    // the disk changed.
    final lapped = events.whereType<LapCompleted>().any(
      (LapCompleted event) => event.isPlayer,
    );
    if (_ghosts.stepped(race.progress[0], _cars[0], lapped)) {
      _celebrateFor = 4.0;
    }
    if (events.whereType<RacerFinished>().any(
      (RacerFinished event) => event.isPlayer,
    )) {
      _finishedHere();
    }
  }

  /// What the pad means to a screen rather than to the car.
  ///
  /// A rebinding waiting for a button gets it first — `PadPresses` holds that
  /// order, and the edge that stops a controller resting against something from
  /// binding itself to whatever the panel was waiting for.
  ///
  /// **There is something for a button to mean now.** This used to drop what
  /// `PadPresses` handed back with a comment saying there was no title card to
  /// take down; there is one, and a player holding a controller should not have
  /// to reach for a keyboard to start the season. Any button begins, which is
  /// also how a browser reveals the pad to the page in the first place: it stays
  /// invisible until one is pressed.
  void _padRebinding() {
    if (!_presses.offer(
      _pad,
      _settings,
      menuButton: PadButton.start,
      // The same clause Escape and the gear run — the keys the car was holding
      // are let go, or it comes back accelerating into a wall.
      opening: _input.clear,
    )) {
      return;
    }
    if (!_started) _begin();
  }

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
    if (!_input.pressed(Drive.tireSet)) return;
    final car = _cars[0];
    if (car.pitStop(TireSet.after(car.tireSet))) {
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
      _ghostCar?.showAt(race.progress[0].lapTime, tape, lift: _carLift[0]);
    } else {
      _ghostCar?.node.isVisible = false;
    }

    final chase = _chase;
    if (chase == null) return;
    chase.follow(_cars[0], dt);
    _stage
      ..setPositionFrom(chase.eye)
      ..lookAt(chase.target);
    // `StereoRig` reads its own field of view from `StereoSurface`'s own
    // `fovY` every frame (`fitToViewport`, called from
    // `build()`) — `chase.fovY` reaches it there instead of through
    // `.projection`, which only [_camera] itself has.
    if (_rig == null) {
      _camera.projection = _lens.copyWith(fovY: chase.fovY);
    }
    // In photo mode the chase camera still follows the stopped car, and the
    // photo camera is put on the node after it.
    if (_photo.isActive) {
      _photo
        ..fly(dt)
        ..applyTo(_camera);
    }

    // The sky, once a frame, from where the camera ended up. The engine's fog
    // is one colour with no idea of direction; giving it the colour of the air
    // *along this view* is what stops distance being the same grey whichever
    // way the car is pointing.
    if (_photo.gaze case final photographed?) {
      _gaze.setFrom(photographed);
    } else {
      _gaze
        ..setFrom(chase.target)
        ..sub(chase.eye);
    }
    _view.clearColorSrgb = _skyColour();

    // `ls-x-02`'s own HUD panel — read and redrawn only when it exists
    // (flat mode never builds one) and only once a race is actually up to
    // read, [_readout]'s own requirement.
    if (_hudPanel case final panel?) {
      _hudReading.value = _readout();
      unawaited(panel.tick());
    }
  }

  /// What the race sounds like this frame.
  ///
  /// Read from the same flags the display reads, once, after the steps: a sound
  /// played from inside a step is a sound played several times on a slow frame.
  void _listen(RaceState race) {
    for (var i = 0; i < _voices.length && i < race.progress.length; i++) {
      _voices[i].update(offRoad: race.progress[i].offRoad);
    }

    // The rest of the race's moments were played off the bus before this
    // frame's phases ([_cues]). A best lap and the lap it was are two events,
    // so the "best instead of lap" choice is made here, once both are heard.
    if (_lapHeard && !_bestHeard) _audio.play(Sounds.lap, _ears.position);
    if (_respawnHeard) _respawnFor = 2.0;
    _lapHeard = _bestHeard = _respawnHeard = false;

    // Along the camera's own forward rather than through a yaw: `aimAt` reads
    // an angle as a first-person camera's, and a chase camera is not one.
    final chase = _chase;
    if (chase != null) {
      _ears.aimAlong(chase.eye, chase.target - chase.eye);
    }
    _elements?.hear(_audio, _loop.lastFrame);
    _audio.update(_ears);
  }

  RaceReadout _readout() {
    final race = _race!;
    final player = race.progress[0];
    return RaceReadout(
      behind: _pace.isBehind,
      paused: _settings.value.isOpen,
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
      tireSet: _cars[0].tireSet.name,
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
      // **Which failure it was decides which screen**, and this used to show
      // one for both: `DidNotStart(error)`, printing the thrown object on
      // black with no filename, no explanation and nothing to press. A device
      // that will not open is the engine's own screen — it carries the
      // shader-bundle sentence, which is the most useful thing anybody has put
      // on it. A circuit that will not read is a content mistake, so the
      // screen names the file and offers the season again from the top.
      return switch (status) {
        RaceFailed(:final String asset, :final error) => LevelLoadFailed(
          asset: asset,
          error: error,
          onStartOver: () => unawaited(_startOver()),
          startOverLabel: 'Start the season again',
        ),
        RaceFailed(:final error) => RendererFailure(error: error),
        _ => _screen(),
      };
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
          // Photo mode before the settings: Escape there means "back to the
          // race", and the panel would take it as "open me". Not over the
          // title card, where there is no race to stop, and not in the
          // headset, which has no window to take a picture the size of.
          if (event is KeyDownEvent &&
              _started &&
              _rig == null &&
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
          final settingsSay = settingsKeys(
            event,
            _settings,
            opening: _input.clear,
          );
          if (settingsSay != null) return settingsSay;
          // Any key takes the title card down, and none of them also drives:
          // the card is the one screen where a hand reaching for the throttle
          // means "start", and letting W through to the car as well would put
          // the player on the grid already accelerating.
          if (!_started && event is KeyDownEvent) {
            _begin();
            return KeyEventResult.handled;
          }
          // R, once the season is over and not before. The other two games
          // put a restart on this key and this one had none at all, so a
          // driver who had won five circuits was left with a caption over a
          // race that keeps running. Gated on [_seasonIsOver] rather than
          // offered always, because a key that throws away four won circuits
          // mid-lap is worse than no key: R is not bound to anything a car
          // does, and a hand looking for the handbrake is one row away.
          if (_seasonIsOver &&
              event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.keyR) {
            unawaited(_startOver());
            return KeyEventResult.handled;
          }
          return _devices.handleKeyEvent(event);
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (_rig case final stereo.StereoRig rig)
              stereo.StereoSurface(
                renderer: renderer,
                scene: scene,
                rig: rig,
                // The same speed-pumped field of view the flat camera reads
                // through `.projection` — `chase`'s own doc comment gives the
                // reason it changes at all, and nothing about drawing it
                // twice needs that reason to be any different. Whether that
                // reads well through a headset is unmeasured, the same
                // "unverified against glass" line `LessonStereoView`'s own
                // doc comment already draws for its lens numbers.
                fovY: _chase?.fovY ?? _lens.fovY,
                onBeforeFrame: () {},
                settings: () => _raceSettings().forStereo(),
              )
            else
              SceneSurface(
                renderer: renderer,
                scene: scene,
                view: _view,
                onBeforeFrame: () {},
                settings: _shownSettings,
                presentFrame: presentFrame,
              ),
            // A platform view takes the pointer events over it, so the click
            // that hands the keyboard back has to be caught above the frame
            // rather than around it. Nothing else here wants the pointer.
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) {
                  _keyboard.requestFocus();
                  // A touch build has no key to press, and a click is the
                  // gesture a browser is waiting for before it will make a
                  // sound — so this layer is the other half of [_begin].
                  _begin();
                },
              ),
            ),
            // Not behind the title card: the lap counter and the speedometer
            // showed through it, counting a race the player has not started.
            // Not in photo mode either: the picture is the circuit, and the
            // bar is all that is over it.
            if (_race != null && _started && !_photo.isActive)
              RaceHud(readout: _readout(), issue: _issue),
            if (_photo.isActive) PhotoBar(mode: _photo),
            // A phone has no keyboard and this game had nothing else to offer
            // it: the wheel and the pedals, above the frame and below the
            // panel. Hidden while the settings are open, or a thumb reaching
            // for a slider holds the throttle down behind it — and hidden
            // behind the title card, where a thumb on the throttle would be
            // holding it down through the lights.
            if (_playing.touch &&
                _race != null &&
                _started &&
                !_settings.value.isOpen)
              TouchDrive(
                state: _input,
                steerLeft: Drive.left,
                steerRight: Drive.right,
                throttle: Drive.throttle,
                brake: Drive.brake,
                handbrake: Drive.handbrake,
                // The HUD tells a driver to stop first and then change; on a
                // phone there was nothing bound to the second half of that
                // sentence. See [TouchDrive.corner].
                corner: const TouchAction(Drive.tireSet, 'pit'),
              ),
            // **This was a caption over a race that never stopped.** The last
            // circuit keeps running after the flag — nothing calls `moveOn`
            // past the fifth — so the whole of the game's ending was one line
            // written across a car still driving. Over the wheel and the
            // pedals, because a finished season has nothing left to steer;
            // below the settings overlay, so the gear still opens.
            if (_seasonIsOver)
              SeasonEnding(
                circuits: _raceCubit.season.circuits,
                laps: _raceCubit.season.laps,
                bestLap: _raceCubit.season.bestLap,
                touch: _playing.touch,
              ),
            // Over the ending in turn, and only once the season is done: R is
            // what a keyboard presses here and a handset has none.
            if (_playing.touch && _seasonIsOver && !_settings.value.isOpen)
              TapToRestart(
                onRestart: () => unawaited(_startOver()),
                label: 'Tap to race the season again',
              ),
            if (!_started)
              TitleCard(
                prompt: _playing.touch
                    ? 'Touch to start the season.'
                    : 'Press any key to start the season, or a button on the '
                          'pad.',
                touch: _playing.touch,
                // The card's own, because the start layer above cannot see a
                // touch that lands on it — see [TitleCard.onBegin]. Without
                // this a handset read "touch to start the season" and had
                // nothing that would.
                onBegin: _begin,
              ),
            // `net-03`: the door into `NetRaceSession` — its own screen,
            // not this one's render loop. Only offered before the season
            // starts, the same visibility `TitleCard` already has, so a
            // race in progress is never one stray tap away from being
            // replaced by a different game entirely.
            if (!_started && !_seasonIsOver)
              Positioned(
                left: 0,
                right: 0,
                bottom: 24.0,
                child: Center(
                  child: TextButton(
                    onPressed: () => unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => NetRaceScreen(relayBase: kRelayBase),
                        ),
                      ),
                    ),
                    child: const Text(
                      'Race with a friend',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            SettingsOverlay(
              settings: _settings,
              sections: SettingsSection.standard(
                // Only the sliders this game's own sounds can be heard
                // through. `busesIn` reads the bank, so a soundtrack arriving
                // one day brings its slider with it.
                buses: busesIn(Sounds.all),
                // Asked, not assumed: a driver with a controller plugged in
                // read "Gamepad (none connected)" over the sliders that set
                // its dead zone while this said `false`.
                padConnected: _pad.isConnected,
                // The map's section, and its reset puts the pad back as
                // well: `driveKeys` alone left a controller unbound.
                defaultActions: driveActionMap,
                // What the game ships that somebody else made, here as well
                // as on the title card: an attribution licence asks for it
                // wherever the work appears.
                credits: CreditsSection(credits: credits.models),
                // A season kept on this device, and sending races: both
                // asked, both off until answered.
                privacy: _cloud.consents,
              ),
              opening: _input.clear,
              // Not over the title card, which carries the same credits and is
              // the one screen a stray gear has nothing to add to.
              canOpen: _started,
            ),
          ],
        ),
      ),
    );
  }
}
