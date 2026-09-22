/// One `RenderView` cropped to a rectangle, and two combined in one frame.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class MultiViewDemo extends ShowcaseDemo {
  bool showLeft = true;

  late final Scene _scene;
  FrameResult? _combined;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.0
      ..pitch = 0.15
      ..yaw = 0.0;
  }

  @override
  Scene build(DemoContext context) {
    // #region layers
    final MeshNode leftCube =
        MeshNode(
            DeviceMesh.upload(
              context.device,
              CuboidShape(size: Vector3.all(1.0)).build(),
            ),
            Material(name: 'left', baseColor: Vector4(0.2, 0.55, 0.95, 1.0)),
            name: 'left cube',
          )
          ..setPosition(-1.4, 0.0, 0.0)
          ..layerMask = 1;
    final MeshNode rightCube =
        MeshNode(
            DeviceMesh.upload(
              context.device,
              CuboidShape(size: Vector3.all(1.0)).build(),
            ),
            Material(name: 'right', baseColor: Vector4(0.95, 0.42, 0.2, 1.0)),
            name: 'right cube',
          )
          ..setPosition(1.4, 0.0, 0.0)
          ..layerMask = 2;
    // #endregion layers

    _scene = Scene()
      ..ambientColor = Vector3(0.45, 0.5, 0.6)
      ..ambientIntensity = 0.16
      ..add(leftCube)
      ..add(rightCube)
      ..add(
        LightNode(name: 'key', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.7, -0.5)),
      );

    // #region rect
    context.view
      ..viewportFraction = const ViewportRect(0.0, 0.0, 0.5, 1.0)
      ..layerMask = showLeft ? 1 : 2;
    // #endregion rect
    return _scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region split
    final RenderView left = RenderView(
      camera: context.camera,
      viewportFraction: const ViewportRect(0.0, 0.0, 0.5, 1.0),
      layerMask: 1,
    );
    final RenderView right = RenderView(
      camera: context.camera,
      viewportFraction: const ViewportRect(0.5, 0.0, 0.5, 1.0),
      layerMask: 2,
    );
    _combined = context.renderer.render(
      width: 320,
      height: 180,
      scene: _scene,
      views: <RenderView>[left, right],
      settings: const RenderSettings(),
    );
    // #endregion split
    context.view.layerMask = showLeft ? 1 : 2;
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    // #region controls
    ToggleControl(
      'Show the left layer',
      value: () => showLeft,
      onChanged: (bool value) => showLeft = value,
    ),
    // #endregion controls
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final FrameResult? combined = _combined;
    if (combined == null || combined.drawCalls <= frame.drawCalls) {
      throw StateError('two views in one frame did not draw more than one');
    }
    // #endregion check
  }
}
