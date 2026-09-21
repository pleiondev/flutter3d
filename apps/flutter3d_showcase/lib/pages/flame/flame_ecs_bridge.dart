/// `ActorComponent` and `ActorSystemComponent` bridging a `flutter3d_sim`
/// `Actor`'s own body onto a Flame position and a flutter3d mesh.
///
/// Quoted by `flame_ecs_bridge.md` and shown whole in the Source tab.
library;

import 'package:flame/components.dart' show Component;
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/flame_layer.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

// #region brain
/// Walks straight towards +x, every step, for as long as it lives.
final class _WalkBrain extends Brain {
  @override
  void act(Mind it) => it.steer(Vector3(1.0, 0.0, 0.0));
}
// #endregion brain

final class FlameEcsBridgeDemo extends ShowcaseDemo {
  late final String _report;
  late final double _actorX;
  late final double _flameX;

  late final DemoContext _context;
  late final Scene _scene;
  late final TransparentFlameGame _game;
  late final Widget _body = flameOrbit(
    _context,
    Flutter3dFlameWidget(
      game: _game,
      camera: _context.camera,
      existing: (device: _context.device, renderer: _context.renderer),
      buildScene: (GraphicsDevice device) => _scene,
    ),
  );

  static const List<Color> _colors = <Color>[
    Color(0xFF80CC4D),
    Color(0xFF80B3E6),
    Color(0xFFE6994D),
  ];

  /// Where the walkers wrap round, on x.
  static const double _edge = 4.5;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 10.0
      ..pitch = 0.8
      ..yaw = 0.4;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _context = context;
    final (String report, double actorX, double flameX) = _run(context.device);
    _report = report;
    _actorX = actorX;
    _flameX = flameX;

    _scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(12.0, 0.1, 12.0)).build(),
          ),
          Material(name: 'floor', baseColor: Vector4(0.36, 0.4, 0.38, 1.0)),
          name: 'floor',
        )..setPosition(0.0, -0.05, 0.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );

    // #region live
    // Three goblins in one shared system, each with a bridge component that
    // copies its body onto its node and, through the plane, onto a Flame
    // position. One `ActorSystemComponent` steps the system, once a frame; the
    // map's dots are those Flame positions.
    final CollisionWorld world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
    final ActorSystem system = ActorSystem(world: world, random: GameRandom(1));
    final FlameMinimap map = FlameMinimap();
    final List<Component> bridges = <Component>[];
    final List<CharacterController> bodies = <CharacterController>[];
    for (var i = 0; i < 3; i++) {
      final CharacterController body = CharacterController(
        world: world,
        position: Vector3(-_edge + i * 1.5, 1.0, (i - 1) * 2.0),
      );
      bodies.add(body);
      final Actor goblin = system.spawn(
        body: body,
        brain: _WalkBrain(),
        name: 'goblin $i',
      );
      final MeshNode node = MeshNode(
        DeviceMesh.upload(
          context.device,
          SphereShape(segments: 24, radius: 0.4).build(),
        ),
        Material(
          name: 'goblin $i',
          baseColor: Vector4(
            _colors[i].r,
            _colors[i].g,
            _colors[i].b,
            1.0,
          ),
        ),
        name: 'goblin $i',
      );
      _scene.add(node);
      bridges.add(
        ActorComponent(
          actor: goblin,
          node: node,
          scene: _scene,
          plane: BridgePlane.ground(),
        )..add(flameDot(_colors[i])),
      );
    }
    map.world.addAll(bridges);
    _game = TransparentFlameGame()
      ..add(ActorSystemComponent(system: system, focus: Vector3.zero))
      // After the system, so the bodies have moved by the time they are read.
      ..add(_Wrap(bodies))
      ..add(map);
    // #endregion live
    _game
      ..add(flameCaption('the dots: Flame positions read off the actors'))
      ..add(flameCaption(_report, at: Vector2(16.0, 40.0)));
    return _scene;
  }

  @override
  void update(DemoContext context, double dt) {
    context.orbit.syncProjectionDepth(context.camera);
  }

  static (String, double, double) _run(GraphicsDevice device) {
    // #region system
    final world = CollisionWorld();
    world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
    final system = ActorSystem(world: world, random: GameRandom(1));
    // #endregion system

    // #region actor
    final controller = CharacterController(
      world: world,
      position: Vector3(0.0, 3.0, 0.0),
    );
    final goblin = system.spawn(
      body: controller,
      brain: _WalkBrain(),
      name: 'goblin',
    );
    // #endregion actor

    // #region bridge
    final scene = Scene();
    final node = MeshNode(
      DeviceMesh.upload(device, SphereShape(segments: 16).build()),
      Material(name: 'bridged-goblin', baseColor: Vector4(0.5, 0.7, 0.3, 1.0)),
    );
    scene.add(node);
    final actorComponent = ActorComponent(
      actor: goblin,
      node: node,
      scene: scene,
      plane: BridgePlane.ground(),
    );
    final systemComponent = ActorSystemComponent(
      system: system,
      focus: Vector3.zero,
    );
    // #endregion bridge

    // #region step
    // The system decides where the goblin's body goes; the actor component
    // copies that body's position onto the node, then the plane it shares
    // carries it onto the Flame side — the same seam `Object3dComponent`
    // gives every other bridged transform.
    for (var i = 0; i < 90; i++) {
      systemComponent.update(1 / 60);
      actorComponent.update(1 / 60);
    }
    // #endregion step

    final double actorX = goblin.body!.position.x;
    final double flameX = actorComponent.position.x;
    return (
      'the goblin walked to x=$actorX; the bridged Flame position reads '
          'x=$flameX',
      actorX,
      flameX,
    );
  }

  /// The Flame game the page runs, for a test that steps it without a window.
  @visibleForTesting
  TransparentFlameGame get game => _game;

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      _body;

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the goblin marker was not drawn');
    }
    // Compared as numbers, not read back out of `_report`: see
    // `sim_audio_xr/actors.dart` for why a formatted string is the wrong
    // thing to assert a double against.
    if (_actorX < 0.5) {
      throw StateError(
        'the goblin should have walked forward under the system, got '
        'x=$_actorX',
      );
    }
    if (_flameX != _actorX) {
      throw StateError(
        'the bridged Flame position should track the actor body exactly on '
        'a ground plane, got flame x=$_flameX vs body x=$_actorX',
      );
    }
  }
}

/// Sends a goblin that has walked off the far edge back to the near one.
final class _Wrap extends Component {
  _Wrap(this._bodies);

  final List<CharacterController> _bodies;

  @override
  void update(double dt) {
    super.update(dt);
    for (final CharacterController body in _bodies) {
      if (body.position.x > FlameEcsBridgeDemo._edge) {
        body.position.x = -FlameEcsBridgeDemo._edge;
      }
    }
  }
}
