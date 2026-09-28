/// A [CameraSyncComponent] advances its [CameraSyncController] once per
/// Flame update.
library;

import 'package:flame/camera.dart' show Viewfinder;
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Plane;

void main() {
  test('an update carries the authoritative side across', () {
    final camera = CameraNode()..setPosition(3.0, 0.0, 4.0);
    final viewfinder = Viewfinder();
    final component = CameraSyncComponent(
      controller: CameraSyncController(
        camera: camera,
        viewfinder: viewfinder,
        plane: BridgePlane.ground(),
      ),
      priority: 10,
    );

    component.update(1 / 60);

    expect(viewfinder.position, Vector2(3.0, 4.0));
    expect(component.priority, 10);
  });
}
