/// `ActorComponent` and `ActorSystemComponent` bridging a `flutter3d_sim`
/// `Actor`'s own body onto a Flame position and a flutter3d mesh.
///
/// Quoted by `flame_ecs_bridge.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
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

  @override
  Scene build(DemoContext context) {
    final (String report, double actorX, double flameX) = _run(context.device);
    _report = report;
    _actorX = actorX;
    _flameX = flameX;

    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      Material(name: 'goblin', baseColor: Vector4(0.5, 0.7, 0.3, 1.0)),
    );

    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
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

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

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
