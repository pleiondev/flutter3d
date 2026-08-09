import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
// `Material` exists in both flutter/material.dart and flutter3d; the level
// loader is the only place that builds one, so it is hidden here.
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'src/level_scene.dart';

/// The game, as far as it goes: a room to stand in and a camera to look around
/// with.
///
/// Deliberately thin. Everything that could live in a package does — the
/// renderer in `flutter3d`, the clock and the input in `flutter3d_game`, the
/// pointer capture in `mouse_capture` — and what is left here is the part that
/// is specific to this game. Right now that is a handful of boxes, because the
/// level format does not exist yet.
///
/// What this proves, which no unit test can: that the fixed step, the captured
/// mouse and the renderer agree with each other at 60 Hz on a real device.
void main() {
  runApp(const DungeonApp());
}

class DungeonApp extends StatelessWidget {
  const DungeonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Dungeon',
      debugShowCheckedModeBanner: false,
      home: GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  /// Radians of view movement per unit of mouse motion.
  static const double _lookSensitivity = 0.0022;

  /// How far the player can look up or down.
  ///
  /// Just short of straight up: at exactly a right angle the forward vector
  /// becomes parallel to the world up axis and the camera's orientation stops
  /// being defined.
  static const double _pitchLimit = math.pi / 2.0 - 0.01;


  final InputState _input = InputState();
  late final DesktopInput _devices;
  late final GameLoop _loop;
  late final Ticker _ticker;

  /// The level, once it has loaded. Null while it is loading or if it failed.
  LoadedLevel? _loaded;
  CharacterController? _body;

  final CameraNode _camera = CameraNode(name: 'player');
  late final RenderView _view;
  Renderer? _renderer;
  Object? _initError;

  /// How far the eye sits above the centre of the player's box.
  static const double _eyeOffset = 0.7;

  final InterpolatedVector3 _smoothedPosition = InterpolatedVector3();

  double _yaw = 0.0;
  double _pitch = 0.0;

  Duration _lastTick = Duration.zero;
  int _steps = 0;
  double _fps = 0.0;

  // Scratch vectors, reused every step. Allocating these per frame is the
  // easiest way to hand the collector work it does not need.
  final Vector3 _forward = Vector3.zero();
  final Vector3 _right = Vector3.zero();
  final Vector3 _wish = Vector3.zero();
  final Vector3 _eye = Vector3.zero();
  final Vector3 _target = Vector3.zero();

  @override
  void initState() {
    super.initState();

    _devices = DesktopInput(state: _input);
    _loop = GameLoop(
      input: _input,
      onStep: _step,
      drainLook: _devices.drainLook,
    );

    _view = RenderView(camera: _camera);

    try {
      _renderer = Renderer.create(
        fallbackAlbedo: SolidColorTexture.white.upload(),
        fallbackNormal: SolidColorTexture.flatNormal.upload(),
      );
    } catch (error) {
      _initError = error;
    }

    _ticker = createTicker(_onTick)..start();
    unawaited(_loadLevel());
  }

  Future<void> _loadLevel() async {
    try {
      final loaded = await const LevelLoader().load(_levelAsset);
      final start = loaded.level.playerStart;

      final body = CharacterController(
        world: loaded.collision,
        // Lifted by half the body height: a spawn is authored where the
        // player's feet go, which is the only place an author can see.
        position: (start?.position ?? Vector3.zero()) + Vector3(0.0, 0.9, 0.0),
      );

      if (!mounted) return;
      setState(() {
        _loaded = loaded;
        _body = body;
        _yaw = start?.yaw ?? 0.0;
        _smoothedPosition.jumpTo(body.position);
        // Loading blocked the ticker for a couple of seconds, and all of that
        // time is sitting in the accumulator. None of it happened in the game,
        // so it is dropped rather than simulated — otherwise the first frame
        // spends its whole budget catching up, and the dropped-step counter
        // reads as a performance problem for the rest of the session.
        _loop.clock.reset();
      });

      for (final issue in loaded.issues) {
        debugPrint('level: $issue');
      }
    } catch (error, stack) {
      debugPrint('level failed to load: $error\n$stack');
      if (mounted) setState(() => _initError = error);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _devices.dispose();
    super.dispose();
  }

  static const String _levelAsset = 'assets/levels/crypt.json';

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt > 0.0) _fps = _fps * 0.9 + (1.0 / dt) * 0.1;

