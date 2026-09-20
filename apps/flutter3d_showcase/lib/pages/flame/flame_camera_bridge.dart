/// `CameraSyncController` reconciling an orthographic flutter3d `CameraNode`
/// and a Flame `Viewfinder`, in both `SyncDirection`s.
///
/// Quoted by `flame_camera_bridge.md` and shown whole in the Source tab.
library;

import 'package:flame/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class FlameCameraBridgeDemo extends ShowcaseDemo {
  late final String _report;
  late final double _viewfinderX;
  late final double _viewfinderZoom;
  late final double _cameraX;
  late final double _orthoHeight;

  @override
  Scene build(DemoContext context) {
    final (
      String report,
      double viewfinderX,
      double viewfinderZoom,
      double cameraX,
      double orthoHeight,
    ) = _run();
    _report = report;
    _viewfinderX = viewfinderX;
    _viewfinderZoom = viewfinderZoom;
    _cameraX = cameraX;
    _orthoHeight = orthoHeight;

    final node = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(0.6, 0.6, 0.6)).build(),
      ),
      Material(name: 'marker', baseColor: Vector4(0.4, 0.7, 0.6, 1.0)),
    );

    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
  }

  static (String, double, double, double, double) _run() {
    // #region cameras
    final camera = CameraNode(
      name: 'bridged-camera',
      projection: const OrthographicProjection(height: 4.0),
    );
    final viewfinder = Viewfinder();
    final plane = BridgePlane.ground();
    // #endregion cameras

    // #region scene-to-flame
    // The flutter3d camera is authoritative; `advance` copies its position
    // and its orthographic height onto the Flame viewfinder.
    final sceneToFlame = CameraSyncController(
      camera: camera,
      viewfinder: viewfinder,
      plane: plane,
    );
    camera.setPosition(3.0, 0.0, 2.0);
    sceneToFlame.advance(1 / 60);
    final double viewfinderX = viewfinder.position.x;
    final double viewfinderZoom = viewfinder.zoom;
    // #endregion scene-to-flame

    // #region flame-to-scene
    // The Flame viewfinder is authoritative instead; `advance` copies its
    // position and its zoom onto the flutter3d camera's projection.
    final flameToScene = CameraSyncController(
      camera: camera,
      viewfinder: viewfinder,
      plane: plane,
      direction: SyncDirection.flameToScene,
    );
    viewfinder.position = Vector2(1.0, -1.0);
    viewfinder.zoom = 0.5;
    flameToScene.advance(1 / 60);
    final double cameraX = camera.readPosition().x;
    final double orthoHeight =
        (camera.projection as OrthographicProjection).height;
    // #endregion flame-to-scene

    return (
      'flutter3d led: Flame position=($viewfinderX, _), zoom=$viewfinderZoom; '
          'Flame led: flutter3d x=$cameraX, height=$orthoHeight',
      viewfinderX,
      viewfinderZoom,
      cameraX,
      orthoHeight,
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
      throw StateError('the marker was not drawn');
    }
    // Compared as numbers, not read back out of `_report`: see
    // `sim_audio_xr/actors.dart` for why.
    if (_viewfinderX != 3.0) {
      throw StateError(
        'the viewfinder should have followed the camera to x=3, got '
        '$_viewfinderX',
      );
    }
    if (_viewfinderZoom != 0.25) {
      throw StateError(
        'zoom = 1 / height should read 0.25 for a height-4 lens, got '
        '$_viewfinderZoom',
      );
    }
    if (_cameraX != 1.0) {
      throw StateError(
        'the flutter3d camera should have followed the viewfinder to x=1, '
        'got $_cameraX',
      );
    }
    if (_orthoHeight != 2.0) {
      throw StateError(
        'height = 1 / zoom should read 2.0 for zoom 0.5, got $_orthoHeight',
      );
    }
  }
}
