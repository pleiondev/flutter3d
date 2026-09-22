/// The numbers a folded cardboard holder and a moulded one differ by, turned
/// into an off-centre frustum per eye — wider away from the nose than
/// towards it, which is what a lens actually looks through.
///
/// Quoted by `viewer_profiles.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart';
import 'package:vector_math/vector_math.dart';

final class ViewerProfilesDemo extends ShowcaseDemo {
  bool useV1 = false;

  final StereoRig _rig = StereoRig();
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
    _scene = Scene()
      ..add(_rig.stage)
      ..add(ball)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
    return _scene;
  }

  // #region viewer
  StereoViewer get _viewer =>
      useV1 ? StereoViewer.cardboardV1 : StereoViewer.cardboardV2;
  static const _screen = StereoScreen(width: 0.13, height: 0.07);
  // #endregion viewer

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    // #region apply
    _rig.applyViewer(_viewer, _screen);
    // #endregion apply
    return StereoSurface(
      renderer: context.renderer,
      scene: _scene,
      rig: _rig,
      settings: () => const RenderSettings().forStereo(),
      onBeforeFrame: () {},
      viewer: _viewer,
      screen: _screen,
    );
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Cardboard v1 (narrower)',
      value: () => useV1,
      onChanged: (bool v) => useV1 = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region compare
    // V1's lenses show less of the world than v2's wider window.
    final v1 = StereoViewer.cardboardV1.projectionFor(Eye.left, _screen);
    final v2 = StereoViewer.cardboardV2.projectionFor(Eye.left, _screen);
    final v1Width = v1.tanRight - v1.tanLeft;
    final v2Width = v2.tanRight - v2.tanLeft;
    // #endregion compare
    if (v1Width >= v2Width) {
      throw StateError(
        'the older, narrower viewer should show less of the '
        'world than the newer one, at the same screen',
      );
    }
  }
}
