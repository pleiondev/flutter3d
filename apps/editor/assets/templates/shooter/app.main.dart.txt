/// A level you can walk around, which is what a new project starts as.
///
///     flutter run -d macos
///
/// **This is a seed, not a game.** It reads the level in `assets/levels/`,
/// builds it, and puts a body in it that walks, looks and jumps. What it
/// deliberately does not do is anything a *genre* does: no weapons, no
/// monsters, no coins, no doors that open, no score, no menu, no saving. Those
/// live in `flutter3d_game_shooter` and `flutter3d_game_platformer`, and wiring one
/// up is the next thing to do here — the three games in this repository are the
/// worked examples, and each of them keeps that wiring in its own
/// `lib/src/staging.dart`.
///
/// It is a real application in this repository as well as a template, so that
/// it is analysed and compiled by CI. **A `main.dart` that is only ever a
/// string in a scaffolder is one that stops compiling six months later and
/// nobody finds out until somebody creates a project.**
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/backend.dart';

/// The level this project opens with.
const String kLevel = String.fromEnvironment(
  'level',
  defaultValue: 'assets/levels/first.json',
);

void main() => runApp(const TemplateApp());

class TemplateApp extends StatelessWidget {
  const TemplateApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'A level',
        debugShowCheckedModeBanner: false,
        home: const LevelScreen(),
      );
}

/// A kind for a type this application has not been taught.
///
/// **The level names things the game does not spawn yet** — a monster, a
/// pickup, a lift — and a registry that has never heard of them refuses to load
/// the document at all. So every type in the document is accepted and none of
/// them is given a meaning: they are coordinates with words attached until
/// there is something to spawn them into.
final class OpenKind extends EntityKind {
  const OpenKind(super.type);
}

class LevelScreen extends StatefulWidget {
  const LevelScreen({super.key});

  @override
  State<LevelScreen> createState() => _LevelScreenState();
}

class _LevelScreenState extends State<LevelScreen>
    with SingleTickerProviderStateMixin {
  Renderer? _renderer;
  Scene? _scene;
  Object? _error;

  final CollisionWorld _world = CollisionWorld();
  CharacterController? _body;

  final CameraNode _camera = CameraNode(name: 'eye');
  late final RenderView _view = RenderView(
    camera: _camera,
    clearColor: Vector4(0.05, 0.05, 0.07, 1.0),
  );

  final InputState _input = InputState();
  late final DesktopInput _keys = DesktopInput(state: _input);
  final FocusNode _keyboard = FocusNode();

  double _yaw = 0.0;
  double _pitch = 0.0;
  Offset? _dragged;

  Ticker? _ticker;
  /// How long since the last frame, and how long since the first.
  final FrameClock _frames = FrameClock();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final device = await GpuRenderBackend.create();
      if (!mounted) return;
      final renderer = Renderer.create(device: device);

      // Read first, build second: the registry is made out of what the document
      // happens to name, which is not knowable before reading it.
      final level = Level.fromJson(
        jsonDecode(await rootBundle.loadString(kLevel)) as Map<String, Object?>,
      );
      final loaded = await LevelLoader().build(
        level,
        device: device,
        registry: EntityRegistry(<EntityKind>[
          for (final type in level.entities.map((EntityDef e) => e.type).toSet())
            OpenKind(type),
        ]),
      );
      loaded.level.addTo(_world);

      // Where the author said somebody stands, lifted by half a body: a spawn
      // is authored at the feet, which is the only place an author can see.
      final spawn = level.entities
          .where((EntityDef it) => it.type.contains('spawn'))
          .firstOrNull;
      final at = (spawn?.position ?? Vector3.zero()) + Vector3(0.0, 0.9, 0.0);

      if (!mounted) return;
      setState(() {
        _renderer = renderer;
        _scene = loaded.scene..add(_camera);
        _body = CharacterController(world: _world, position: at);
        _yaw = spawn?.yaw ?? 0.0;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _onTick(Duration now) {
    final dt = _frames.secondsSince(now);

    final body = _body;
    if (body == null) return;

    if (_input.pressed(GameAction.jump)) body.requestJump();

    // Where the keys are asking to go, turned by where the head is pointing.
    final wish = _input.moveAxis;
    final forward = Vector3(math.sin(_yaw), 0.0, -math.cos(_yaw));
    final right = Vector3(-forward.z, 0.0, forward.x);
    body.step(
      dt.clamp(0.0, 0.1),
      wishDirection: Vector3(
        forward.x * wish.y + right.x * wish.x,
        0.0,
        forward.z * wish.y + right.z * wish.x,
      ),
      sprint: _input.held(GameAction.sprint),
    );

    if (mounted) setState(() {});
  }

  /// Puts the camera at eye height, looking where the mouse has been dragged.
  void _place() {
    final body = _body;
    if (body == null) return;
    final eye = body.position + Vector3(0.0, 0.7, 0.0);
    final cosPitch = math.cos(_pitch);
    _camera
      ..setPosition(eye.x, eye.y, eye.z)
      ..lookAt(
        eye +
            Vector3(
              math.sin(_yaw) * cosPitch,
              math.sin(_pitch),
              -math.cos(_yaw) * cosPitch,
            ),
        up: Vector3(0.0, 1.0, 0.0),
      );
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _keyboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF14161A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('$error',
                style: const TextStyle(color: Color(0xFFFF8A80))),
          ),
        ),
      );
    }

    final renderer = _renderer;
    final scene = _scene;
    if (renderer == null || scene == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF14161A),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF14161A),
      body: Focus(
        focusNode: _keyboard,
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) =>
            _keys.handleKeyEvent(event),
        child: Listener(
          onPointerDown: (PointerDownEvent event) {
            _keyboard.requestFocus();
            _dragged = event.localPosition;
          },
          onPointerMove: (PointerMoveEvent event) {
            final from = _dragged;
            if (from == null) return;
            final by = event.localPosition - from;
            _dragged = event.localPosition;
            _yaw -= by.dx * 0.0032;
            _pitch = (_pitch - by.dy * 0.0032).clamp(-1.5, 1.5);
          },
          onPointerUp: (_) => _dragged = null,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              SceneSurface(
                renderer: renderer,
                scene: scene,
                view: _view,
                settings: () => const RenderSettings(),
                onBeforeFrame: _place,
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: Color(0xCC0E1013),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      'W A S D walk · shift runs · space jumps · drag to look',
                      style: TextStyle(color: Color(0xFF9AA4B2), fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