    _steps = _loop.advance(dt);
    setState(() {});
  }

  /// One step of simulated time. Everything that decides where the player is
  /// happens here and nowhere else.
  void _step(double dt) {
    final body = _body;
    final loaded = _loaded;
    if (body == null || loaded == null) return;

    _yaw -= _input.lookDelta.x * _lookSensitivity;
    _pitch = (_pitch - _input.lookDelta.y * _lookSensitivity)
        .clamp(-_pitchLimit, _pitchLimit);

    // Movement follows the yaw only. Walking forward while looking at the floor
    // must not drive the player into it — that is what a fly camera does, and
    // not what a first-person one should.
    final axis = _input.moveAxis;
    final sin = math.sin(_yaw);
    final cos = math.cos(_yaw);
    _forward.setValues(-sin, 0.0, -cos);
    _right.setValues(cos, 0.0, -sin);
    _wish.setValues(
      _forward.x * axis.y + _right.x * axis.x,
      0.0,
      _forward.z * axis.y + _right.z * axis.x,
    );

    if (_input.pressed(GameAction.jump)) body.requestJump();

    body.step(
      dt,
      wishDirection: _wish,
      sprint: _input.held(GameAction.sprint),
    );

    loaded.collision.update();
    loaded.collision.clearKinematicDeltas();

    _smoothedPosition.push(body.position);
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    final loaded = _loaded;
    final body = _body;
    if (renderer == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Text(
              'The renderer did not start.\n\n$_initError\n\n'
              'The shader bundle is built by '
              'packages/flutter3d/tool/build_shaders.sh, and has to be rebuilt '
              'after every Flutter SDK change.',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    if (loaded == null || body == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Loading the crypt…',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, KeyEvent event) => _devices.handleKeyEvent(event),
        child: Listener(
          onPointerDown: (_) {
            if (_devices.isCaptured) {
              _devices.pressPointer();
            } else {
              _devices.enterFirstPerson();
            }
          },
          onPointerUp: (_) => _devices.releasePointer(),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _SceneSurface(
                renderer: renderer,
                scene: loaded.scene,
                view: _view,
                onBeforeFrame: _placeCamera,
              ),
              _Hud(
                captured: _devices.isCaptured,
                fps: _fps,
                steps: _steps,
                dropped: _loop.clock.droppedSteps,
                position: body.position,
                grounded: body.isGrounded,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Places the camera for the frame about to be drawn.
  ///
  /// Reads the interpolated position rather than the simulated one: on a
  /// display faster than the step rate, several frames in a row would otherwise
  /// show the same place and then jump.
  void _placeCamera() {
    _smoothedPosition.read(_loop.alpha, _eye);
    _eye.y += _eyeOffset;

    final cosPitch = math.cos(_pitch);
    _target
      ..setFrom(_eye)
      ..x += -math.sin(_yaw) * cosPitch
      ..y += math.sin(_pitch)
      ..z += -math.cos(_yaw) * cosPitch;

    _camera
      ..setPositionFrom(_eye)
      ..lookAt(_target);
  }
}

class _SceneSurface extends StatelessWidget {
  const _SceneSurface({
    required this.renderer,
    required this.scene,
    required this.view,
    required this.onBeforeFrame,
  });

  final Renderer renderer;
  final Scene scene;
  final RenderView view;
  final VoidCallback onBeforeFrame;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        onBeforeFrame();
        final frame = renderer.render(
          width: (constraints.maxWidth * dpr).round().clamp(1, 8192),
          height: (constraints.maxHeight * dpr).round().clamp(1, 8192),
          scene: scene,
          views: <RenderView>[view],
        );
        return CustomPaint(
          painter: _ImagePainter(frame.image),
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
      },
    );
  }
}

class _ImagePainter extends CustomPainter {
  const _ImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0.0, 0.0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) => true;
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.captured,
    required this.fps,
    required this.steps,
    required this.dropped,
    required this.position,
    required this.grounded,
  });

  final bool captured;
  final double fps;
  final int steps;
  final int dropped;
  final Vector3 position;
  final bool grounded;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // The crosshair. Nothing shoots yet; it is here because without it the
        // sensitivity is impossible to judge.
        const Center(
          child: SizedBox(
            width: 5.0,
            height: 5.0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white70,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        Positioned(
          left: 12.0,
          top: 12.0,
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.0,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('fps ${fps.toStringAsFixed(0)}   '
                    'steps this frame $steps   dropped $dropped'),
                Text('x ${position.x.toStringAsFixed(1)}  '
                    'y ${position.y.toStringAsFixed(1)}  '
                    'z ${position.z.toStringAsFixed(1)}  '
                    '${grounded ? 'grounded' : 'airborne'}'),
              ],
            ),
          ),
        ),
        if (!captured)
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'Click to look around  ·  WASD to move  ·  Space to jump  ·  '
                'Shift to sprint  ·  Esc to release the pointer',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
      ],
    );
  }
}
