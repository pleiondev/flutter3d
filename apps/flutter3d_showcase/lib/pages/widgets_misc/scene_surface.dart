/// The widget every viewport in this app is built from: renders a scene
/// once a frame and hands the result to Flutter through `presentFrame`, and
/// the screen an application shows when a renderer never opened at all.
///
/// Quoted by `scene_surface.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class SceneSurfaceDemo extends ShowcaseDemo {
  late Scene _scene;

  // #region scene
  @override
  Scene build(DemoContext context) {
    final material = f3d.Material(
      name: 'ball',
      baseColor: Vector4(0.6, 0.7, 0.9, 1.0),
    );
    final ball = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 24).build()),
      material,
    );
    _scene = Scene()
      ..add(ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
    return _scene;
  }
  // #endregion scene

  // #region surface
  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      SceneSurface(
        renderer: context.renderer,
        scene: _scene,
        view: context.view,
        settings: () => const RenderSettings(),
        onBeforeFrame: () {},
        presentFrame: presentFrame,
      );
  // #endregion surface

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // #region failure
    // What an application shows instead, when the renderer never opened.
    final failure = DidNotStart(
      StateError('no shader bundle for this build'),
      explaining: 'run tool/build_shaders.sh first',
    );
    // #endregion failure
    if (failure.explaining != 'run tool/build_shaders.sh first') {
      throw StateError('the explanation should be carried through as given');
    }
  }
}
