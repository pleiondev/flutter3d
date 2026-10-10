/// A valley of water: a spring on a plateau, the stream it feeds winding
/// down to a cliff, the waterfall off it, and the pond at its foot draining
/// off the map.
///
///     flutter run -d macos
///
/// All of it is the physics core's shallow water: the stream finds its own
/// way down the bed, the falls are the spray it throws off the cliff, and
/// the waves on the pond are what the falls and the stones dropped in push
/// out. Drag to look round, scroll to come closer; a click drops a stone
/// where it points, S drops one into the pond, L puts a log in the stream, W
/// turns a wind down the valley on and off. On the bank a bonfire is laid:
/// F lights it, and it burns, spreads from log to log and leans in the wind
/// as the core's heat has it; E throws water on it.
///
/// Every key and click is input the fixed step reads, so the valley is
/// recorded as it is played: F5 keeps the run so far as a `.f3drun` — the
/// tape, the loop's journal, each step's events, checkpoints of the whole
/// state and where every stone went — and F9 plays the last one kept back
/// from its start and says whether it went where it went.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show DemoFile, DemoReplay;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show preparePhysics;
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show EngineLoop, GameAction, InputState, ReplayException;

import 'src/runs.dart';
import 'src/staging.dart';
import 'src/valley.dart';

/// What this build calls itself in a run file.
const String _buildStamp = String.fromEnvironment(
  'FLUTTER3D_BUILD_STAMP',
  defaultValue: 'dev',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await preparePhysics();
  runApp(const WaterApp());
}

/// The application: one screen.
class WaterApp extends StatelessWidget {
  const WaterApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Water',
    debugShowCheckedModeBanner: false,
    home: WaterScreen(),
  );
}

/// Opens the device and runs the valley.
class WaterScreen extends StatefulWidget {
  const WaterScreen({super.key});

  @override
  State<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends State<WaterScreen>
    with SingleTickerProviderStateMixin {
  /// Where the sun shines along.
  static Vector3 get _sunAlong => Vector3(0.35, -0.7, -0.6);

  final CameraNode _camera = CameraNode(name: 'eye');
  late final RenderView _view = RenderView(
    camera: _camera,
    clearColorSrgb: Vector4(0.62, 0.76, 0.9, 1.0),
  );
  final FrameClock _frames = FrameClock();
  final FocusNode _keyboard = FocusNode();
  Ticker? _ticker;

  ({Renderer renderer, WaterRun run})? _playing;
  Object? _error;

  /// The valley's loop: its fixed steps, phase by phase. Made with the run;
  /// never more than a thirtieth of a second of a stall is stepped — a
  /// stall in the window is not a flood in the valley.
  EngineLoop? _loop;

  /// What the keys and the pointer ask for, read by the valley's step.
  final InputState _input = InputState();

  /// The run being recorded, and the last one kept.
  WaterRuns? _runs;

  /// What the last keep or replay came to, for the panel.
  String _said = 'F5 keeps the run · F9 plays the last one back';

  /// Where the eye looks from, round the falls.
  double _yaw = 0.6, _pitch = 0.45, _distance = 26.0;

  /// How far the pointer has moved since it went down: a click drops a
  /// stone, a drag turns the view.
  double _dragged = 0.0;
  Size _size = Size.zero;
  final Raycaster _raycaster = Raycaster();

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
        ..ambientIntensity = 0.45 * Photometric.legacyUnit
        ..ambientColor = LinearColor(0.70, 0.80, 1.0)
        ..add(
          // From over the pond's side, so the falls and the cliff behind them
          // are in the sun.
          LightNode(name: 'sun', intensity: 2.0 * Photometric.legacyUnit)
            ..setLocalForward(_sunAlong),
        )
        ..add(_camera);
      // The valley's water, the bonfire and what is thrown in: the effects
      // package's elements, over a world of the physics core's they own.
      final elements = await Elements.open(
        device: device,
        renderer: renderer,
        scene: scene,
        load: rootBundle.load,
      );
      final run = WaterRun(
        device,
        scene,
        elements,
        sun: (along: _sunAlong, light: Vector3(2.0, 1.95, 1.85)),
        input: _input,
      );
      if (!mounted) return;
      final loop = EngineLoop(input: _input, longestFrame: 1.0 / 30.0);
      run.install(loop);
      _loop = loop;
      _runs = WaterRuns(
        loop: loop,
        run: run,
        file: DemoFile(appName: 'flutter3d_demo_water'),
        buildStamp: _buildStamp,
        platform: defaultTargetPlatform.name,
      )..begin();
      setState(() => _playing = (renderer: renderer, run: run));
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
    final target = Vector3(16.0, 2.0, 15.0);
    final eye =
        target +
        Vector3(
              math.sin(_yaw) * math.cos(_pitch),
              math.sin(_pitch),
              math.cos(_yaw) * math.cos(_pitch),
            ) *
            _distance;
    _camera
      ..setPosition(eye.x, eye.y, eye.z)
      ..lookAt(target);
    _playing?.run.eye.setFrom(eye);
  }

