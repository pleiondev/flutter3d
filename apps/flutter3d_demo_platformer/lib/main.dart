/// A third-person platformer, assembled from the engine, the genre and this
/// game's own content.
///
/// The assembly is the dungeon's, minus everything that was a shooter's: no
/// weapons, no arsenal, no monsters, no view model with its own field of view.
/// What is left is the shape every application on this stack has — a device, a
/// renderer, a loop, a level, a camera — and here all of it is one
/// [Flutter3dView]: it opens the device, makes the renderer, runs the loop
/// with the genre in it, and owns focus and the lifecycle. The game hands it
/// each level's scene as the level comes up, and hangs its own work on the
/// loop's phases.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey, rootBundle;
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart'
    show Elements, ElementsQuality, HearingScale, LiquidLook, PhysicsHearing;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_kit/ghost.dart' show Ghost;
import 'package:flutter3d_game_kit/reactions.dart' show ReactionsPlugin;
import 'package:flutter3d_game_kit/soundtrack.dart' show SoundtrackPlugin;
import 'package:flutter3d_game_physics/elements.dart' show ElementSounds;
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_game_ui/flutter3d_game_ui.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativeWorld, usePhysics;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pad_input/pad_input.dart';

import 'src/air.dart';
import 'src/audio_cubit.dart';
import 'src/backend.dart';
import 'src/credits.dart';
import 'src/effects.dart';
import 'src/elements.dart';
import 'src/ghost.dart';
import 'src/hud.dart';
import 'src/lens.dart';
import 'src/photo_mode.dart';
import 'src/reactions.dart';
import 'src/run.dart';
import 'src/run_cubit.dart';
import 'src/run_elements.dart';
import 'src/runner_looks.dart';
import 'src/runner_visuals.dart';
import 'src/screen_cubit.dart';
import 'src/sounds.dart';
import 'src/soundtrack.dart';
import 'src/staging.dart' show headlessPlatformer;
import 'src/title_card.dart';
import 'src/touch_runner.dart';

/// `rp-04`'s own build stamp, the same convention `flutter3d_demo_dungeon`
/// established: whatever the release process passes in, `dev` otherwise.
const String _buildStamp = String.fromEnvironment(
  'FLUTTER3D_BUILD_STAMP',
  defaultValue: 'dev',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape and no system bars on a handset — see `lockLandscapeForTouch`,
  // which two applications had written out and the third had not.
  lockLandscapeForTouch(_playing);
  // Settings before the screen: the bindings a player saved are the ones the
  // keyboard should be reading from the first key press, not from the first
  // rebind.
  var unread = false;
  final config = await SettingsFile(
    appName: 'platformer',
    defaultActions: _GameScreenState._actionMap,
    onIssue: (Issue reported) {
      printIssue(reported);
      unread = true;
    },
  ).read();
  runApp(PlatformerApp(config: config, configUnread: unread));
}

/// How this build is played — fingers or keys, a pointer that can be taken
/// — asked of the platform once, for the whole game.
final Playing _playing = Playing.ofPlatform();

class PlatformerApp extends StatelessWidget {
  const PlatformerApp({
    super.key,
    this.device,
    this.config,
    this.configUnread = false,
  });

  /// What the player changed, read before the first frame; the defaults
  /// when null, which is what a test that mounts the game starts with.
  final GameSettings? config;

  /// Whether the stored settings could not be read, which the game says.
  final bool configUnread;

