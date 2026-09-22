/// `LightType.area`: a rectangle with extent, so a wall reads as lit by a
/// window rather than by a bright dot painted behind one.
///
/// Quoted by `area_lights.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AreaLightsDemo extends ShowcaseDemo {
  double width = 2.5;
  double height = 1.5;

  late final LightNode _window;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.5
      ..yaw = 0.6
      ..pitch = 0.1;
  }

  @override
  Scene build(DemoContext context) {
    // #region window
    _window = LightNode(name: 'window', type: LightType.area, intensity: 8.0)
      ..width = width
      ..height = height
      ..setPosition(0.0, 0.5, 2.0);
    _window.lookAt(Vector3(0.0, 0.0, 0.0));
    // #endregion window

    // #region room
    final Material wallMaterial = Material(
      name: 'wall',
      baseColor: Vector4(0.85, 0.83, 0.78, 1.0),
      roughness: 0.9,
      doubleSided: true,
    );
    final MeshNode backWall = MeshNode(
      DeviceMesh.upload(
        context.device,
        const PlaneShape(width: 6, depth: 4).build(),
      ),
      wallMaterial,
      name: 'back wall',
    )..setPosition(0.0, 0.0, -1.5);
    final MeshNode floor = MeshNode(
      DeviceMesh.upload(
        context.device,
        const PlaneShape(width: 6, depth: 5).build(),
      ),
      wallMaterial,
      name: 'floor',
    )..setPosition(0.0, -1.8, 0.5);
    // #endregion room

    return Scene()
      ..add(backWall)
      ..add(floor)
      ..add(_window);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _window
      ..width = width
      ..height = height;
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Width',
      min: 0.5,
      max: 4,
      value: () => width,
      onChanged: (double v) => width = v,
    ),
    SliderControl(
      'Height',
      min: 0.5,
      max: 3,
      value: () => height,
      onChanged: (double v) => height = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_window.type != LightType.area) {
      throw StateError('the window is not an area light');
    }
    if (_window.width != width || _window.height != height) {
      throw StateError('the panel size did not track the sliders');
    }
    final Vector3 halfWidth = _window.readHalfWidth();
    final Vector3 halfHeight = _window.readHalfHeight();
    if (halfWidth.length2 == 0.0 || halfHeight.length2 == 0.0) {
      throw StateError('the panel has no extent to shade against');
    }
    if (frame.drawCalls < 2) {
      throw StateError('the room was not drawn');
    }
    // #endregion check
  }
}
