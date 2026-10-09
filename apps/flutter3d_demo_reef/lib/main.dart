/// Wreck Reef: a dive on the physics core.
///
///     flutter run -d macos
///
/// A boat rides at anchor over a reef flat; off its edge the reef drops to
/// a sand plain where a ship went down. The sea is a shallow liquid with a
/// current through it, its floor lit by the caustics its own surface
/// focuses, and everything under it reddened away by the water between it
/// and the eye. Bring up what lies there with bags of air before the tank
/// runs dry.
///
/// The keys and the pointer write an [InputState] and the dive's step reads
/// only that, so a dive is its tape: F5 writes the dive so far to a
/// `.f3drun`, F9 plays the saved one back from its start and checks it
/// against its own checkpoints.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game/flutter3d_game.dart'
    show
        ActionBinding,
        ActionInput,
        ActionMap,
        AxisComposite,
        Bindings,
        DemoFile,
        DemoRecording,
        DemoReplay,
        InputSource,
        replayDemoOnLoop;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativeWorld, preparePhysics, usePhysics;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        Divergence,
        EngineLoop,
        EventDivergence,
        GameAction,
        InputState,
        ReplayException,
        Snapshot,
        StateDigest;

import 'src/diver.dart';
import 'src/looks.dart';
import 'src/sound.dart';
import 'src/staging.dart';

/// Which build wrote a `.f3drun`: whatever the release passes in, `dev`
/// otherwise — the convention every demo here keeps.
const String _buildStamp = String.fromEnvironment(
  'FLUTTER3D_BUILD_STAMP',
  defaultValue: 'dev',
);

/// What each key asks of the diver, as an action map over
/// [ReefActions.set]. Held keys hold an action; E is pressed once and read by
/// the next step. Rising and sinking are one axis on two keys.
ActionMap reefControls() {
  InputSource key(LogicalKeyboardKey key) => InputSource.key(key.keyId);
  return ActionMap(
    actions: ReefActions.set,
    buttons: Bindings(<InputSource, GameAction>{
      key(LogicalKeyboardKey.keyW): GameAction.moveForward,
      key(LogicalKeyboardKey.keyS): GameAction.moveBack,
      key(LogicalKeyboardKey.keyA): GameAction.moveLeft,
      key(LogicalKeyboardKey.keyD): GameAction.moveRight,
      key(LogicalKeyboardKey.keyR): ReefActions.fill,
      key(LogicalKeyboardKey.keyQ): ReefActions.dump,
      key(LogicalKeyboardKey.keyE): ReefActions.act,
    }),
    axes: <ActionBinding>[
      AxisComposite(
        ReefActions.ascend,
        negative: key(LogicalKeyboardKey.keyC),
        positive: key(LogicalKeyboardKey.space),
      ),
    ],
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await preparePhysics();
  runApp(const ReefApp());
}

/// The application: one screen.
class ReefApp extends StatelessWidget {
  const ReefApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Wreck Reef',
    debugShowCheckedModeBanner: false,
    home: ReefScreen(),
  );
}

/// Opens the device and runs the dive.
class ReefScreen extends StatefulWidget {
  const ReefScreen({super.key});

  @override
  State<ReefScreen> createState() => _ReefScreenState();
}

