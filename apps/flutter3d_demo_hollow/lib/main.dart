/// Cobble Hollow: a stone-age valley on the physics core.
///
///     flutter run -d macos
///
/// A river runs over a plateau and falls into a lagoon, a quarry waits for
/// a crane, and a volcano in the corner sets the village alight now and
/// then. Everything in it is the physics core's: the river and the lava are
/// shallow liquids, the fires the core's heat, the car and the crane its
/// vehicle and multibody.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show preparePhysics;
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/sound.dart';
import 'src/staging.dart';

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
    clearColor: Vector4(0.62, 0.76, 0.9, 1.0),
  );
  final FrameClock _frames = FrameClock();
  final FocusNode _keyboard = FocusNode();
  Ticker? _ticker;

  ({Renderer renderer, HollowRun run})? _playing;
  Object? _error;

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
      final bundle = await rootBundle.load(LiquidLook.asset);
      final water = await LiquidLook.load(
        device: device,
        renderer: renderer,
        bundle: bundle,
      );
      // The lava: the same material, dark and opaque, glowing where its
      // flow breaks the crust.
      final lava = LiquidLook.of(bundle)
        ..tint(
          shallow: Vector3(0.18, 0.05, 0.02),
          deep: Vector3(0.05, 0.02, 0.01),
          clearness: 1e-6,
        )
        ..glow = Vector3(6.0, 1.6, 0.25);
      for (final look in <LiquidLook>[water, lava]) {
        look.sun(along: _sunAlong, light: Vector3(2.0, 1.9, 1.75));
      }
      final scene = Scene()
        ..ambientIntensity = 0.45
        ..ambientColor = Vector3(0.70, 0.80, 1.0)
        ..add(
          LightNode(name: 'sun', intensity: 2.0)..setLocalForward(_sunAlong),
        )
        ..add(_camera);
      final run = HollowRun(
        device: device,
        scene: scene,
        renderer: renderer,
        water: water,
        lava: lava,
      );
      if (!mounted) return;
      setState(() => _playing = (renderer: renderer, run: run));
      final speakers = await openSpeakers(bank: HollowSound.bank);
      if (!mounted) {
        await speakers?.backend.dispose();
        return;
      }
      _speakers = speakers;
      if (speakers != null) _sound = HollowSound(speakers.scene, run.hearing);
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
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    double axis(LogicalKeyboardKey plus, LogicalKeyboardKey minus) =>
        (keys.contains(plus) ? 1.0 : 0.0) - (keys.contains(minus) ? 1.0 : 0.0);
    final run = playing.run;
    if (run.craning) {
      run.car.drive(throttle: 0, turn: 0, hold: true);
      run.crane.work(
        lift: axis(LogicalKeyboardKey.keyI, LogicalKeyboardKey.keyK),
        swing: axis(LogicalKeyboardKey.keyJ, LogicalKeyboardKey.keyL),
      );
    } else {
      run.crane.work(lift: 0, swing: 0);
      run.car.drive(
        throttle: axis(LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyS),
        turn: axis(LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyD),
        hold: keys.contains(LogicalKeyboardKey.space),
      );
    }
    playing.run.step(dt);
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final run = _playing?.run;
    if (run == null || event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyE:
        run.act();
      case LogicalKeyboardKey.keyR:
        run.car.rightUp();
      case LogicalKeyboardKey.keyC:
        run.craning = !run.craning && run.nearCrane;
        run.said = run.craning
            ? 'At the crane: I/K neck, J/L swing, G rope, C to drive.'
            : run.nearCrane
            ? 'Back in the car.'
            : 'Drive up to the crane at the quarry first.';
      case LogicalKeyboardKey.keyG when run.craning:
        run.crane.grab(run.stones.bodies);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _keyboard.dispose();
    _sound?.stop();
    unawaited(_speakers?.backend.dispose());
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
                child: SafeArea(
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      shadows: <Shadow>[Shadow(blurRadius: 4)],
                    ),
                    child: _Panel(run: playing.run),
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
  const _Panel({required this.run});

  final HollowRun run;

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
        const SizedBox(height: 6),
        const Text(
          'WASD drive · Space brake · E act · C crane · R right the car · '
          'drag to look',
          style: TextStyle(color: Color(0xFFB8C2CF), fontSize: 12),
        ),
      ],
    );
  }
}
