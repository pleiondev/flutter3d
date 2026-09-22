/// Two cameras under a head, under a stage the application moves: a stereo
/// pair drawn side by side into one frame.
///
/// Quoted by `stereo_rig.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart';
import 'package:vector_math/vector_math.dart';

final class StereoRigDemo extends ShowcaseDemo {
  // #region rig
  final StereoRig _rig = StereoRig();
  // #endregion rig

  late Scene _scene;

  @override
  Scene build(DemoContext context) {
    final material = f3d.Material(
      name: 'ball',
      baseColor: Vector4(0.8, 0.5, 0.3, 1.0),
    );
    final ball = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 24).build()),
      material,
    )..setPosition(0, 0, -2);
    _rig.stage.setPosition(0, 0, 0);
    _scene = Scene()
      ..add(_rig.stage)
      ..add(ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
    return _scene;
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    // #region surface
    return StereoSurface(
      renderer: context.renderer,
      scene: _scene,
      rig: _rig,
      settings: () => const RenderSettings().forStereo(),
      onBeforeFrame: () {},
    );
    // #endregion surface
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region views
    // Two views, side by side, half the frame's width apart.
    if (_rig.views.length != 2) {
      throw StateError('a stereo rig draws exactly two views');
    }
    final left = _rig.views[0].viewportFraction;
    final right = _rig.views[1].viewportFraction;
    // #endregion views
    if (left.x != 0.0 || right.x != 0.5 || left.width != 0.5) {
      throw StateError(
        'the left view should fill the left half of the '
        'frame and the right view the right half',
      );
    }
  }
}
