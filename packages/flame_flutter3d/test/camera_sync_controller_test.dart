/// A [CameraSyncController] keeps a flutter3d [CameraNode] and a Flame
/// [Viewfinder] describing the same view, on whichever side [SyncDirection]
/// names as authoritative.
library;

import 'package:flame/camera.dart' show Viewfinder;
import 'package:flame_flutter3d/src/camera/camera_sync_controller.dart';
import 'package:flame_flutter3d/src/transform/object3d_component.dart'
    show SyncDirection;
import 'package:flame_flutter3d/src/transform/plane.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Plane;

void main() {
  test('sceneToFlame moves the viewfinder position to the camera, through the '
      'plane', () {
    final camera = CameraNode()..setPosition(3.0, 0.0, 4.0);
    final viewfinder = Viewfinder();
    final controller = CameraSyncController(
      camera: camera,
      viewfinder: viewfinder,
      plane: BridgePlane.ground(),
    );

    controller.advance(1 / 60);

    expect(viewfinder.position, Vector2(3.0, 4.0));
  });

  test('sceneToFlame moves the viewfinder zoom to the orthographic height, '
      'reciprocally', () {
    final camera = CameraNode(
      projection: const OrthographicProjection(height: 4.0),
    );
    final viewfinder = Viewfinder();
    final controller = CameraSyncController(
      camera: camera,
      viewfinder: viewfinder,
      plane: BridgePlane.ground(),
    );

    controller.advance(1 / 60);

    expect(viewfinder.zoom, 0.25);
  });

  test(
    'sceneToFlame leaves the viewfinder zoom alone for a perspective camera',
    () {
      final camera = CameraNode(projection: const PerspectiveProjection());
      final viewfinder = Viewfinder()..zoom = 2.0;
      final controller = CameraSyncController(
        camera: camera,
        viewfinder: viewfinder,
        plane: BridgePlane.ground(),
      );

      controller.advance(1 / 60);

      expect(viewfinder.zoom, 2.0);
    },
  );

  test('flameToScene moves the camera position to the viewfinder, through the '
      'plane', () {
    final camera = CameraNode();
    final viewfinder = Viewfinder()..position = Vector2(5.0, 6.0);
    final controller = CameraSyncController(
      camera: camera,
      viewfinder: viewfinder,
      plane: BridgePlane.ground(height: 1.5),
      direction: SyncDirection.flameToScene,
    );

    controller.advance(1 / 60);

    final read = camera.readPosition();
    expect(read.x, 5.0);
    expect(read.y, 1.5);
    expect(read.z, 6.0);
  });

  test('flameToScene moves the orthographic height to the viewfinder zoom, '
      'reciprocally', () {
    final camera = CameraNode(
      projection: const OrthographicProjection(height: 4.0),
    );
    final viewfinder = Viewfinder()..zoom = 0.5;
    final controller = CameraSyncController(
      camera: camera,
      viewfinder: viewfinder,
      plane: BridgePlane.ground(),
      direction: SyncDirection.flameToScene,
    );

    controller.advance(1 / 60);

    final projection = camera.projection;
    expect(projection, isA<OrthographicProjection>());
    expect((projection as OrthographicProjection).height, 2.0);
  });

  test('flameToScene leaves a perspective projection alone', () {
    const projection = PerspectiveProjection();
    final camera = CameraNode(projection: projection);
    final viewfinder = Viewfinder()..zoom = 2.0;
    final controller = CameraSyncController(
      camera: camera,
      viewfinder: viewfinder,
      plane: BridgePlane.ground(),
      direction: SyncDirection.flameToScene,
    );

    controller.advance(1 / 60);

    expect(camera.projection, same(projection));
  });
}
