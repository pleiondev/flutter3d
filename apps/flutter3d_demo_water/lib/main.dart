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
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show preparePhysics;
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/staging.dart';
import 'src/valley.dart';

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
    clearColor: Vector4(0.62, 0.76, 0.9, 1.0),
  );
  final FrameClock _frames = FrameClock();
  final FocusNode _keyboard = FocusNode();
  Ticker? _ticker;

  ({Renderer renderer, WaterRun run})? _playing;
  Object? _error;

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
      // The water's material, as `flutter3d_effects` ships it.
      final water = await WaterLook.load(
        device: device,
        renderer: renderer,
        bundle: await rootBundle.load(WaterLook.asset),
      )..sun(along: _sunAlong, light: Vector3(2.0, 1.95, 1.85));
      final scene = Scene()
        ..ambientIntensity = 0.45
        ..ambientColor = Vector3(0.70, 0.80, 1.0)
        ..add(
          // From over the pond's side, so the falls and the cliff behind them
          // are in the sun.
          LightNode(name: 'sun', intensity: 2.0)..setLocalForward(_sunAlong),
        )
        ..add(_camera);
      final run = WaterRun(device, scene, water, renderer);
      if (!mounted) return;
      setState(() => _playing = (renderer: renderer, run: run));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _onTick(Duration _) {
    // Never more than a thirtieth of a second at once: a stall in the window
    // is not a flood in the valley.
    final dt = math.min(_frames.tick(), 1.0 / 30.0);
    final playing = _playing;
    if (playing == null || dt <= 0.0) return;
    playing.run.step(dt);
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
    if (hit != null) run.dropStone(hit);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final run = _playing?.run;
    if (run == null || event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyS:
        run.dropStone();
      case LogicalKeyboardKey.keyL:
        run.dropLog();
      case LogicalKeyboardKey.keyF:
        run.bonfire.light();
      case LogicalKeyboardKey.keyE:
        run.bonfire.douse();
      case LogicalKeyboardKey.keyW:
        run.windy = !run.windy;
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _keyboard.dispose();
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
                    zenith: Vector3(0.22, 0.42, 0.78),
                    horizon: Vector3(0.68, 0.79, 0.92),
                    nadir: Vector3(0.30, 0.32, 0.30),
                  ),
                ),
                onBeforeFrame: _placeCamera,
                presentFrame: presentFrame,
              ),
              Positioned(
                left: 16,
                top: 16,
                child: SafeArea(child: _Panel(run: playing.run)),
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
  const _Panel({required this.run});

  final WaterRun run;

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
            run.fireView.burning == 0
                ? 'Bonfire cold'
                : 'Bonfire: ${run.fireView.burning} '
                      '${run.fireView.burning == 1 ? 'log' : 'logs'} burning, '
                      '${(run.fireView.watts / 1000).round()} kW going up',
          ),
          const SizedBox(height: 6),
          const Text(
            'drag to look · scroll to zoom · click drops a stone · S stone · L log · '
            'W wind · F light the fire · E douse it',
            style: TextStyle(color: Color(0xFFB8C2CF), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