  /// A stone dropped where the pointer at [at] meets the valley.
  void _dropAt(WaterRun run, Offset at) {
    if (_size.isEmpty) return;
    _placeCamera();
    _raycaster.setFromNdc(
      _camera,
      at.dx / _size.width * 2.0 - 1.0,
      1.0 - at.dy / _size.height * 2.0,
      aspect: _size.width / _size.height,
    );
    final hit = run.hit(_raycaster.ray.origin, _raycaster.ray.direction);
    if (hit == null) return;
    // The point is input too: the step reads it from the tunes, and the
    // tape keeps it with the press.
    _input
      ..tune(WaterActions.dropX, hit.x)
      ..tune(WaterActions.dropY, hit.y)
      ..tune(WaterActions.dropZ, hit.z)
      ..press(WaterActions.dropStoneAt)
      ..release(WaterActions.dropStoneAt);
  }

  /// The keys, as the actions the step reads.
  static final Map<LogicalKeyboardKey, GameAction> _keys =
      <LogicalKeyboardKey, GameAction>{
        LogicalKeyboardKey.keyS: WaterActions.dropStone,
        LogicalKeyboardKey.keyL: WaterActions.dropLog,
        LogicalKeyboardKey.keyF: WaterActions.light,
        LogicalKeyboardKey.keyE: WaterActions.douse,
        LogicalKeyboardKey.keyW: WaterActions.wind,
      };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_playing == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.f5:
          _keep();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.f9:
          _replay();
          return KeyEventResult.handled;
      }
    }
    final action = _keys[event.logicalKey];
    if (action == null) return KeyEventResult.ignored;
    switch (event) {
      case KeyDownEvent():
        _input.press(action);
      case KeyUpEvent():
        _input.release(action);
      default:
    }
    return KeyEventResult.handled;
  }

  /// Keeps the run so far, and says so.
  void _keep() {
    final kept = _runs?.keep();
    setState(
      () => _said = kept == null
          ? 'Nothing to keep yet'
          : 'Kept a run of ${kept.tape.steps} steps',
    );
  }

  /// Plays the last run kept back from its start, and says how it went.
  Future<void> _replay() async {
    final runs = _runs;
    if (runs == null) return;
    String said;
    try {
      final replay = await runs.replay();
      said = switch (replay) {
        null => 'No run kept to play back',
        DemoReplay(divergence: final d?) =>
          'Played ${replay.steps} steps; it parted at step ${d.step}',
        DemoReplay(eventDivergence: final e?) =>
          'Played ${replay.steps} steps; the events parted at step ${e.step}',
        _ => 'Played ${replay.steps} steps, every checkpoint matched',
      };
    } on ReplayException catch (refused) {
      said = 'Not replayed: ${refused.message}';
    } on FormatException catch (error) {
      said = 'Not replayed: ${error.message}';
    }
    if (!mounted) return;
    setState(() => _said = said);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _keyboard.dispose();
    _runs?.dispose();
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
        child: Listener(
          onPointerDown: (_) {
            _keyboard.requestFocus();
            _dragged = 0.0;
          },
          onPointerUp: (PointerUpEvent event) {
            if (_dragged < 6.0) _dropAt(playing.run, event.localPosition);
          },
          onPointerMove: (PointerMoveEvent event) {
            _dragged += event.delta.distance;
            _yaw -= event.delta.dx * 0.006;
            _pitch = (_pitch + event.delta.dy * 0.004).clamp(0.08, 1.4);
          },
          onPointerSignal: (PointerSignalEvent event) {
            if (event is! PointerScrollEvent) return;
            _distance = (_distance * math.exp(event.scrollDelta.dy * 0.001))
                .clamp(4.0, 60.0);
          },
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  _size = box.biggest;
                  return const SizedBox.expand();
                },
              ),
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
                  child: _Panel(run: playing.run, said: _said),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  };
}

/// What the water holds and the keys.
class _Panel extends StatelessWidget {
  const _Panel({required this.run, required this.said});

  final WaterRun run;

  /// What the last keep or replay came to.
  final String said;

  @override
  Widget build(BuildContext context) {
    final v = run.volume;
    return DefaultTextStyle(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        shadows: <Shadow>[Shadow(blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Spring ${(springRate * 1000).round()} L/s · '
            'pond at ${run.pondLevel.toStringAsFixed(3)} m · '
            'held ${v.held.toStringAsFixed(1)} m³ · '
            'run off ${v.lost.toStringAsFixed(1)} m³',
          ),
          Text(
            '${run.sprayInFlight} pieces falling · '
            '${run.bubbleClouds} clouds of bubbles · '
            'wind ${run.windy ? 'blowing' : 'still'} · '
            'valley ${valleySize.round()} m',
          ),
          Text(
            run.elements.fireView.burning == 0
                ? 'Bonfire cold'
                : 'Bonfire: ${run.elements.fireView.burning} '
                      '${run.elements.fireView.burning == 1 ? 'log' : 'logs'} burning, '
                      '${(run.elements.fireView.watts / 1000).round()} kW going up',
          ),
          Text(said),
          const SizedBox(height: 6),
          const Text(
            'drag to look · scroll to zoom · click drops a stone · S stone · L log · '
            'W wind · F light the fire · E douse it · F5 keep the run · '
            'F9 play it back',
            style: TextStyle(color: Color(0xFFB8C2CF), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
