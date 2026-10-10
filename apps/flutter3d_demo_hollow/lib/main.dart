/// Cobble Hollow: a stone-age valley on the physics core.
///
///     flutter run -d macos
///
/// A river runs over a plateau and falls into a lagoon, a quarry waits for
/// a crane, and a volcano in the corner sets the village alight now and
/// then. Everything in it is the physics core's: the river and the lava are
/// shallow liquids, the fires the core's heat, the car and the crane its
/// vehicle and multibody.
///
/// The keys write an [InputState] and the valley's step reads only that, so
/// a run is its tape: F5 writes the run so far to a `.f3drun`, F9 plays the
/// saved one back from its start and checks it against its own checkpoints.
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

import 'src/looks.dart';
import 'src/sound.dart';
import 'src/staging.dart';

/// Which build wrote a `.f3drun`: whatever the release passes in, `dev`
/// otherwise — the convention every demo here keeps.
const String _buildStamp = String.fromEnvironment(
  'FLUTTER3D_BUILD_STAMP',
  defaultValue: 'dev',
);

/// What each key asks of the valley, as an action map over
/// [HollowActions.set]. Held keys hold an action; the others are pressed once
/// and read by the next step. The crane's neck and swing are axes, each on
/// two keys.
ActionMap hollowControls() {
  InputSource key(LogicalKeyboardKey key) => InputSource.key(key.keyId);
  return ActionMap(
    actions: HollowActions.set,
    buttons: Bindings(<InputSource, GameAction>{
      key(LogicalKeyboardKey.keyW): GameAction.moveForward,
      key(LogicalKeyboardKey.keyS): GameAction.moveBack,
      key(LogicalKeyboardKey.keyA): GameAction.moveLeft,
      key(LogicalKeyboardKey.keyD): GameAction.moveRight,
      key(LogicalKeyboardKey.space): HollowActions.brake,
      key(LogicalKeyboardKey.keyE): HollowActions.act,
      key(LogicalKeyboardKey.keyR): HollowActions.rightUp,
      key(LogicalKeyboardKey.keyC): HollowActions.crane,
      key(LogicalKeyboardKey.keyG): HollowActions.grab,
    }),
    axes: <ActionBinding>[
      AxisComposite(
        HollowActions.lift,
        negative: key(LogicalKeyboardKey.keyK),
        positive: key(LogicalKeyboardKey.keyI),
      ),
      AxisComposite(
        HollowActions.swing,
        negative: key(LogicalKeyboardKey.keyL),
        positive: key(LogicalKeyboardKey.keyJ),
      ),
    ],
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await preparePhysics();
  runApp(const HollowApp());
}

/// The application: one screen.
class HollowApp extends StatelessWidget {
  const HollowApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Cobble Hollow',
    debugShowCheckedModeBanner: false,
    home: HollowScreen(),
  );
}

/// Opens the device and runs the valley.
class HollowScreen extends StatefulWidget {
  const HollowScreen({super.key});

  @override
  State<HollowScreen> createState() => _HollowScreenState();
}