class _ReefScreenState extends State<ReefScreen>
    with SingleTickerProviderStateMixin {
  /// The sun: high, from the south-west, a late morning.
  static Vector3 get _sunAlong => Vector3(0.3, -0.85, -0.42);
  static Vector3 get _sunLight => Vector3(2.0, 1.95, 1.85);

  final CameraNode _camera = CameraNode(name: 'eye');
  late final RenderView _view = RenderView(
    camera: _camera,
    clearColorSrgb: Vector4(0.55, 0.75, 0.92, 1.0),
  );
  final FrameClock _frames = FrameClock();
  final FocusNode _keyboard = FocusNode();
  Ticker? _ticker;

  ({Renderer renderer, ReefRun run})? _playing;
  Object? _error;

  /// The dive's loop: its fixed steps, phase by phase, then the frame. Made
  /// with the run.
  EngineLoop? _loop;

  /// What the keys and the pointer ask of the dive, which its step alone
  /// reads.
  final InputState _input = InputState();

  /// The keys, as [reefControls] binds them.
  final ActionMap _controls = reefControls();

  /// Rising and sinking from their keys.
  late final ActionInput _axes = ActionInput(state: _input, map: _controls);

  /// Drops every held key and axis — a lost focus never sends the key-ups.
  void _letGo() {
    _input.clear();
    _axes.letGo();
  }

  /// How far the pointer has dragged across since the loop last took it:
  /// the eye's turn round the diver, which the step makes.
  final Vector2 _drag = Vector2.zero();

  /// The dive's own `.f3drun`, on disk, and the dive being written into it
  /// from the moment it began.
  final DemoFile _runs = DemoFile(appName: 'reef');
  DemoRecording? _recording;
  void Function()? _stopCheckpoints;

  /// What the window last said about the run file, beside what the dive
  /// says: a line of its own, since the dive's words are its state.
  String _told = '';

  Speakers? _speakers;
  ReefSound? _sound;
  final AudioListener _listener = AudioListener();

  /// Where the eye looks from: behind the diver by the dive's own
  /// [ReefRun.eyeYaw], up by [_pitch], [_distance] off.
  double _pitch = 0.25, _distance = 4.5;

  /// Whether the eye is under the surface now.
  bool _under = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final device = await openDevice(width: 1280, height: 800);
      final renderer = Renderer.create(device: device);
      final surface =
          await LiquidLook.load(
              device: device,
              renderer: renderer,
              bundle: await rootBundle.load(LiquidLook.asset),
            )
            ..sun(along: _sunAlong, light: _sunLight)
            // Open sea over sand: clear and blue-green.
            ..optics = LiquidOptics.pureWater;
      final floor =
          await SeabedLook.load(
              device: device,
              renderer: renderer,
              bundle: await rootBundle.load(SeabedLook.asset),
            )
            ..sun(along: _sunAlong, light: _sunLight)
            ..optics = LiquidOptics.pureWater;
      final scene = Scene()
        ..ambientIntensity = 0.5 * Photometric.legacyUnit
        ..ambientColor = LinearColor(0.75, 0.85, 1.0)
        ..add(
          LightNode(name: 'sun', intensity: 2.0 * Photometric.legacyUnit)
            ..setLocalForward(_sunAlong),
        )
        ..add(_camera);
      // A phone draws less of the water.
      final phone =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      final elements =
          await Elements.adopt(
              NativeWorld(),
              device: device,
              renderer: renderer,
              scene: scene,
              load: rootBundle.load,
              quality: ElementsQuality.of(phone: phone),
              // Nothing burns on the reef.
              lights: FireLights.none,
              hearing: (world) => PhysicsHearing(
                world,
                fireScale: const HearingScale(
                  quiet: 500.0,
                  loud: 5e5,
                  reference: 2e4,
                ),
                fallScale: const HearingScale(
                  quiet: 50.0,
                  loud: 1e5,
                  reference: 5e3,
                ),
                splashScale: const HearingScale(
                  quiet: 20.0,
                  loud: 2e4,
                  reference: 2e3,
                ),
              ),
            )
            ..sun(along: _sunAlong, light: _sunLight);
      final run = ReefRun(
        device: device,
        scene: scene,
        elements: elements,
        surface: surface,
        floor: floor,
        looks: await ReefLooks.load(device),
        input: _input,
      );
      if (!mounted) return;
      final loop = _loopFor(run)..snapshots.add(_runPartOf(run));
      _loop = loop;
      _record(run, loop);
      setState(() => _playing = (renderer: renderer, run: run));
      // A machine with no audio device plays the same dive, silent.
      final Speakers speakers;
      try {
        speakers = await openSpeakers(bank: ReefSound.bank);
      } on AudioDeviceException {
        return;
      }
      if (!mounted) {
        await speakers.dispose();
        return;
      }
      _speakers = speakers;
      _sound = ReefSound(speakers.scene, run.hearing);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// The dive's loop: [run]'s systems — its controls read off [_input] at
  /// the top of each step among them — and the window's own, what is heard
  /// once a frame. The pointer's drag reaches the step as the input's look,
  /// shared out over the frame's steps.
  ///
  /// Never more than a thirtieth of a second of a stall is stepped, as
  /// before the loop.
  EngineLoop _loopFor(ReefRun run) {
    final loop = EngineLoop(
      input: _input,
      longestFrame: 1.0 / 30.0,
      drainLook: (Vector2 out) {
        out.setFrom(_drag);
        _drag.setZero();
      },
    );
    run.install(loop);
    loop.addSystem(
      'reef.sound',
      LoopPhase.audio,
      (frame) => _sound?.update(
        _listener,
        frame.dt,
        breathing: math.min(run.controls.swim.length, 1.0),
        under: run.diver.depthUnder(run.level) > 0.3,
      ),
    );
    return loop;
  }

  void _onTick(Duration _) {
    final dt = _frames.tick();
    final loop = _loop;
    if (_playing == null || loop == null) return;
    loop.frame(dt);
    if (mounted) setState(() {});
  }

  /// A key down presses its action and a key up lets it go; F5 and F9 are
  /// the window's own, for the run file. A repeat is neither.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_playing == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.f5:
          _saveRun();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.f9:
          _replay();
          return KeyEventResult.handled;
      }
    }
    final source = InputSource.key(event.logicalKey.keyId);
    final action = _controls.buttons[source];
    final routed = _axes.routes(source);
    if (action == null && !routed) return KeyEventResult.ignored;
    switch (event) {
      case KeyDownEvent():
        if (action != null) _input.press(action);
        if (routed) _axes.sourceDown(source);
      case KeyUpEvent():
        if (action != null) _input.release(action);
        if (routed) _axes.sourceUp(source);
      case _:
    }
    return KeyEventResult.handled;
  }

  /// Starts writing the dive down from the state [run] is in now, through
  /// [loop]: its input, its journal and each step's events, a checkpoint
  /// every two seconds and the moving bodies' poses.
  void _record(ReefRun run, EngineLoop loop) {
    _stopRecording();
    final start = run.save();
    final recording = DemoRecording(
      physics: usePhysics(),
      level: 'reef:wreck',
      levelHash: StateDigest.of(start.toJson()).toRadixString(16),
      start: start,
      seed: 0,
      // The world's snapshot is the sea's grid as well as the bodies: taken
      // every two seconds rather than every twenty-five steps.
      checkpointEvery: 120,
      simulation: reefSimulation,
      bodies: run.poses,
    )..attach(loop);
    _stopCheckpoints = loop.onStepEnd((summary) {
      if (!summary.resimulated) recording.observe(run.save);
    }).cancel;
    _recording = recording;
  }

  void _stopRecording() {
    _stopCheckpoints?.call();
    _stopCheckpoints = null;
    _recording?.detach();
    _recording = null;
  }

  /// F5: the dive so far, written to the reef's `.f3drun`.
  Future<void> _saveRun() async {
    final recording = _recording;
    if (recording == null) return;
    final written = await _runs.write(
      recording.demo(
        buildStamp: _buildStamp,
        platform: defaultTargetPlatform.name,
      ),
    );
    if (!mounted) return;
    setState(
      () => _told = written
          ? 'Dive saved: ${recording.steps} steps. F9 plays it back.'
          : 'The dive could not be saved.',
    );
  }

  /// F9: the saved dive played back from its start, as fast as it steps,
  /// checked against its own checkpoints; the dive is left where the run
  /// ended, and a new recording begins from there.
  Future<void> _replay() async {
    final run = _playing?.run;
    final loop = _loop;
    if (run == null || loop == null) return;
    final demo = await _runs.read();
    if (!mounted) return;
    if (demo == null) {
      setState(() => _told = 'There is no saved dive to play back.');
      return;
    }
    _stopRecording();
    _letGo();
    _drag.setZero();
    String told;
    try {
      final result = replayDemoOnLoop(
        demo: demo,
        loop: loop,
        part: _runPart,
        simulation: reefSimulation,
        // A dive from before rising was an axis replays with it.
        actions: ReefActions.set,
      );
      told = switch (result) {
        DemoReplay(divergence: final Divergence d) =>
          'Played back ${result.steps} steps; it parted from the recording '
              'at step ${d.step}.',
        DemoReplay(eventDivergence: final EventDivergence e) =>
          'Played back ${result.steps} steps; its events differed at step '
              '${e.step}.',
        _ => 'Played back ${result.steps} steps, matching the recording.',
      };
    } on ReplayException catch (refused) {
      told = refused.message;
    } on FormatException catch (error) {
      told = 'The dive could not be played back: ${error.message}';
    }
    _letGo();
    loop.resetClock();
    _record(run, loop);
    setState(() => _told = told);
  }

  void _placeCamera() {
    final run = _playing?.run;
    if (run == null) return;
    final target = run.diver.position;
    // Behind the diver, or nearer where the reef or the ship stands in the
    // way: never inside either.
    final yaw = Portable.sinCos(run.eyeYaw);
    final pitch = Portable.sinCos(_pitch);
    final eye = run.clearView(
      target,
      target +
          Vector3(yaw.cos * pitch.cos, pitch.sin, -yaw.sin * pitch.cos) *
              _distance,
    );
    _camera
      ..setPosition(eye.x, eye.y, eye.z)
      ..lookAt(target);
    run.eye.setFrom(eye);
    _under = eye.y < run.level;
    _listener.aimAlong(eye, target - eye);
  }

  @override
  void dispose() {
    _stopRecording();
    _ticker?.dispose();
    _keyboard.dispose();
    _sound?.stop();
    unawaited(_speakers?.dispose());
    _playing?.run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch ((_error, _playing)) {
    (final Object error, _) => DidNotStart(
      error,
      background: const Color(0xFF0A1A24),
      foreground: const Color(0xFFFF8A80),
    ),
    (_, null) => const ColoredBox(
      color: Color(0xFF0A1A24),
      child: Center(child: CircularProgressIndicator()),
    ),
    (_, final playing?) => Scaffold(
      backgroundColor: const Color(0xFF0A1A24),
      body: Focus(
        focusNode: _keyboard,
        autofocus: true,
        onKeyEvent: _onKey,
        // A key held when the window went away never comes up.
        onFocusChange: (bool focused) {
          if (!focused) _letGo();
        },
        child: Listener(
          onPointerMove: (PointerMoveEvent event) {
            // The turn round the diver is the dive's, made in the step; the
            // tilt is the eye's alone.
            _drag.x += event.delta.dx;
            _pitch = (_pitch + event.delta.dy * 0.004).clamp(-1.2, 1.2);
          },
          onPointerSignal: (PointerSignalEvent event) {
            if (event is! PointerScrollEvent) return;
            _distance = (_distance * Portable.exp(event.scrollDelta.dy * 0.001))
                .clamp(2.0, 30.0);
          },
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              SceneSurface(
                renderer: playing.renderer,
                scene: playing.run.scene,
                view: _view,
                settings: () => RenderSettings(
                  exposure: 0.8,
                  // Fitted to the few tens of metres a diver sees, and soft:
                  // under water the sun comes through a rippling surface
                  // and the water scatters it, so a shadow has a wide edge
                  // and is never black.
                  shadows: const ShadowSettings(
                    resolution: 2048,
                    viewDistance: 30.0,
                    cascadeSplit: 0.6,
                    directionalLightRadius: 0.6,
                    strength: 0.8,
                  ),
                  bloom: const BloomSettings(enabled: false),
                  // Under the surface, past the reef's edges is open water:
                  // its own blue-green, lighter towards the light.
                  sky: _under
                      ? SkySettings(
                          enabled: true,
                          zenith: LinearColor(0.10, 0.42, 0.52),
                          horizon: LinearColor(0.04, 0.24, 0.34),
                          nadir: LinearColor(0.01, 0.08, 0.14),
                        )
                      : SkySettings(
                          enabled: true,
                          zenith: LinearColor(0.20, 0.45, 0.85),
                          horizon: LinearColor(0.70, 0.82, 0.92),
                          nadir: LinearColor(0.05, 0.25, 0.32),
                        ),
                  // Under the surface the sun comes down in shafts through
                  // the water, scattered blue-green.
                  lightShafts: LightShaftSettings(
                    enabled: _under,
                    distance: 30.0,
                    strength: 0.02,
                    color: LinearColor(0.45, 0.85, 0.95),
                  ),
                ),
                onBeforeFrame: _placeCamera,
                presentFrame: presentFrame,
              ),
              Positioned(
                left: 16,
                top: 16,
                child: SafeArea(
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      shadows: <Shadow>[Shadow(blurRadius: 4)],
                    ),
                    child: _Panel(run: playing.run, told: _told),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  };
}

/// The gauges, and what the diver can do.
class _Panel extends StatelessWidget {
  const _Panel({required this.run, required this.told});

  final ReefRun run;

  /// What the window said about the run file.
  final String told;

  @override
  Widget build(BuildContext context) {
    final diver = run.diver;
    final level = run.level;
    final depth = math.max(diver.depthUnder(level), 0.0);
    final rising = diver.velocity.y;
    final minutes = diver.minutesLeft(level);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Wreck Reef',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Depth ${depth.toStringAsFixed(1)} m · '
          '${pressureAt(run.world, depth).toStringAsFixed(2)} atm',
        ),
        Text(
          'Tank ${diver.tankBar.round()} bar — '
          '${minutes.isFinite ? minutes.round() : 0} min at this depth',
          style: TextStyle(
            color: diver.tankBar < 50 ? const Color(0xFFFF8A80) : Colors.white,
          ),
        ),
        Text('Jacket ${diver.jacketVolume(level).toStringAsFixed(1)} L'),
        if (rising > 0.25)
          const Text(
            'Too fast up — dump air from the jacket (Q)',
            style: TextStyle(color: Color(0xFFFFE0A0)),
          ),
        Text('Finds in the boat: ${run.raised} of ${run.finds.finds.length}'),
        for (final b in run.bags.where((b) => b.inUse))
          Text(
            'Bag on the ${b.lifting!.name}: '
            '${b.air.round()} L of air',
            style: const TextStyle(color: Color(0xFFFFD08A)),
          ),
        if (run.said.isNotEmpty)
          Text(run.said, style: const TextStyle(color: Color(0xFFFFE0A0))),
        if (told.isNotEmpty)
          Text(told, style: const TextStyle(color: Color(0xFFB8E0FF))),
        const SizedBox(height: 6),
        const Text(
          'WASD swim · Space up · C down · R fill jacket · Q dump · '
          'E bag / air into bag · drag to look · F5 save dive · '
          'F9 play it back',
          style: TextStyle(color: Color(0xFFB8C2CF), fontSize: 12),
        ),
      ],
    );
  }
}

/// The dive as one part of the loop's snapshots, by id: what a replay
/// restores a run file's start into and digests its checkpoints from
/// (`replayDemoOnLoop`), and what every rewind of the loop covers.
const String _runPart = 'reef.run';

/// [run]'s own save and restore as the loop's part [_runPart].
SnapshotPart _runPartOf(ReefRun run) => SnapshotPart.of(
  id: _runPart,
  capture: () => run.save().data,
  restore: (Object? data, int _) {
    if (data is Map) run.restore(Snapshot(data.cast<String, Object?>()));
  },
);