  /// The device this game draws with, borrowed by its [Flutter3dView].
  ///
  /// **Null in the application, and the only reason it exists is that nothing
  /// could ever mount this game.** `main.dart` opened the backend its build was
  /// compiled for — `flutter_gpu` on the desktop — so a widget test had no way
  /// past the first frame, and every screen, gate and wire in this file was
  /// covered by nothing but an analyser and a pair of eyes. A test hands in a
  /// `CpuDevice`, which is a `GraphicsDevice` with no GPU under it.
  ///
  /// One field, and it changes nothing about how the game runs: an application
  /// that passes nothing gets the device the view opens for its platform.
  final GraphicsDevice? device;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Ascent',
    debugShowCheckedModeBanner: false,
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      Flutter3dGameLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    home: GameScreen(
      device: device,
      config: config,
      configUnread: configUnread,
    ),
  );
}

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.device,
    this.config,
    this.configUnread = false,
  });

  /// See [PlatformerApp.config].
  final GameSettings? config;

  /// See [PlatformerApp.configUnread].
  final bool configUnread;

  /// See [PlatformerApp.device].
  final GraphicsDevice? device;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
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
  static const String _runnerModel = 'assets_src/models/penguin.glb';

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

  /// **A settings document that will not read used to reset every binding in
  /// silence.** `SettingsFile` takes the console by default, which is a place
  /// no player looks, and this game was the last of the three still leaving it
  /// there — its own `SaveFile` next door had been saying so on screen for a
  /// while. A truncated write or a hand edit that lost a brace costs a player
  /// every rebinding and every volume they had set, and losing them without a
  /// word is indistinguishable from never having set them.
  late final SettingsFile _settingsFile = SettingsFile(
    appName: 'platformer',
    defaultActions: _actionMap,
    onIssue: (Issue reported) {
      printIssue(reported);
      // The same line the levels and the save file talk on, and it outlives
      // this frame for the same reason: nothing has started yet, and `_sayFor`
      // only counts down once the ticker runs.
      _said = 'Your settings could not be read. Starting with the defaults.';
      _sayFor = 6.0;
    },
  );

  /// The player's settings as they are now: replaced on every change, by
  /// [_applyConfig].
  late GameSettings _config;

  /// The colour table for the player's colour vision. See
  /// `ColorVisionLook`.
  ColorVisionLook? _vision;

  final InputState _input = InputState();
  late final DesktopInput _devices;
  late final PadInput _pad;

  /// `rp-04`'s last ten seconds, every step of them — the same window and the
  /// same reasoning as `flutter3d_demo_dungeon`'s own `_rewind`.
  final RewindBuffer _rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);

  /// `rp-02`'s door onto this run, over the VM service: through the view's
  /// loop and its snapshots, so whichever level the genre is stepping is the
  /// one rewound, its elements with it. Made once the loop is, in
  /// [_engineReady].
  late final RunTimeline _timeline = RunTimeline(rewind: _rewind, loop: _loop);

  /// `rp-04`'s "send this run", called remotely rather than from a button
  /// this game draws itself — the last few seconds `_rewind` has kept, as
  /// plain JSON. Null (and the extension answers with an error) when there
  /// is nothing to report yet, the same case `bugReportTape` itself returns
  /// null for.
  Map<String, Object?> _remoteBugReport() {
    // The start as the run's own snapshot, which is what a `.f3drun` holds.
    final report = bugReportTape(_rewind, part: PlatformerPlugin.id);
    if (report == null) {
      throw StateError('nothing has been recorded yet');
    }
    final level = _level?.loaded.level;
    // A run as a `.f3drun` reads it — the asset it is played in, and no
    // checkpoints, which a tool that keeps it takes by playing it again —
    // so what an agent drops into `test/tapes/` replays as it is.
    return <String, Object?>{
      'version': 1,
      'level': _demo?.level ?? level?.name ?? 'unknown',
      'levelHash': level?.digestHex ?? '',
      'start': report.start.toJson(),
      'tape': report.tape.toJson(),
      'buildStamp': _buildStamp,
      'checkpoints': DigestTrace().toJson(),
      'platform': defaultTargetPlatform.name,
      'physics': usePhysics().name,
    };
  }

  /// The settings screen, which is a state machine and now says so.
  ///
  /// Built in [initState] rather than inline, because it needs the devices and
  /// the pad to exist before it can apply anything to them.
  late final GameSettingsController _settings;

  /// Everything the game is heard through — see [AudioCubit], which is where
  /// the scene, the listener, the backend and the music flag now live.
  final AudioCubit _audio = AudioCubit();

  /// What the screen is showing, as opposed to what the loop is doing — see
  /// [ScreenCubit] for where the line between the two is drawn.
  final ScreenCubit _screen = ScreenCubit();

  /// The engine the view made: the device, the renderer, the scene being
  /// drawn and the loop. Null until the device is open.
  Flutter3dEngine? _engine;

  /// The frame: the genre's step and this game's work around it, phase by
  /// phase — see [_installLoop] for what runs where. The view's; read only
  /// once [_engine] is there, which everything that steps or records is.
  EngineLoop get _loop => _engine!.loop;

  /// The platformer, as the engine runs it: its step, its events, its
  /// entity kinds. Pointed at the level being played by [_preStep].
  final PlatformerPlugin _platformer = PlatformerPlugin(
    headless: headlessPlatformer(),
  );

  /// The level the current step is stepping, or null when nothing is: no
  /// level, or one whose runner or camera is not up yet. Set at the top of
  /// every step, so the genre, the elements and the reaction after them
  /// agree about one level.
  LevelReady? _stepping;

  /// The real seconds of the frame being run, for the frame phases: they
  /// were handed the unclamped frame time before the loop owned them, and
  /// still are.
  double _frameDt = 0.0;

  final CameraNode _camera = CameraNode(projection: ascentLens.base);

  /// P stops the world and hands the player a camera — see `photo_mode.dart`.
  final PhotoMode _photo = runnerPhotoMode();

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

  /// The view's renderer, once it has made one.
  Renderer? get _renderer => _engine?.renderer;

  /// The scene being drawn. Empty until the level arrives, and **never null**.
  ///
  /// That is the whole point of it: the renderer must get to build its frame
  /// targets before anything else has taken device memory, and waiting for the
  /// level to load meant fifteen textures were uploaded first. On this machine
  /// that combination fails to allocate — every frame, from the first — which
  /// is the same trap the runner's model fell into and is documented on
  /// `_dressRunner`.
  /// Empty until a level is up, so the first frames have something to draw.
  final Scene _empty = Scene();

  /// What the render loop reads, all of it owned by [_run]. Getters rather than
  /// fields assigned together in one `setState`, so there is one answer to
  /// "which level is this" instead of five that have to agree.
  Scene get _scene => _level?.scene ?? _empty;
  LoadedLevel? get _loaded => _level?.loaded;
  FixtureVisuals? get _fixtures => _level?.fixtures;

  /// What the player sees themselves as, and everything that decides it.
  ///
  /// Six fields and three methods lived here and only ever spoke to each other;
  /// see [RunnerVisuals], which is now where they are.
  late final RunnerVisuals _runnerVisuals = RunnerVisuals(
    model: _runnerModel,
    modelFacing: _modelFacing,
  );

  Runner? get _runner => _level?.runner;
  PlatformerSimulation? get _sim => _level?.sim;
  FollowCamera? _followCamera;

  /// Dust, sparks and flame. One pool for the whole game, one draw call.
  final ParticleSystem _particles = ParticleSystem(capacity: 2000);

  /// The level's water, fire and floating wood, drawn. The run owns and
  /// steps them (`Staged.elements`); this draws a copy. Null until the
  /// water's material has been read, and for good where it cannot be: the
  /// run still wades and burns, and the level is drawn as it was before
  /// there was any water to draw.
  LevelElements? _elements;

  /// What the fires, falls and splashes of [_elements] sound like, through
  /// whichever scene the game is heard through.
  final ElementSounds _elementSounds = ElementSounds();

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

  /// Whether the music loop has been started. Once per session.

  final Vector3 _scratch = Vector3.zero();

  /// How long since the first frame, in seconds: the fixtures' own clock.
  double _elapsed = 0.0;

  /// **A save that will not read used to become a new game, silently.** The
  /// package said so to the console and handed back null, and null is also
  /// what a player who has never played gets — so the one person who needed to
  /// know saw the title card and assumed they had imagined saving.
  late final SaveFile _saveFile = SaveFile(
    appName: 'platformer',
    onIssue: (Issue reported) {
      printIssue(reported);
      // Said on screen, through the same line the levels talk on. It outlives
      // this frame because the run has not started yet: `_sayFor` counts down
      // from the first tick, so the message is up while the title card is.
      _said = 'Your saved run could not be read. Starting again.';
      _sayFor = 6.0;
    },
  );

  /// The run: which level is up, how it is going, and where next.
  ///
  /// Built in [_engineReady]; its `open` waits on [_deviceReady], so the
  /// first level may be asked for before the renderer has finished opening.
  /// Nullable because it is assigned only once the device is open: as `late
  /// final`, a device that failed to open turned `dispose` into a
  /// `LateInitializationError` thrown over the top of the real error.
  RunCubit? _runOrNull;

  /// The run, once [_engineReady] has built it. Everything behind the
  /// renderer guard in [build] may use this; anything that can fire earlier
  /// reads [_runOrNull].
  RunCubit get _run => _runOrNull!;

  /// Writes the run at a checkpoint, on the way into a pause and when the
  /// application goes to the background. Built beside [_runOrNull].
  Autosave? _autosave;

  /// What a step sounds like. See `soundtrack.dart` for why this is a class
  /// and not a method: a decision can be tested, an effect inside a widget
  /// cannot.
  final Soundtrack _soundtrack = Soundtrack();

  /// What a step looks like. A class for the same reason [Soundtrack] is one.
  final Reactions _reactions = Reactions();

  /// The sounds an event places by itself, played off the bus once a frame
  /// — see [Soundtrack.placed].
  late final SoundtrackPlugin _placedSounds = SoundtrackPlugin(
    _soundtrack.placed,
    scene: () => _audio.scene,
  );

  /// The bursts an event places by itself, decided off the bus once a frame
  /// and shown by `platformer_demo.reactions` — see [Reactions.placed].
  late final ReactionsPlugin _placedBursts = ReactionsPlugin(_reactions.placed);

  /// What happens to the runner, said to a screen reader: the level's own
  /// lines, a checkpoint and a death.
  final SpokenEvents _spoken = SpokenEvents(<Spoken<BusEvent>>[
    Spoken<LevelSaid>((LevelSaid event) => event.message),
    Spoken<CheckpointReached>((_) => 'Checkpoint.'),
    Spoken<RunnerDied>((_) => 'You died.'),
  ]);

  /// The last thing the level said, and how much longer to say it for.
  ///
  /// Three seconds, and replaced rather than queued: a player who walks into a
  /// gate twice wants the second answer, not both of them in order.
  String? _said;
  double _sayFor = 0.0;

  /// Which level is being played. Written by [_loadLevel], read by the save.
  /// Through [_runOrNull], because [build] asks before the device has opened.
  LevelReady? get _level => _runOrNull?.level;

  /// `rp-01`/`rp-04`: this game's own `.f3drun` files, on disk. The dungeon's
  /// own field, mirrored — see its `_beginDemo`/`_endDemo` for the mechanism
  /// this repeats rather than reinvents.
  DemoFile? _demos;

  /// The run being written down: its start, its own recorder — beside no
  /// rewind buffer here, this game has none of the dungeon's kill camera to
  /// share one with — its checkpoints, and `HR3`'s edits made under it.
  DemoRecording? _demo;

  /// Starts writing the run down, from the state the level is in now.
  ///
  /// Now rather than at load: a level resumed from a save begins mid-run, and
  /// the demo has to begin where the player did. The tape's seed is the dice
  /// the snapshot carries, which is the one number a replay cannot do without.
  void _beginDemo(String asset, LevelReady level) => _record(
    asset: asset,
    levelHash: level.loaded.level.digestHex,
    start: level.sim.save(),
  );

  void _record({
    required String asset,
    required String levelHash,
    required Snapshot start,
  }) {
    _endRecording();
    final demo = DemoRecording(
      physics: usePhysics(),
      level: asset,
      levelHash: levelHash,
      start: start,
      seed: start.data.integer('random'),
      simulation: platformerSimulationVersion,
      // Beside the tape, the runner's place every few steps: the ghost a
      // build on another simulation still races (`ghostOf`).
      bodies: () => switch (_runner) {
        final Runner runner => runnerPoses(runner),
        null => const <BodyPose>[],
      },
    );
    _demo = demo;
    // The loop's input, its journal — the plugins as they stand and every
    // switch after — and each step's event digest, all into the one file.
    demo.attach(_loop);
  }

  /// Stops the demo's recording.
  DemoRecording? _endRecording() {
    final demo = _demo;
    demo?.detach();
    _demo = null;
    return demo;
  }

  /// `HR3`: writes an edit the timeline swapped in before [step] into the
  /// demo, so the `.f3drun` replays it rather than parting from the run
  /// there.
  ///
  /// An edit that took effect before this demo began — within a keyframe of
  /// the level loading — cannot go into it, and the demo starts again from
  /// now, in the level it was loaded as, with the edit at its first step.
  void _recordSwap(Level next, int step) {
    final demo = _demo;
    final sim = _sim;
    if (demo == null || sim == null) return;
    if (demo.levelSwapped(next, stepsAgo: _rewind.step - step)) return;
    _record(asset: demo.level, levelHash: demo.levelHash, start: sim.save());
    _demo?.levelSwapped(next, stepsAgo: 0);
  }

  /// Writes the run down when it ends, either way.
  ///
  /// Either way, because a death is the run somebody wants to send: "it threw
  /// me off the edge" is a sentence, and the demo is the proof. Written once
  /// at the end rather than as it goes — the same reason the save is.
  void _endDemo() {
    final demo = _endRecording();
    if (demo == null) return;
    final written = demo.demo(
      buildStamp: _buildStamp,
      platform: defaultTargetPlatform.name,
    );
    unawaited(_demos?.write(written));
    // To the server too, if the player said runs may go: the uploader asks
    // their answer at the moment of sending.
    unawaited(_cloud.send(written));
    _lastRun = written;
  }

  /// The run that ended last, which Share files.
  Demo? _lastRun;

  /// The ghost being raced: where its runner was through the level, the
  /// level it was run in, and what draws it.
  Tape? _ghostTrack;
  String? _ghostLevel;
  Ghost? _ghost;

  /// Files [_lastRun] with its level, and answers its code or why not.
  Future<String> _share() async {
    final shares = _cloud.shares;
    final run = _lastRun;
    final loaded = _loaded;
    if (shares == null || run == null || loaded == null) {
      return 'There is no run to share.';
    }
    final level = loaded.level.toJson();
    final ShareBundle bundle;
    try {
      bundle = ShareBundle(game: 'platformer', level: level, run: run);
    } on ShareFormatException catch (error) {
      return error.message;
    }
    return switch (await shares.share(bundle)) {
      ServiceDone<SharedBundle>(:final value) => 'Your code is ${value.code}.',
      ServiceRefused<SharedBundle>(:final reason) => reason,
    };
  }

  /// Opens [code] and, when its run is through this level, races it: the
  /// level from the top, with the ghost beside the runner.
  Future<String> _race(String code) async {
    final shares = _cloud.shares;
    final loaded = _loaded;
    if (shares == null || loaded == null) return 'There is nowhere to look.';
    if (code.isEmpty) return 'Type a code first.';
    final ShareBundle bundle;
    switch (await shares.open(code)) {
      case ServiceRefused<ShareBundle>(:final reason):
        return reason;
      case ServiceDone<ShareBundle>(:final value):
        bundle = value;
    }
    final run = bundle.run;
    if (run == null) return 'That code is a level with no run in it.';
    if (bundle.levelHash != loaded.level.digestHex) {
      return 'That run is through another level, or another version of '
          'this one.';
    }
    final (:ghost, :note) = ghostOf(Level.fromJson(bundle.level), run);
    if (!mounted) return '';
    final says = note.say(
      Localizations.maybeLocaleOf(context)?.languageCode ?? 'en',
    );
    if (ghost == null) return says;
    setState(() {
      _ghostTrack = ghost;
      _ghostLevel = bundle.levelHash;
    });
    _restart();
    return 'Racing ${bundle.title ?? code}: $says.';
  }

  /// Puts the ghost in [level]'s scene when it is the level being raced.
  void _haunt(LevelReady level, GraphicsDevice device) {
    _ghost = null;
    if (_ghostTrack == null || _ghostLevel != level.loaded.level.digestHex) {
      return;
    }
    _ghost = runnerGhost(
      device,
      level.scene,
      halfExtents: level.runner.body.halfExtents,
      model: _runnerVisuals.asset,
      modelFloor: _runnerVisuals.modelFloor,
      facing: _runnerVisuals.facing,
    );
  }

  /// What the player is asked about their data, and what a yes turns on:
  /// the run kept on the save server, finished levels sent to see where
  /// they are hard. Both off until answered.
  late final GameCloud _cloud = GameCloud(
    game: 'platformer',
    storage: _saveFile.storage,
    saves: _saveFile,
    server: const String.fromEnvironment('FLUTTER3D_CLOUD'),
    policy: '2026-10',
  );

  /// `HR3`: the level on screen, as the editor sees it.
  LiveLevel? _live;

  /// Stops the replay [replayAfterHotSwap] starts after every hot reload;
  /// null until the loop is up.
  VoidCallback? _stopReplays;

  /// Lets a level saved in the editor into this run, or tells the door
  /// which level is up now.
  ///
  /// **Registered with the first level rather than in [initState]**, because
  /// a `LiveLevel` compares every edit with the level it holds and there is
  /// none before one loads; a VM service extension cannot be registered
  /// twice, so later levels move the one door along. Everything the edit
  /// takes is the run's: it builds the edited level ahead, swaps it in inside
  /// [_timeline]'s replay when the simulation has to be lived again, and only
  /// then tells this widget, through [PlatformerRun.onLevelEdited]. The step
  /// the edit took effect at goes into the demo on the way ([_recordSwap]).
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
        present: (Level next, LevelDiff diff) => run.announceEdit(),
        swapped: _recordSwap,
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // Settings before devices: the bindings a player saved are the ones the
    // keyboard should be reading from the first key press, not from the first
    // rebind.
    _config = widget.config ?? const GameSettings();
    if (widget.configUnread) {
      // The same line the levels and the save file talk on, and it outlives
      // this frame for the same reason: nothing has started yet, and
      // `_sayFor` only counts down once the ticker runs.
      _said = 'Your settings could not be read. Starting with the defaults.';
      _sayFor = 6.0;
    }
    // **One map, and the settings controller holds it**: the keyboard, the
    // pad and the rebinding screen read the same object, and every change is
    // saved from it. A fresh table on a first launch, edited by the screen
    // and never saved, is the bug this replaced.
    final controls = _config.actionsOr(_actionMap);
    _devices = DesktopInput(state: _input, actions: controls);
    // A saved config written before the gamepad existed has no `pad:` in it, and
    // a player should not have to delete their settings to use a controller. The
    // rebindings they did make are left alone.
    if (!PadInput.knowsPad(controls)) _padBindings(controls.buttons);
    // One map for both devices, because a player's bindings are one file.
    _pad = PadInput(state: _input, actions: controls)..applySettings(_config);
    _settings = GameSettingsController(
      settings: _config,
      actions: controls,
      file: _settingsFile,
      apply: _applyConfig,
    );
    _applyConfig(_config);
    _demos = DemoFile(appName: 'platformer', onIssue: printIssue);
    // `P12`: the frame this game draws, pass by pass and draw by draw, for
    // whichever renderer is open when somebody asks.
    registerRenderExtensions(() => _renderer);
  }

  /// [_bindings] as an action map over [PlatformerActions.set], with the
  /// mouse's motion bound to looking.
  static ActionMap _actionMap() => ActionMap(
    actions: PlatformerActions.set,
    buttons: _bindings(),
    axes: const <ActionBinding>[
      DualAxisBinding(DualAxisAction.look, InputSource.pointerMotion),
    ],
  );

  /// The engine's table plus this game's own two keys.
  ///
  /// The dash was already the pointer's; drop-through is control, which is
  /// where a player looks for crouch and is what it becomes when crouching
  /// exists.
  static Bindings _bindings() {
    final bindings =
        DesktopInput.addDefaultsTo(ActionMap(actions: ActionSet.common)).buttons
          ..bind(
            InputSource.key(LogicalKeyboardKey.controlLeft.keyId),
            PlatformerActions.dropThrough,
          )
          ..bind(
            InputSource.key(LogicalKeyboardKey.keyC.keyId),
            PlatformerActions.dropThrough,
          );
    if (!_playing.capturesPointer) {
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
    PadInput.addDefaultsTo(
      ActionMap(actions: PlatformerActions.set, buttons: bindings),
    );
    return bindings
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

  /// Mouse motion picked up from a drag, where there is no pointer to lock.
  final DragLook _dragLook = DragLook();

  /// Everything that waits for the device, once the view has opened it and
  /// made the renderer and the loop.
  ///
  /// A device that will not open never gets here: the view shows [_failed]
  /// instead, and nothing waits on [_deviceReady], since the run that would
  /// is built below.
  void _engineReady(Flutter3dEngine engine) {
    final device = engine.device;
    if (!_deviceReady.isCompleted) _deviceReady.complete(device);
    _installLoop(engine.loop);
    _engine = engine;
    if (_stopReplays == null) {
      // `rp-02`: harmless where the VM service is off — `registerExtension`
      // just adds an entry nothing ever asks for. Once the loop is up, since
      // the timeline rewinds through it.
      registerTimelineExtensions(_timeline, bugReport: _remoteBugReport);
      // `HR4`: after every hot reload, the last three seconds lived again
      // under the new code, and the console says whether they came out the
      // same.
      _stopReplays = replayAfterHotSwap(_timeline);
    }
    _vision = ColorVisionLook(device);
    // One pool, one draw call, added once. Everything this game throws into
    // the air goes through it.
    engine.renderer.renderSteps.addContributor(ParticleContributor(_particles));
    // Redrawn once this call is over rather than inside it: a borrowed device
    // has the view call this while it is still being built, and an ancestor
    // marked dirty then is an error.
    scheduleMicrotask(() {
      if (mounted) setState(() {});
    });
    // Not under a device handed in from outside: that is a test drawing the
    // run alone, and its frames are the run's, not the effects'.
    if (widget.device == null) {
      unawaited(_openElements(device, engine.renderer));
    }

    // A cubit and nothing more: `RunSession` decides nothing about state
    // management, and this game happens to use BLoC — matching the dungeon,
    // whose `RunCubit` this one mirrors. A level that will not load is read
    // straight off `_run.state` in [build] rather than copied into fields
    // here.
    _runOrNull = RunCubit(
      PlatformerRun(
        firstLevel: _firstLevel,
        saves: _saveFile,
        input: _input,
        openDevice: () => _deviceReady.future,
        // The guards are drawn from what the step published, not from the
        // actors: the view's side of the boundary.
        published: () => _loop.published,
        onLevelBuilt: (String asset, LevelReady level, GraphicsDevice device) {
          setState(() => _levelArrived(level, device));
          _beginDemo(asset, level);
          _takeEdits(level);
        },
        onLevelEdited: (String asset, LevelReady level, GraphicsDevice device) {
          setState(() => _levelArrived(level, device));
          _takeEdits(level);
        },
      ),
    );
    _autosave = Autosave(_run.run)..watchLifecycle();

    // A run in progress beats a fresh one, and the file says which level it was
    // in — see `SaveFile`, which refuses to hand back a snapshot without one.
    // `begin` also falls back when the saved level is gone, which this game
    // used to handle by showing an error screen with a button on it.
    unawaited(_beginRun());
  }

  /// What shows when no device would open.
  Widget _failed(Object error) => DidNotStart(
    // The sentence is this game's; the screen is `flutter3d_app`'s, and it
    // was the same four widgets in five applications.
    'The renderer did not start.\n\n$error',
    explaining:
        'The shader bundle is built by '
        'packages/flutter3d_impeller/tool/build_shaders.sh and is not '
        'in the repository.',
  );

  /// Reads the water's material and builds [_elements], then dresses the
  /// level already up, if one is.
  ///
  /// **A level that arrives without them is still a level**: the material
  /// is read beside the first load rather than ahead of it, and a bundle
  /// that will not read leaves every level as it was before there was any
  /// water to draw.
  Future<void> _openElements(GraphicsDevice device, Renderer renderer) async {
    try {
      // A phone draws less of the water and the fire. It steps the same
      // water: that is the run's, and a phone's run is a desktop's run.
      final phone =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      // The run steps the elements of each level in a world of its own;
      // what is drawn is a copy of it, in this world, never stepped.
      final drawn = NativeWorld();
      final bundle = await rootBundle.load(LiquidLook.asset);
      final world = await Elements.adopt(
        drawn,
        device: device,
        renderer: renderer,
        // A scene of its own until a level is up: each level's in turn.
        scene: Scene(),
        load: rootBundle.load,
        quality: ElementsQuality.of(phone: phone),
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
      final elements = LevelElements(
        elements: world,
        device: device,
        liquidBundle: bundle,
      );
      if (!mounted) {
        elements.dispose();
        return;
      }
      _elements = elements;
      final level = _level;
      if (level != null) elements.stage(level);
    } catch (error) {
      printIssue(Issue('effects: the water and fire are not drawn: $error'));
    }
  }

  /// The run this device and the save server agree on, begun: the cloud is
  /// asked first — only if the player turned cloud saves on — so a run
  /// carried on from another device is the one that loads.
  Future<void> _beginRun() async {
    final synced = await syncBeforeBegin(context, _cloud.sync);
    if (synced != null) {
      _said = synced;
      _sayFor = 4.0;
    }
    if (!mounted) return;
    final resumed = await _run.begin();
    if (mounted) _screen.resumedFromDisk(resumed: resumed);
  }

  /// Starts SoLoud and swaps it in behind the mixer.
  ///
  /// Failing is allowed and is not fatal: a machine with no audio device, or a
  /// CI runner, keeps the silent backend and plays the game.
  /// Puts the config onto everything that is playing.
  ///
  /// **One function called from one place**, which it was not: the volumes went
  /// on in one method, the pad's dead zone in another and the accessibility
  /// numbers in a third, and each caller picked the subset it thought it
  /// needed. Moving a volume never re-applied the dead zone; nothing depended
  /// on that, and nothing said so either.
  void _applyConfig(GameSettings config) {
    _config = config;
    _audio.applyVolumes(config);
    _pad.applySettings(config);
    _applyAccessibility();
  }

  /// Everything that has to happen before a settings panel is on screen.
  ///
  /// Letting the mouse go, because a panel you cannot point at has no way out of
  /// it — and **letting go of the keys**, which used to happen only as a side
  /// effect of releasing the pointer. On the web and on a phone there is no
  /// pointer to release, so a key held as the panel opened stayed held, and
  /// closing the panel sent the runner walking off on their own.
  void _openSettings() {
    unawaited(_devices.releaseMouse());
    _input.clear();
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
        _config.chosenValueOf(GameSettingKeys.cameraMotion) ??
        _system.cameraMotion;
    _input.setToggled(
      GameAction.sprint,
      toggled: _config.valueOf(GameSettingKeys.toggleSprint),
    );
  }

  /// Records a number that is not a volume, and acts on it at once.
  ///
  /// Applied before it is written, because the point of a dead-zone slider is
  /// that the player moves it and feels the stick change — a setting that took
  /// effect on the next launch could not be chosen at all. That order is
  /// `GameSettingsController`'s promise now rather than this method's.
  /// Loads [asset], and shows why if it cannot.
  ///
  /// **A level that will not read used to be a black screen for ever.** There
  /// was no `catch` here at all and `ScreenState.error` covers only the device
  /// and the renderer, so a malformed document, a missing texture or a save
  /// naming a
  /// level that no longer exists left the game drawing nothing, saying nothing,
  /// and offering nothing to do about it. Every one of those is a *content*
  /// mistake — the failure a person editing a level makes, which is to say the
  /// most likely failure this game has.
  /// Everything the widget has to do when a level arrives.
  ///
  /// Handed to [PlatformerRun] rather than done at the tail of a load, because
  /// the load happens in the run now and every one of these is an effect on
  /// something the run does not own.
  void _levelArrived(LevelReady level, GraphicsDevice device) {
    final runner = level.runner;
    // The level's scene is the one drawn from the next frame, and the eye
    // moves into it.
    _engine?.scene = level.scene;
    _haunt(level, device);
    // A load takes far longer than a frame and drops simulated time every time.
    // Counting that against the machine would light the slow-machine warning on
    // every level of every run, which is the same as not having one.
    _pace.reset(_loop.lostSteps);

    // A box now, the model when it arrives. Doing it any other way is what
    // turned out to matter: awaiting the model here puts it in the scene before
    // the renderer has ever built its frame targets, and on this machine that
    // combination fails to allocate them — every frame, from the first.
    _runnerVisuals.box(device, level.scene, runner);
    _followCamera = FollowCamera(world: level.loaded.collision);
    // A camera is built per level, so the setting has to be put back on it.
    _applyAccessibility();
    // **`mounted` is not enough, and the gap is a whole level.** Reading and
    // uploading eighteen clips takes long enough that the player can finish the
    // level, die into a reload, or press restart while it is happening — and
    // every one of those builds a new scene and a new runner, leaving the load
    // holding the old pair. The widget is still mounted, so the model went into
    // a scene nobody draws, the runner node was pointed at it, and the animation
    // drove it: the level being played kept the orange box it started with,
    // permanently, and the pose logic ran against a node in the dark.
    //
    // Compared by identity against the scene the game is showing, because that
    // is what `setState` at the end of `_readLevel` swaps.
    unawaited(
      _runnerVisuals.dress(
        device,
        level.scene,
        runner,
        stillWanted: () => mounted && identical(level.scene, _scene),
        onArrived: () => setState(() {}),
      ),
    );
    _drawnAt = InterpolatedVector3(
      initial: runner.body.position,
      stepLimit: runner.body.tuning.stepHeight,
    );
    _drawnYaw.jumpTo(runner.yaw);
    _followCamera?.cut();
    _screen.forgetSave();
    _soundtrack.reset();
    _elementSounds.silence();
    _elements?.stage(level);
    // The other of the two racers: the device may have opened before there was
    // anything to play under.
    _audio.startMusic(levelReady: _sim != null);
  }

  /// Writes the run out when it has reached somewhere new to come back to.
  ///
  /// **This game's own trigger, and it stays here.** The crypt saves on entering
  /// a level because it has no checkpoints; a platformer has them, and what a
  /// checkpoint means is exactly that the respawn point moved.
  void _keepSaved() {
    final sim = _sim;
    if (sim == null) return;
    if (!_screen.shouldSave(sim.respawnPoint)) return;
    unawaited(_autosave?.checkpoint());
  }

  /// What the pad means to a screen rather than to the runner.
  ///
  /// Two things the simulation has no verb for: taking down the title card and
  /// starting over once the run is finished. The edge, and the settings' first
  /// refusal of it, are `PadPresses`.
  void _padScreenButtons() {
    if (!_presses.offer(
      _pad,
      _settings,
      menuButton: PadButton.start,
      opening: _openSettings,
    )) {
      return;
    }

    // Any button begins, which is also how a browser reveals the pad to the
    // page in the first place: it stays invisible until one is pressed.
    if (!_screen.state.started) {
      _begin();
      return;
    }
    if (_runIsOver && _pad.heldButtons.contains(PadButton.start)) _restart();
  }

  /// The pad's presses, told apart from its holds.
  final PadPresses _presses = PadPresses();

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
    if (_screen.state.started) return;
    // **The audio starts here rather than at launch**, and that is the browser's
    // rule rather than a preference: a page may not make a sound until the
    // player has done something, and a build that opened its audio in
    // `initState` spent that permission before the player had given it — so the
    // first sound of the game was the one that got refused. This is the first
    // click, touch or pad button in every build, which is exactly the gesture
    // the browser is waiting for.
    unawaited(_audio.open(_config, stillWanted: () => mounted));
    _screen.begin();
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
  void _restart() => unawaited(_run.restart());

  /// Back to the beginning, from a level that would not load.
  ///
  /// Not [_restart], which reloads the level that has just failed: the saved
  /// level is the usual reason a run cannot be resumed, so the only thing that
  /// helps is throwing the save away and going back to the first one.
  ///
  /// `RunSession.startOver` rather than the two lines this used to be: those
  /// cleared the save and loaded the first level, and left `_carried` alone —
  /// so the lives and the elapsed time of the run being thrown away arrived in
  /// the new one. The shared version calls `startFresh` between the two.
  void _startOver() => unawaited(_run.startOver());

  /// The top of a frame, before the view steps the loop: the pad read, and
  /// whether the loop is paused this frame.
  void _beforeFrame(Flutter3dEngine engine, FrameInfo frame) {
    final dt = frame.seconds;
    _elapsed += dt;
    // Before the loop, so the frame that reads the pad is the frame it moves in.
    _pad.tick(dt);
    _padScreenButtons();

    // Four facts and no devices — see `pause_gate.dart`, which carries the three
    // ways this line has been wrong and a test for each.
    _loop.isPaused = shouldPause(
      ready: _sim != null,
      menuOpen: _settings.value.isOpen,
      pointerIsTheGate: _playing.capturesPointer,
      pointerHeld: _devices.isCaptured,
      padConnected: _pad.isConnected,
      photoMode: _photo.isActive,
    );
    // A pause is where most sessions end — the menu opened to quit, the pad
    // put down — so the run is written on the way in.
    unawaited(_autosave?.paused(now: _loop.isPaused));
    // The view steps the loop next, then everything else the frame does,
    // phase by phase — see [_installLoop].
    _frameDt = dt;
  }

  /// The bottom of a frame, after the loop: the screen around the picture
  /// redrawn with what the frame did.
  void _afterFrame(Flutter3dEngine engine, FrameInfo frame) {
    // Not while a photo is drawn: a rebuild draws a frame on the renderer the
    // tiles are drawn on — see `capturePhoto`. The view itself is held still
    // then too, under a `TickerMode` in [_game].
    if (mounted && !_photo.isBusy) setState(() {});
  }

  /// The engine's loop with this game in it.
  ///
  /// **The order the game always had, now said by phase.** A step was this
  /// widget's `_step` around the simulation's; it is now:
  ///
  /// 1. `input` — `platformer_demo.aim`: which level is stepped, the camera's
  ///    yaw handed to the run, the rewind's keyframe taken;
  /// 2. `physics` — `platformer.step`, the genre's own ([PlatformerPlugin]);
  /// 3. `elements` — `platformer_demo.elements`, the level's water and fires
  ///    ([stepElements]), which until this loop rode inside the genre's step;
  /// 4. `publish` — `platformer_demo.react`: the demo's checkpoint;
  /// 5. the step's end ([_afterStep], `onStepEnd`): the step's events, as the
  ///    bus's step channel handed them out, shown, and the drawn runner
  ///    pushed on.
  ///
  /// The sounds and bursts an event places by itself are not in the step:
  /// [SoundtrackPlugin] and [ReactionsPlugin] hear them on the bus's frame
  /// channel after the frame's steps, and `platformer_demo.reactions` shows
  /// the bursts first thing in `animate`. [SpokenEvents] says the runner's
  /// moments there too.
  ///
  /// And a frame, after its steps, what the frame did before the view owned
  /// the loop, in the same order: the pace, the particles and the runner's
  /// clips (`animate`); the camera, the ghost and the photo camera
  /// (`camera`); the fixtures, the elements' drawing and the lamps
  /// (`render`); the save and the run's own state (`ui`).
  ///
  /// The loop itself is the view's, made with [_plugins], the level format's
  /// [EntityKinds] and [_drainLook]; this hangs the game on it.
  void _installLoop(EngineLoop loop) {
    // The last ten seconds, kept as the loop's own captures.
    _rewind.attach(loop);
    loop.onStepEnd(_afterStep);
    loop
      ..addSystem('platformer_demo.aim', LoopPhase.input, _preStep)
      ..addSystem('platformer_demo.elements', LoopPhase.fields, _stepElements)
      ..addSystem('platformer_demo.react', LoopPhase.publish, _postStep)
      // What the frame channel decided, shown before the particles advance:
      // the frame a burst thrown from the step's own `react` was shown in.
      ..addSystem(
        'platformer_demo.reactions',
        LoopPhase.animate,
        (LoopContext _) => _placedBursts.drain()
          ..showIn(_particles)
          ..feel(_followCamera?.rig),
      )
      ..addSystem('platformer_demo.pace', LoopPhase.animate, _notePace)
      ..addSystem(
        'platformer_demo.particles',
        LoopPhase.animate,
        // The frame the loop accepted — see `EngineLoop.lastFrame`.
        (LoopContext frame) => _particles.advance(frame.dt),
      )
      ..addSystem(
        'platformer_demo.runner',
        LoopPhase.animate,
        (LoopContext _) => _runnerVisuals.animate(_frameDt, _runner),
      )
      ..addSystem('platformer_demo.camera', LoopPhase.camera, _frameCamera)
      ..addSystem('platformer_demo.scene', LoopPhase.render, _frameScene)
      ..addSystem('platformer_demo.run', LoopPhase.ui, _frameRun);
  }

  /// The plugins the view's loop installs: the genre, and the sounds, bursts
  /// and spoken lines an event places by itself.
  late final List<Flutter3dPlugin> _plugins = <Flutter3dPlugin>[
    _platformer,
    _placedSounds,
    _placedBursts,
    _spoken,
  ];

  /// The registries the view's loop is made with: the level format's kinds,
  /// which the genre adds its own to.
  final List<PluginRegistry> _registries = <PluginRegistry>[EntityKinds()];

  void _notePace(LoopContext _) {
    final dt = _frameDt;
    // The loop has always counted the simulated time it could not run. Nobody
    // read it, so a machine that could not keep up ran the game slowly and said
    // nothing about it.
    _pace.note(
      dropped: _loop.lostSteps,
      dt: dt,
      stepSeconds: _loop.stepSeconds,
    );

    if (_sayFor > 0.0) {
      _sayFor -= dt;
      if (_sayFor <= 0.0) _said = null;
    }
  }

  void _frameCamera(LoopContext _) {
    final dt = _frameDt;
    _placeCamera(dt);
    // The ghost on the run's own clock: both started at the top together.
    if ((_ghost, _ghostTrack, _sim) case (
      final Ghost ghost,
      final Tape track,
      final PlatformerSimulation sim,
    )) {
      ghost.showAt(sim.elapsed, track);
    }
    if (_photo.isActive) {
      // The paused loop drains nothing, so the look is taken here, and the
      // photo camera is put on the node after the follow camera was.
      final look = Vector2.zero();
      _drainLook(look);
      _photo
        ..fly(dt, input: _input, look: look)
        ..applyTo(_camera);
    }
  }

  void _frameScene(LoopContext _) {
    final dt = _frameDt;
    _fixtures?.sync(_elapsed);
    final elements = _elements;
    if (elements != null) {
      elements
        ..hideDressed()
        // Drawn as the run's last step left them. The clock that ripples
        // the surface and ages the spray is held still with the photograph,
        // and never more than a thirtieth of a second at once.
        ..update(
          _photo.isActive ? 0.0 : (dt < 1.0 / 30.0 ? dt : 1.0 / 30.0),
          eye: _followCamera?.eye ?? Vector3.zero(),
        );
      // The scene asked each frame: the game swaps its silent one for the
      // speakers' once they open.
      _elementSounds.play(_audio.scene, elements.hearing);
    }
    _burnLamps();
  }

  void _frameRun(LoopContext _) {
    _keepSaved();
    // The run's own state, republished on the step it changes — see
    // `RunSession.observe`. **Missing here, this game's next level and its
    // game-over screen would never arrive**: `advance` only acts once
    // `_status.outcome` says the run is over, and nothing else moves that
    // cached outcome off `RunOutcome.playing`.
    _run.observe();
    unawaited(_run.advance());
  }

  /// Opens photo mode where the follow camera is, or closes it.
  void _togglePhoto() {
    final camera = _followCamera;
    final level = _loaded;
    final runner = _runner;
    if (_photo.isActive) {
      setState(_photo.leave);
      return;
    }
    if (camera == null || level == null || runner == null) return;
    setState(
      () => _photo.enter(
        world: level.collision,
        eye: camera.eye,
        target: camera.target,
        anchor: runner.body.position,
        fieldOfView: ascentLens.base.fovY + camera.extraFovY,
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
      settings: _renderSettings(filtered: false),
      filter: _photo.filter,
      clearColorSrgb: _engine!.view.clearColorSrgb,
      shelf: defaultPhotoShelf('platformer'),
      name: 'platformer-${DateTime.now().millisecondsSinceEpoch}.png',
    );
    if (!mounted) return;
    setState(() {
      _photo
        ..isBusy = false
        ..said = taken.saved.message;
    });
  }

  /// What every frame is drawn with; [filtered] puts photo mode's filter on.
  RenderSettings _renderSettings({bool filtered = true}) => RenderSettings(
    // The level's sky and its fog lying low — see `air.dart`. Nothing before
    // a level is up: the first frames draw an empty scene.
    fog: switch (_loaded?.level) {
      final Level level => levelFog(level),
      null => const FogSettings(),
    },
    sky: switch (_loaded?.level) {
      final Level level => levelSky(level),
      null => const SkySettings(),
    },
    // Three cascades, because this level is a hundred and twenty metres by two
    // hundred and sixty and one map over that is fourteen centimetres of world
    // per texel — which drew the runner's own shadow as a blurred slab beside
    // them, and was reported as the character being drawn twice.
    //
    // 2048 rather than the default 1024, which is a real cost: the atlas is
    // `resolution × cascades` wide, so this is 6144 × 2048. What it buys is the
    // character's own shadow reading as soft rather than as a staircase — at
    // 1024 the near cascade is 1.9 cm of world per texel and the penguin's
    // shadow is a visible flight of steps beside it.
    shadows: const ShadowSettings(cascades: 3, resolution: 2048),
    // Photo mode's filter, and over it the player's colour vision.
    look: _seen(
      filtered && _photo.isActive
          ? _photo.look(const LookSettings())
          : const LookSettings(),
    ),
  );

  /// [look] with the player's colour vision correction, when they asked
  /// for one in the settings.
  LookSettings _seen(LookSettings look) => _vision?.of(_config, look) ?? look;

  /// What the last simulated step published. See [_afterStep].
  List<GameEvent> _lastStep = const <GameEvent>[];

  /// The top of a step: which level it steps, and what the run is handed
  /// before the genre steps it. Nothing here draws.
  void _preStep(LoopContext step) {
    final level = _level;
    final camera = _followCamera;
    final stepping = camera == null ? null : level;
    _stepping = stepping;
    // Nothing steps until the level's camera is up, as before the loop.
    _platformer.simulation = stepping?.sim;
    if (stepping == null || camera == null) return;
    final sim = stepping.sim;

    // The camera owns "forward", and the simulation takes it as a number.
    sim.cameraYaw = camera.yaw;
  }

  /// The level's water and fires, after the genre's step. See
  /// [stepElements].
  void _stepElements(LoopContext step) {
    final level = _stepping;
    if (level == null) return;
    stepElements(level.sim, level.staged.elements, step.dt);
  }

  /// The bottom of a step: what it did, written down.
  void _postStep(LoopContext step) {
    final level = _stepping;
    final camera = _followCamera;
    if (level == null || camera == null) return;

    // `rp-01`'s own checkpoint, taken here rather than replayed later from the
    // finished tape — see the dungeon's identical placement for why the step
    // number has to be the recorder's own.
    _demo?.observe(level.sim.save);
  }

  /// The end of a step, once the bus has handed out what it published: the
  /// step shown, the drawn runner pushed on.
  ///
  /// At the step's end rather than in `publish`, because the step channel
  /// hands a step's events out only once all of its phases have run. Read
  /// once, here, and handed to everything that wants it, so every reader sees
  /// the whole step in the order it happened. Kept as well as passed on: the
  /// pose is built in the draw path, which runs between steps, and what it
  /// used to read were flags that stayed set until the next step cleared
  /// them. This is the same window.
  void _afterStep(StepEventSummary summary) {
    final level = _stepping;
    final camera = _followCamera;
    if (level == null || camera == null) return;
    final sim = level.sim;
    final runner = level.runner;
    final dt = _loop.stepSeconds;

    final events = _lastStep = summary.events.whereType<GameEvent>().toList();
    _react(sim, runner, events);

    if (events.any((GameEvent event) => event is RunnerDied)) {
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

  static Vector3 get _up => Vector3(0.0, 1.0, 0.0);
  final Vector3 _flameAt = Vector3.zero();

  /// Turns a step's events into sound and spectacle. Nothing here decides.
  ///
  /// Both halves are somebody else's: `Soundtrack` says what a step sounds
  /// like and `Reactions` says what it looks like, because a decision inside a
  /// widget needs a device, a renderer and a window to ask about — and this
  /// game shipped mute, and then shipped without a particle for a collected
  /// coin, with nothing red either time.
  void _react(PlatformerSimulation sim, Runner runner, List<GameEvent> events) {
    for (final Heard heard in _soundtrack.heardOnStep(sim, runner, events)) {
      _audio.scene.play(heard.sound, heard.at);
    }

    // What the level said. It has been saying things since the engine had
    // signals, into a list this game never drained.
    for (final LevelSaid said in events.whereType<LevelSaid>()) {
      _said = said.message;
      _sayFor = 3.0;
    }

    // Everything the step showed, decided in `Reactions` and only performed
    // here — the same split as the sound above, and for the same reason: what
    // a coin looks like when it is taken was a private method of a widget
    // nothing can mount, so nothing checked that it looked like anything.
    _reactions.shownOnStep(sim, runner, events)
      ..showIn(_particles)
      ..feel(_followCamera?.rig);
  }

  void _placeCamera(double dt) {
    final camera = _followCamera;
    final node = _runnerVisuals.node;
    if (camera == null || node == null) return;

    // A captured pointer reports through the loop; a drag reports here.
    // A captured pointer reports through the loop; a drag reports here.
    camera.look(_playing.usesDragLook ? _dragLook.drain() : _input.lookDelta);
    _drawnAt.read(_loop.alpha, _scratch);
    // The way the runner is *going*, so the camera drifts round behind them
    // over a long level instead of having to be steered by hand at every
    // corner. Velocity rather than facing: a runner sliding backwards off a
    // ledge is going one way and looking another, and the camera should show
    // where they are about to land.
    camera.follow(_scratch, dt, traveling: _runner?.body.velocity);

    // The pose: squash, stretch, lean, and the flip a double jump turns. Built
    // from what the runner did this step and applied here, because this is the
    // one place that draws.
    final runner = _runner;
    if (runner != null) _pose.advance(runner, dt, _lastStep);
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
            modelFloor: _runnerVisuals.modelFloor,
          );

    node
      ..setPosition(_scratch.x, feet, _scratch.z)
      ..setScale(scale.x, scale.y, scale.z)
      ..setRotation(
        Quaternion.axisAngle(
              Vector3(0.0, 1.0, 0.0),
              _drawnYaw.read(_loop.alpha) + _runnerVisuals.facing + _pose.spin,
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
      ..projection = ascentLens.widened(camera.extraFovY);
    // The ears follow this camera: the view says where it ended up after the
    // frame, through [_listenerMoved].
  }

  /// The ears where the camera is, in the world and facing its way, as the
  /// view hands them over after every frame: relative to the drawn scene's
  /// origin, which is where the mixer's sounds are placed from.
  void _listenerMoved(ListenerPose ears) {
    _audio.ears.placeAt(
      ears.position,
      ears.forward,
      origin: ears.origin,
      up: ears.up,
    );
    _audio.scene.update(_audio.ears);
  }

  @override
  void dispose() {
    _stopReplays?.call();
    // Null if the device never opened: nothing ran, so there is nothing to
    // keep — and the cubit to close was never built either.
    _runOrNull?.save();
    _autosave?.dispose();
    // Closed like the three below, and the cubit unhooks itself from the
    // session first — see `RunCubit.close` for why the order matters.
    unawaited(_runOrNull?.close());
    unawaited(_audio.close());
    unawaited(_screen.close());
    _settings.dispose();
    _keyboard.dispose();
    unawaited(_devices.dispose());
    _elements?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = _runOrNull;
    // Before the device is open there is no run to watch: the view shows its
    // placeholder, and the screen around it waits with it.
    if (run == null) return _game();

    return BlocConsumer<RunCubit, RunStatus<LevelReady>>(
      bloc: run,
      // `rp-01`/`rp-04`: the one moment `_beginDemo` cannot cover, because it
      // fires from `onLevelBuilt` rather than from a republished status —
      // this game's own outcome ending, win or lose. `RunSession.observe`
      // (called every step, see the comment above it) is what republishes
      // `RunPlaying` with a new `outcome` exactly once per transition, so
      // this fires once per level ending, not once per frame it stays ended.
      listener: (BuildContext context, RunStatus<LevelReady> run) {
        switch (run) {
          case RunPlaying<LevelReady>(outcome: RunOutcome.lost):
          case RunPlaying<LevelReady>(outcome: RunOutcome.won):
            _endDemo();
          default:
        }
      },
      builder: (BuildContext context, RunStatus<LevelReady> run) => _game(
        // **This used to be a black screen for ever**: the load caught its
        // own throw and printed it, which is a line in a console nobody
        // playing the game can see. Over the view, which stays, so a level
        // that does load after a start-over is drawn by the same engine.
        failed: run is RunFailed<LevelReady>
            ? LevelLoadFailed(
                asset: run.asset,
                error: run.error,
                onStartOver: _startOver,
              )
            : null,
      ),
    );
  }

  /// The game itself: the view, and the screen around it once the view's
  /// engine is up — the HUD, the touch controls, the title card and the
  /// settings — with [failed] over everything when a level would not load.
  Widget _game({Widget? failed}) {
    final sim = _sim;
    final renderer = _renderer;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        // Wherever the pointer can be captured, which now includes a desktop
        // browser: `_playing.capturesPointer` asks the capture backend and no
        // longer a platform list. The drag-look layer above the platform view
        // is the other half of the same question and stands down when this
        // one answers yes — handling both at once doubled every look delta.
        //
        // **The capture must stay inside this handler**, because a browser
        // refuses `requestPointerLock` without a user gesture behind it.
        onPointerDown: (_) {
          _keyboard.requestFocus();
          _begin();
          if (!_playing.capturesPointer) return;
          _devices.pressPointer(PlatformerActions.dash);
          if (!_devices.isCaptured) unawaited(_devices.captureMouse());
        },
        onPointerUp: (_) {
          if (!_playing.capturesPointer) return;
          _devices.releasePointer(PlatformerActions.dash);
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Held still while a photo is drawn: a frame drawn then would be
            // drawn on the renderer the photo's tiles are — see
            // `capturePhoto`.
            TickerMode(
              enabled: !_photo.isBusy,
              child: Flutter3dView(
                scene: _empty,
                camera: _camera,
                device: widget.device,
                input: _input,
                drainLook: _drainLook,
                plugins: _plugins,
                registries: _registries,
                settings: _renderSettings(),
                focusNode: _keyboard,
                autofocus: true,
                onKeyEvent: _onKey,
                onCreated: _engineReady,
                onBeforeFrame: _beforeFrame,
                onFrame: _afterFrame,
                onListenerMoved: _listenerMoved,
                placeholder: const Center(child: CircularProgressIndicator()),
                failure: _failed,
              ),
            ),
            // **`gfx-71n`.** This build ships to Android and iOS, and the
            // pool it draws through settles at the high-water mark of every
            // attachment shape any frame has needed — which here includes a
            // 6144 x 2048 shadow atlas and bloom's five levels. On a phone
            // that is the difference between a slow frame and the operating
            // system killing the process, so the platform's own warning is
            // wired to giving the pooled ones back.
            if (renderer != null) ...<Widget>[
              MemoryPressureRelease(
                renderer: renderer,
                child: const SizedBox.shrink(),
              ),
              // The web build draws into a platform view, and a platform view
              // takes every pointer event over it — the `Listener` outside this
              // stack never sees the drag that turns the camera. A transparent
              // layer *above* the view does, because it is an ordinary Flutter
              // widget again. Nothing below it is interactive, so opaque hit
              // testing costs nothing.
              if (_playing.usesDragLook)
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) {
                      _keyboard.requestFocus();
                      _begin();
                      _dragLook.begin();
                    },
                    onPointerMove: (PointerMoveEvent event) =>
                        _dragLook.moved(event.delta),
                    onPointerUp: (_) => _dragLook.end(),
                    onPointerCancel: (_) => _dragLook.end(),
                  ),
                ),
              // Not behind the title card: the tallies and its own "Click to
              // play" banner showed through it, saying the same thing twice
              // and counting a run the player has not started.
              if (_photo.isActive) PhotoBar(mode: _photo),
              // Not in photo mode either: the picture is the level, and the
              // tallies over it are not.
              if (sim != null && _screen.state.started && !_photo.isActive)
                Hud(
                  coins: _runner?.purse['coin'] ?? 0,
                  deaths: sim.deaths,
                  lives: sim.lives,
                  elapsed: sim.elapsed,
                  state: sim.state,
                  // Nothing to capture in a browser, so nothing to prompt for.
                  captured: !_playing.capturesPointer || _devices.isCaptured,
                  levelName: _loaded?.level.name ?? '',
                  keys: _runner?.keys ?? const <String>{},
                  message: _said,
                  behind: _pace.isBehind,
                  lost: _pace.lost,
                  // The end of the *game*, not of a level: the last level is
                  // the one with nowhere to go next, which the document says
                  // and this widget must not guess at.
                  finale: sim.nextLevel == null,
                  // So the end of a run asks for something this build can do.
                  touch: _playing.touch,
                ),
              // Above the drag layer on purpose: a widget higher in the stack
              // takes the pointers that land on it, so a thumb on the stick is
              // never also a turn of the camera. Everything the drag layer
              // still sees is screen the controls are not on.
              if (_playing.touch &&
                  _screen.state.started &&
                  !_settings.value.isOpen)
                // **`TouchRunner` rather than `TouchControls` written out
                // here.** The list of buttons was inline in this method, where
                // nothing could pump it — and it was one verb short: sprint is
                // bound to shift and to a shoulder button and to nothing a
                // finger could reach. Its own file says why that one is a
                // switch rather than a fourth circle.
                TouchRunner(
                  state: _input,
                  onSprint: () =>
                      setState(() => _input.toggle(GameAction.sprint)),
                ),
              // The way back in on a device that has neither R nor a pad.
              // Above the stick, because a finished run has nothing left to
              // jump over and the stick is where a thumb already rests; above
              // the HUD, which is an `IgnorePointer` and takes no touch at all;
              // and below the settings overlay, so the gear still opens.
              if (_playing.touch && _screen.state.started && _runIsOver)
                TapToRestart(onRestart: _restart),
              // Share the run just ended, or race somebody's: where a run
              // is over, and only in a build with somewhere to share to.
              if (_cloud.shares != null && _runIsOver && !_photo.isActive)
                Positioned(
                  top: 12,
                  right: 12,
                  child: ShareStrip(
                    onShare: _lastRun == null ? null : _share,
                    onOpen: _race,
                  ),
                ),
              if (!_screen.state.started)
                TitleCard(
                  prompt: _playing.touch
                      ? 'Touch to begin.'
                      : _playing.capturesPointer
                      ? 'Click to take the mouse, or press a button on the '
                            'pad.'
                      : 'Click to begin, or press a button on the pad.',
                  dashOnPointer: _playing.capturesPointer,
                  touch: _playing.touch,
                  resuming: _screen.state.resumed,
                ),
              SettingsOverlay(
                settings: _settings,
                sections: SettingsSection.standard(
                  // Only the sliders this game's own sounds can be heard
                  // through. `busesIn` reads the bank, so a soundtrack
                  // arriving one day brings its slider with it.
                  buses: busesIn(Sounds.all),
                  padConnected: _pad.isConnected,
                  defaultActions: _actionMap,
                  credits: CreditsSection(credits: credits.models),
                  // Cloud saves and sending runs, both off until answered.
                  privacy: _cloud.consents,
                ),
                opening: _openSettings,
                // Not over the title card, which carries the same settings on
                // it and is the one screen a stray gear has nothing to add to.
                canOpen: _screen.state.started,
              ),
            ],
            ?failed,
          ],
        ),
      ),
    );
  }

  /// A key, while the view has focus: photo mode, the settings and the end
  /// of a run first, then the keyboard's bindings.
  KeyEventResult _onKey(KeyEvent event) {
    // Photo mode before the settings: Escape there means "back to the
    // game", and the panel would take it as "open me".
    if (event is KeyDownEvent &&
        _screen.state.started &&
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
    // The settings get the key first — see `settingsKeys` for the order
    // and for the bug this call fixed here: R sat above the rebinding, so
    // a player at the end of a run could not bind R to anything.
    //
    // The panel is offered only once the game has started; the title card
    // carries the same credits and is the one screen a panel over the top
    // of it adds nothing to.
    final settingsSay = settingsKeys(
      event,
      _settings,
      opening: _openSettings,
      canOpen: _screen.state.started,
    );
    if (settingsSay != null) return settingsSay;
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
  }
}