class _HollowScreenState extends State<HollowScreen>
    with SingleTickerProviderStateMixin {
  /// Where the sun shines along: low from the south-west, an afternoon.
  static Vector3 get _sunAlong => Vector3(0.45, -0.6, -0.65);

  final CameraNode _camera = CameraNode(name: 'eye');
  late final RenderView _view = RenderView(
    camera: _camera,
    clearColorSrgb: Vector4(0.62, 0.76, 0.9, 1.0),
  );
  final FrameClock _frames = FrameClock();
  final FocusNode _keyboard = FocusNode();
  Ticker? _ticker;

  ({Renderer renderer, HollowRun run})? _playing;
  Object? _error;

  /// The valley's loop: its fixed steps, phase by phase, then the frame.
  /// Made with the run.
  EngineLoop? _loop;

  /// What the keys ask of the valley, which its step alone reads.
  final InputState _input = InputState();

  /// The keys, as [hollowControls] binds them.
  final ActionMap _controls = hollowControls();

  /// The crane's two axes from their keys.
  late final ActionInput _axes = ActionInput(state: _input, map: _controls);

  /// Drops every held key and axis — a lost focus never sends the key-ups.
  void _letGo() {
    _input.clear();
    _axes.letGo();
  }

  /// The valley's own `.f3drun`, on disk, and the run being written into it
  /// from the moment the valley opened.
  final DemoFile _runs = DemoFile(appName: 'hollow');
  DemoRecording? _recording;
  void Function()? _stopCheckpoints;

  /// What the window last said about the run file, beside what the valley
  /// says: a line of its own, since the valley's words are its state.
  String _told = '';

  /// The speakers, once open — or never, on a machine with no sound — and
  /// what the valley plays through them.
  Speakers? _speakers;
  HollowSound? _sound;
  final AudioListener _listener = AudioListener();

  /// Where the eye looks from: round behind the car by [_yaw], up by
  /// [_pitch], [_distance] off.
  double _yaw = 0.0, _pitch = 0.35, _distance = 10.0;

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
      final scene = Scene()
        // The sky's light in the shade, and what the warm ground throws
        // back into it: not the blue of the sky alone.
        ..ambientIntensity = 0.6 * Photometric.legacyUnit
        ..ambientColor = LinearColor(0.86, 0.88, 0.94)
        ..add(
          LightNode(name: 'sun', intensity: 2.0 * Photometric.legacyUnit)
            ..setLocalForward(_sunAlong),
        )
        ..add(_camera);
      final looks = await HollowLooks.load(device);
      // A phone draws less of the water and the fire.
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
            ..sun(along: _sunAlong, light: Vector3(2.0, 1.9, 1.75));
      final run = HollowRun(
        device: device,
        scene: scene,
        elements: elements,
        looks: looks,
        input: _input,
      );
      if (!mounted) return;
      // A stall in the window is not a flood in the valley: never more than
      // a thirtieth of a second of it is stepped, as before the loop.
      final loop = EngineLoop(input: _input, longestFrame: 1.0 / 30.0)
        ..snapshots.add(_runPartOf(run));
      run.install(loop);
      _loop = loop;
      _record(run, loop);
      setState(() => _playing = (renderer: renderer, run: run));
      // A machine with no audio device plays the same valley, silent.
      final Speakers speakers;
      try {
        speakers = await openSpeakers(bank: HollowSound.bank);
      } on AudioDeviceException {
        return;
      }
      if (!mounted) {
        await speakers.dispose();
        return;
      }
      _speakers = speakers;
      _sound = HollowSound(speakers.scene, run.hearing);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _onTick(Duration _) {
    final dt = _frames.tick();
    final loop = _loop;
    if (_playing == null || loop == null) return;
    loop.frame(dt);
    if (mounted) setState(() {});
  }

  void _placeCamera() {
    final car = _playing?.run.car;
    if (car == null) return;
    final target = car.position + Vector3(0.0, 1.0, 0.0);
    // Behind the car, turned by however far the pointer has turned it.
    final heading = math.atan2(-car.forward.z, car.forward.x) + _yaw;
    final eye =
        target +
        Vector3(
              -math.cos(heading) * math.cos(_pitch),
              math.sin(_pitch),
              math.sin(heading) * math.cos(_pitch),
            ) *
            _distance;
    _camera
      ..setPosition(eye.x, eye.y, eye.z)
      ..lookAt(target);
    _playing?.run.eye.setFrom(eye);
    _listener.aimAlong(eye, target - eye);
    _sound?.update(_listener);
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

  /// Starts writing the run down from the state [run] is in now, through
  /// [loop]: its input, its journal and each step's events, a checkpoint
  /// every two seconds and the moving bodies' poses.
  void _record(HollowRun run, EngineLoop loop) {
    _stopRecording();
    final start = run.save();
    final recording = DemoRecording(
      physics: usePhysics(),
      level: 'hollow:valley',
      levelHash: StateDigest.of(start.toJson()).toRadixString(16),
      start: start,
      seed: 7,
      // The world's snapshot is the river's and the lava's grids as well
      // as the bodies: taken every two seconds rather than every
      // twenty-five steps.
      checkpointEvery: 120,
      simulation: hollowSimulation,
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

  /// F5: the run so far, written to the valley's `.f3drun`.
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
          ? 'Run saved: ${recording.steps} steps. F9 plays it back.'
          : 'The run could not be saved.',
    );
  }

  /// F9: the saved run played back from its start, as fast as it steps,
  /// checked against its own checkpoints; the valley is left where the run
  /// ended, and a new recording begins from there.
  Future<void> _replay() async {
    final run = _playing?.run;
    final loop = _loop;
    if (run == null || loop == null) return;
    final demo = await _runs.read();
    if (!mounted) return;
    if (demo == null) {
      setState(() => _told = 'There is no saved run to play back.');
      return;
    }
    _stopRecording();
    _letGo();
    String told;
    try {
      final result = replayDemoOnLoop(
        demo: demo,
        loop: loop,
        part: _runPart,
        simulation: hollowSimulation,
        // A run from before the crane's axes replays with them.
        actions: HollowActions.set,
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
      told = 'The run could not be played back: ${error.message}';
    }
    _letGo();
    loop.resetClock();
    _record(run, loop);
    setState(() => _told = told);
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
      background: const Color(0xFF14161A),
      foreground: const Color(0xFFFF8A80),
    ),
    (_, null) => const ColoredBox(
      color: Color(0xFF14161A),
      child: Center(child: CircularProgressIndicator()),
    ),
    (_, final playing?) => Scaffold(
      backgroundColor: const Color(0xFF14161A),
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
            _yaw -= event.delta.dx * 0.006;
            _pitch = (_pitch + event.delta.dy * 0.004).clamp(0.08, 1.4);
          },
          onPointerSignal: (PointerSignalEvent event) {
            if (event is! PointerScrollEvent) return;
            _distance = (_distance * math.exp(event.scrollDelta.dy * 0.001))
                .clamp(5.0, 120.0);
          },
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              SceneSurface(
                renderer: playing.renderer,
                scene: playing.run.scene,
                view: _view,
                settings: () => RenderSettings(
                  exposure: 0.7,
                  bloom: const BloomSettings(enabled: false),
                  sky: SkySettings(
                    enabled: true,
                    zenith: LinearColor(0.22, 0.42, 0.78),
                    horizon: LinearColor(0.68, 0.79, 0.92),
                    nadir: LinearColor(0.30, 0.32, 0.30),
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

/// The tasks, and what the player can do.
class _Panel extends StatelessWidget {
  const _Panel({required this.run, required this.told});

  final HollowRun run;

  /// What the window said about the run file.
  final String told;

  @override
  Widget build(BuildContext context) {
    final burning = run.village.burning;
    final volcano = run.volcano;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Cobble Hollow',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Stone for the builder: ${run.stones.delivered} of 3 '
          '(the crane at the quarry lifts them onto the car)',
        ),
        Text(
          burning == 0
              ? (volcano.erupting
                    ? 'The volcano is throwing fire at the village!'
                    : 'The volcano sleeps — '
                          '${volcano.untilNext.round()} s')
              : '$burning ${burning == 1 ? 'hut burns' : 'huts burn'}: '
                    'fill the barrel at the water, E to throw it',
        ),
        Text(
          run.idol.home
              ? "The elder's idol is home."
              : run.idol.carried
              ? "The elder's idol rides on the car: bring it to the village, "
                    'E to set it down'
              : "The elder's idol lies on the lagoon's floor: drive in by "
                    'the south bank, E to lift it',
        ),
        Text('Barrel ${run.car.water.round()} kg'),
        if (run.said.isNotEmpty)
          Text(run.said, style: const TextStyle(color: Color(0xFFFFE0A0))),
        if (told.isNotEmpty)
          Text(told, style: const TextStyle(color: Color(0xFFB8E0FF))),
        const SizedBox(height: 6),
        const Text(
          'WASD drive · Space brake · E act · C crane · R right the car · '
          'drag to look · F5 save run · F9 play it back',
          style: TextStyle(color: Color(0xFFB8C2CF), fontSize: 12),
        ),
      ],
    );
  }
}

/// The valley's run as one part of the loop's snapshots, by id: what a replay
/// restores a run file's start into and digests its checkpoints from
/// (`replayDemoOnLoop`), and what every rewind of the loop covers.
const String _runPart = 'hollow.run';

/// [run]'s own save and restore as the loop's part [_runPart].
SnapshotPart _runPartOf(HollowRun run) => SnapshotPart.of(
  id: _runPart,
  capture: () => run.save().data,
  restore: (Object? data, int _) {
    if (data is Map) run.restore(Snapshot(data.cast<String, Object?>()));
  },
);
