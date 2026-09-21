/// `Object3dComponent` keeping a Flame `PositionComponent` and a flutter3d
/// `SceneNode` at the same place, in both `SyncDirection`s.
///
/// Quoted by `flame_transform_bridge.md` and shown whole in the Source tab.
library;

import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class FlameTransformBridgeDemo extends ShowcaseDemo {
  late final double _flamePositionX;
  late final double _flamePositionY;
  late final double _scenePositionX;
  late final double _scenePositionZ;

  @override
  Scene build(DemoContext context) {
    final (double flameX, double flameY, double sceneX, double sceneZ) = _run(
      context.device,
    );
    _flamePositionX = flameX;
    _flamePositionY = flameY;
    _scenePositionX = sceneX;
    _scenePositionZ = sceneZ;

    final node = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(0.6, 0.6, 0.6)).build(),
      ),
      Material(name: 'marker', baseColor: Vector4(0.6, 0.4, 0.8, 1.0)),
      name: 'marker',
    );

    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
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

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    final scene = Scene();
    final node = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(0.6, 0.6, 0.6)).build(),
      ),
      Material(name: 'bridged-cube', baseColor: Vector4(0.6, 0.4, 0.8, 1.0)),
    );
    final plane = BridgePlane.ground();
    final bridge = Object3dComponent(
      node: node,
      scene: scene,
      plane: plane,
      direction: SyncDirection.flameToScene,
    );
    final game = TransparentFlameGame()..add(bridge..add(_Drift(bridge)));
    return Flutter3dFlameWidget(
      game: game,
      // Left at its own default transform, this camera sat exactly where
      // the bridged cube does — see `flame_overview.dart` for the same fix.
      camera: CameraNode(name: 'transform-preview')
        ..setPosition(2.5, 2.0, 4.0)
        ..lookAt(Vector3.zero()),
      existing: (device: context.device, renderer: context.renderer),
      buildScene: (GraphicsDevice device) => scene,
    );
  }

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

/// Nudges a bridged component sideways every frame, for the preview only.
final class _Drift extends Component {
  _Drift(this._target);

  final Object3dComponent _target;
  double _t = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _target.position = Vector2(_t % 2.0 - 1.0, 0.0);
  }
}
