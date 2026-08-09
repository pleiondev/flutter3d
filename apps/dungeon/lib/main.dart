import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

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

  /// The same room as the scene, in the shape the simulation understands.
  ///
  /// Built alongside the meshes rather than derived from them: a renderer mesh
  /// is triangles and a collider is a brush, and keeping one authored list that
  /// produces both is what stops the two from drifting apart. When the level
  /// format arrives it will be that list.
  final CollisionWorld _collision = CollisionWorld();
  late final CharacterController _body;

  final Scene _scene = Scene();
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
    _buildRoom();

    _body = CharacterController(
      world: _collision,
      position: Vector3(0.0, 0.95, 6.0),
    );
    _smoothedPosition.jumpTo(_body.position);

    try {
      _renderer = Renderer.create(
        fallbackAlbedo: SolidColorTexture.white.upload(),
        fallbackNormal: SolidColorTexture.flatNormal.upload(),
      );
    } catch (error) {
      _initError = error;
    }

    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _devices.dispose();
    super.dispose();
  }

  /// A stand-in for a level: a floor and something to walk around.
  ///
  /// The numbers are chosen to look like a dungeon rather than to be neutral.
  /// A default white material under a bright directional light clips to flat
  /// white everywhere, which reads as "the renderer is broken" even when it is
  /// working perfectly — dark stone and a single torch show the shading.
  void _buildRoom() {
    final stone = engine.Material(
      baseColor: Vector4(0.38, 0.36, 0.32, 1.0),
      roughness: 0.85,
    );

    final floorSize = Vector3(40.0, 0.5, 40.0);
    final floorAt = Vector3(0.0, -0.25, 0.0);
    _scene.add(
      MeshNode(GpuMesh.upload(CuboidShape(size: floorSize).build()), stone,
          name: 'floor')
        ..setPositionFrom(floorAt),
    );
    _collision.addBox(floorAt, floorSize);

    // One mesh, eight nodes: the geometry is uploaded once and instanced by
    // reference, which is all the instancing flutter_gpu offers.
    final pillarSize = Vector3(1.5, 4.0, 1.5);
    final pillarMesh = GpuMesh.upload(CuboidShape(size: pillarSize).build());
    for (var i = 0; i < 8; i++) {
      final angle = i / 8.0 * 2.0 * math.pi;
      final at = Vector3(math.cos(angle) * 9.0, 2.0, math.sin(angle) * 9.0);
      _scene.add(
        MeshNode(pillarMesh, stone, name: 'pillar$i')..setPositionFrom(at),
      );
      _collision.addBox(at, pillarSize);
    }

    // Something to climb, so the step-up and the jump are reachable without a
    // level: a short flight of stairs and the ledge they lead to.
    final stepMesh = GpuMesh.upload(
      CuboidShape(size: Vector3(4.0, 0.3, 1.2)).build(),
    );
    for (var i = 0; i < 5; i++) {
      final at = Vector3(0.0, 0.15 + i * 0.3, -3.0 - i * 1.2);
      _scene.add(
        MeshNode(stepMesh, stone, name: 'step$i')..setPositionFrom(at),
      );
      // The collider is a solid block down to the floor, not a floating slab:
      // a stair with a gap under it is a stair the player can fall into.
      _collision.addBox(
        Vector3(at.x, (0.3 + i * 0.3) / 2.0, at.z),
        Vector3(4.0, 0.3 + i * 0.3, 1.2),
      );
    }

    // A weak, cold directional light standing in for whatever daylight reaches
    // this far down. It aims along the node's local -Z, the same forward axis a
    // camera uses, so it is pointed with lookAt rather than by setting a vector.
    _scene.add(
      LightNode(
        color: Vector3(0.55, 0.62, 0.80),
        intensity: 0.8,
        name: 'sky',
      )
        ..setPosition(6.0, 12.0, 5.0)
        ..lookAt(Vector3.zero()),
    );

    // The torch does the actual lighting, and its falloff is what makes the
    // room feel enclosed.
    _scene.add(
      LightNode(
        type: LightType.point,
        color: Vector3(1.0, 0.72, 0.38),
        intensity: 20.0,
        range: 22.0,
        name: 'torch',
      )..setPosition(0.0, 3.0, 0.0),
    );
  }

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

    if (_input.pressed(GameAction.jump)) _body.requestJump();

    _body.step(
      dt,
      wishDirection: _wish,
      sprint: _input.held(GameAction.sprint),
    );

    _collision.update();
    _collision.clearKinematicDeltas();

    _smoothedPosition.push(_body.position);
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
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
                scene: _scene,
                view: _view,
                onBeforeFrame: _placeCamera,
              ),
              _Hud(
                captured: _devices.isCaptured,
                fps: _fps,
                steps: _steps,
                dropped: _loop.clock.droppedSteps,
                position: _body.position,
                grounded: _body.isGrounded,
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
