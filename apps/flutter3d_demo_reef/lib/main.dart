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
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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

import 'src/diver.dart';
import 'src/sound.dart';
import 'src/staging.dart';

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

  /// What a metre of sea takes out of red, green and blue, and gives back:
  /// clear tropical water's.
  static Vector3 get _absorb => Vector3(0.45, 0.065, 0.025);
  static Vector3 get _scatter => Vector3(0.05, 0.22, 0.30);

  final CameraNode _camera = CameraNode(name: 'eye');
  late final RenderView _view = RenderView(
    camera: _camera,
    clearColor: Vector4(0.55, 0.75, 0.92, 1.0),
  );
  final FrameClock _frames = FrameClock();
  final FocusNode _keyboard = FocusNode();
  Ticker? _ticker;

  ({Renderer renderer, ReefRun run})? _playing;
  Object? _error;
  Speakers? _speakers;
  ReefSound? _sound;
  final AudioListener _listener = AudioListener();

  /// Where the eye looks from: behind the diver by [_yaw], up by [_pitch],
  /// [_distance] off; and which way the diver faces.
  double _yaw = math.pi, _pitch = 0.25, _distance = 4.5, _heading = 0.0;

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
            ..tint(
              shallow: Vector3(0.10, 0.45, 0.50),
              deep: Vector3(0.02, 0.12, 0.22),
              clearness: 0.06,
            );
      final floor =
          await SeabedLook.load(
              device: device,
              renderer: renderer,
              bundle: await rootBundle.load(SeabedLook.asset),
            )
            ..sun(along: _sunAlong, light: _sunLight)
            ..water(absorb: _absorb, scatter: _scatter);
      final scene = Scene()
        ..ambientIntensity = 0.5
        ..ambientColor = Vector3(0.75, 0.85, 1.0)
        ..add(
          LightNode(name: 'sun', intensity: 2.0)..setLocalForward(_sunAlong),
        )
        ..add(_camera);
      final run = ReefRun(
        device: device,
        scene: scene,
        surface: surface,
        floor: floor,
        // A phone draws less of the water and the fire.
        light:
            defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS,
      );
      if (!mounted) return;
      setState(() => _playing = (renderer: renderer, run: run));
      final speakers = await openSpeakers(bank: ReefSound.bank);
      if (!mounted) {
        await speakers?.backend.dispose();
        return;
      }
      _speakers = speakers;
      if (speakers != null) _sound = ReefSound(speakers.scene, run.hearing);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// The way the fins push: the keys, turned by where the eye looks.
  Vector3 _swim(Set<LogicalKeyboardKey> keys) {
    double axis(LogicalKeyboardKey plus, LogicalKeyboardKey minus) =>
        (keys.contains(plus) ? 1.0 : 0.0) - (keys.contains(minus) ? 1.0 : 0.0);
    final ahead = axis(LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyS);
    final side = axis(LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyA);
    final rise = axis(LogicalKeyboardKey.space, LogicalKeyboardKey.keyC);
    // Forward is away from the eye, level; the eye looks along −(yaw).
    final forward = Vector3(-math.cos(_yaw), 0.0, math.sin(_yaw));
    final right = Vector3(-forward.z, 0.0, forward.x);
    final swim = forward * ahead + right * side + Vector3(0.0, rise, 0.0);
    if (ahead != 0.0 || side != 0.0) {
      _heading = math.atan2(
        -(forward * ahead + right * side).z,
        (forward * ahead + right * side).x,
      );
    }
    return swim.length > 1.0 ? swim.normalized() : swim;
  }

  void _onTick(Duration _) {
    // Never more than a thirtieth of a second at once.
    final dt = math.min(_frames.tick(), 1.0 / 30.0);
    final playing = _playing;
    if (playing == null || dt <= 0.0) return;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final swim = _swim(keys);
    playing.run.step(
      dt,
      swim: swim,
      fill: keys.contains(LogicalKeyboardKey.keyR) ? 1.0 : 0.0,
      dump: keys.contains(LogicalKeyboardKey.keyQ) ? 1.0 : 0.0,
      heading: _heading,
    );
    _sound?.update(
      _listener,
      dt,
      breathing: math.min(swim.length, 1.0),
      under: playing.run.diver.depthUnder(playing.run.level) > 0.3,
    );
    if (mounted) setState(() {});
  }

  void _placeCamera() {
    final run = _playing?.run;
    if (run == null) return;
    final target = run.diver.position;
    final eye =
        target +
        Vector3(
              math.cos(_yaw) * math.cos(_pitch),
              math.sin(_pitch),
              -math.sin(_yaw) * math.cos(_pitch),
            ) *
            _distance;
    _camera
      ..setPosition(eye.x, eye.y, eye.z)
      ..lookAt(target);
    run.eye.setFrom(eye);
    _under = eye.y < run.level;
    _listener.aimAlong(eye, target - eye);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final run = _playing?.run;
    if (run == null || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.keyE) {
      return KeyEventResult.ignored;
    }
    run.act();
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
        child: Listener(
          onPointerMove: (PointerMoveEvent event) {
            _yaw -= event.delta.dx * 0.006;
            _pitch = (_pitch + event.delta.dy * 0.004).clamp(-1.2, 1.2);
          },
          onPointerSignal: (PointerSignalEvent event) {
            if (event is! PointerScrollEvent) return;
            _distance = (_distance * math.exp(event.scrollDelta.dy * 0.001))
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
                  bloom: const BloomSettings(enabled: false),
                  sky: SkySettings(
                    enabled: true,
                    zenith: Vector3(0.20, 0.45, 0.85),
                    horizon: Vector3(0.70, 0.82, 0.92),
                    nadir: Vector3(0.05, 0.25, 0.32),
                  ),
                  // Under the surface the sun comes down in shafts through
                  // the water, scattered blue-green.
                  lightShafts: LightShaftSettings(
                    enabled: _under,
                    distance: 30.0,
                    strength: 0.02,
                    color: Vector3(0.45, 0.85, 0.95),
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

/// The gauges, and what the diver can do.
class _Panel extends StatelessWidget {
  const _Panel({required this.run});

  final ReefRun run;

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
          '${pressureAt(depth).toStringAsFixed(2)} atm',
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
        const SizedBox(height: 6),
        const Text(
          'WASD swim · Space up · C down · R fill jacket · Q dump · '
          'E bag / air into bag · drag to look',
          style: TextStyle(color: Color(0xFFB8C2CF), fontSize: 12),
        ),
      ],
    );
  }
}
