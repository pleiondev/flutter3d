/// `RenderSettings.wireframe`: triangles drawn as lines, and what a device
/// that cannot do that reports instead.
///
/// Quoted by `wireframe.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class WireframeDemo extends ShowcaseDemo {
  bool wireframe = true;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.5
      ..yaw = 0.5
      ..pitch = 0.25;
  }

  @override
  Scene build(DemoContext context) {
    // #region mesh
    final MeshNode knot = MeshNode(
      DeviceMesh.upload(
        context.device,
        const TorusShape(segments: 32, tubeSegments: 16).build(),
      ),
      Material(name: 'knot', baseColor: Vector4(0.3, 0.65, 0.85, 1.0)),
      name: 'knot',
    );
    return Scene()
      ..add(knot)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.7, -0.6)),
      );
    // #endregion mesh
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    wireframe: wireframe,
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Wireframe',
      value: () => wireframe,
      onChanged: (bool v) => wireframe = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // The software rasteriser has no polygon-mode line primitive, so this
    // page's own claim on this device is the refusal itself: asking for
    // wireframe here still draws the model solid, and the frame says why.
    if (wireframe && !frame.wireframeDeclined) {
      throw StateError('this device drew wireframe; the claim below is stale');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the knot was not drawn');
    }
    // #endregion check
  }
}
