/// `Object3dComponent` keeping a Flame `PositionComponent` and a flutter3d
/// `SceneNode` at the same place, in both `SyncDirection`s.
///
/// Quoted by `flame_transform_bridge.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/flame_layer.dart';

final class FlameTransformBridgeDemo extends ShowcaseDemo {
  late final double _flamePositionX;
  late final double _flamePositionY;
  late final double _scenePositionX;
  late final double _scenePositionZ;

  late final DemoContext _context;
  late final Scene _scene;
  late final MeshNode _leader;
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
  double _clock = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.0
      ..pitch = 0.7
      ..yaw = 0.5;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
  }

  MeshNode _cube(DemoContext context, String name, Vector4 color) => MeshNode(
    DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.5, 0.5, 0.5)).build(),
    ),
    Material(name: name, baseColor: color),
    name: name,
  )..setPosition(0.0, 0.25, 0.0);

  @override
  Scene build(DemoContext context) {
    _context = context;
    final (double flameX, double flameY, double sceneX, double sceneZ) = _run(
      context.device,
    );
    _flamePositionX = flameX;
    _flamePositionY = flameY;
    _scenePositionX = sceneX;
    _scenePositionZ = sceneZ;

    _leader = _cube(context, 'scene leads', Vector4(0.5, 0.7, 0.9, 1.0));
    final MeshNode follower = _cube(
      context,
      'flame leads',
      Vector4(0.9, 0.6, 0.3, 1.0),
    );
    _scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(8.0, 0.1, 8.0)).build(),
          ),
          Material(name: 'floor', baseColor: Vector4(0.36, 0.4, 0.38, 1.0)),
          name: 'floor',
        )..setPosition(0.0, -0.05, 0.0),
      )
      ..add(_leader)
      ..add(follower)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );

    // #region live
    // The same two components as above, now in a running game: each frame
    // Flame updates them and each copies one way. The map in the corner is
    // Flame's own view of the ground plane, a metre to 24 pixels.
    final BridgePlane plane = BridgePlane.ground();
    final Object3dComponent reads = Object3dComponent(
      node: _leader,
      scene: _scene,
      plane: plane,
    )..add(flameDot(const Color(0xFF80B3E6)));
    final Object3dComponent writes = Object3dComponent(
      node: follower,
      scene: _scene,
      plane: plane,
      direction: SyncDirection.flameToScene,
    )..add(flameDot(const Color(0xFFE6994D)));
    final FlameMinimap map = FlameMinimap()
      ..world.addAll(<Component>[reads, writes]);
    _game = TransparentFlameGame();
    _game
      // Before `writes`, so the position is set before it is copied.
      ..add(_Drift(writes))
      ..add(map)
      ..add(flameCaption('blue: the node moves, Flame reads it'))
      ..add(
        flameCaption(
          'orange: Flame moves, the node reads it',
          at: Vector2(16.0, 40.0),
        ),
      );
    // #endregion live
    return _scene;
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    context.orbit.syncProjectionDepth(context.camera);
    // The flutter3d side leads: it moves its own node round in a circle.
    _leader.setPosition(
      2.6 * math.cos(_clock * 0.8),
      0.25,
      2.6 * math.sin(_clock * 0.8),
    );
  }

  static (double, double, double, double) _run(GraphicsDevice device) {
    final scene = Scene();
    // #region shared-plane
    // One ground plane, shared by both components below, so a Flame (x, y)
    // and a flutter3d (x, height, y) mean the same point everywhere in this
    // scene.
    final plane = BridgePlane.ground();
    // #endregion shared-plane

    // #region scene-authoritative
    // The flutter3d side moves; `SyncDirection.sceneToFlame` is the default,
    // so `Object3dComponent` reads the node and writes the Flame component.
    final node = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(0.4, 0.4, 0.4)).build(),
      ),
      Material(
        name: 'scene-authoritative',
        baseColor: Vector4(0.5, 0.7, 0.9, 1.0),
      ),
    );
    scene.add(node);
    final sceneToFlame = Object3dComponent(
      node: node,
      scene: scene,
      plane: plane,
    );
    node.setPosition(3.0, 0.0, 2.0);
    sceneToFlame.update(1 / 60);
    final Vector2 flamePosition = sceneToFlame.position;
    // #endregion scene-authoritative

    // #region flame-authoritative
    // The Flame side moves instead; `SyncDirection.flameToScene` makes
    // `Object3dComponent` read the Flame component and write the node.
    final otherNode = MeshNode(
      DeviceMesh.upload(
        device,
        CuboidShape(size: Vector3(0.4, 0.4, 0.4)).build(),
      ),
      Material(
        name: 'flame-authoritative',
        baseColor: Vector4(0.9, 0.6, 0.3, 1.0),
      ),
    );
    scene.add(otherNode);
    final flameToScene = Object3dComponent(
      node: otherNode,
      scene: scene,
      plane: plane,
      direction: SyncDirection.flameToScene,
    );
    flameToScene.position = Vector2(4.0, -1.0);
    flameToScene.update(1 / 60);
    final Vector3 scenePosition = otherNode.readPosition();
    // #endregion flame-authoritative

    return (flamePosition.x, flamePosition.y, scenePosition.x, scenePosition.z);
  }

  /// The Flame game the page runs, for a test that steps it without a window.
  @visibleForTesting
  TransparentFlameGame get game => _game;

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) => _body;

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the marker was not drawn');
    }
    // Compared as numbers, not read back out of a formatted report: a whole
    // number double loses its trailing `.0` when a web backend formats it,
    // and this repository's own showcase pages were bitten by exactly that
    // once already.
    if (_flamePositionX != 3.0 || _flamePositionY != 2.0) {
      throw StateError(
        'moving the node to (3, _, 2) on a ground plane should read back as '
        'Flame position (3, 2), got ($_flamePositionX, $_flamePositionY)',
      );
    }
    if (_scenePositionX != 4.0 || _scenePositionZ != -1.0) {
      throw StateError(
        'moving the Flame position to (4, -1) on a ground plane should read '
        'back as scene x=4, z=-1, got x=$_scenePositionX, z=$_scenePositionZ',
      );
    }
  }
}

/// Moves a bridged component along a figure of eight, the way a Flame game
/// moves anything of its own: by setting its position.
final class _Drift extends Component {
  _Drift(this._target);

  final Object3dComponent _target;
  double _t = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _target.position = Vector2(
      2.6 * math.sin(_t * 0.8),
      1.6 * math.sin(_t * 1.6),
    );
  }
}
