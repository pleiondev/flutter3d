/// The same lesson document a step panel authors, played back through a
/// stereo rig with a Previous and a Next button instead of a keyboard.
///
/// Quoted by `stereo_lesson.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart';
import 'package:vector_math/vector_math.dart';

final class StereoLessonDemo extends ShowcaseDemo {
  final StereoRig _rig = StereoRig();
  late Scene _scene;
  late MeshNode _detail;

  // #region steps
  late final LessonPlayer _player = LessonPlayer(<EntityDef>[
    EntityDef(
      type: 'edu_step',
      position: Vector3(0, 0, 0),
      properties: const <String, Object?>{
        'hidden': <String>['detail'],
      },
    ),
    EntityDef(
      type: 'edu_step',
      position: Vector3(0.5, 0, 0),
      properties: const <String, Object?>{
        'visible': <String>['detail'],
      },
    ),
  ]);
  // #endregion steps

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
    _detail = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 12).build()),
      f3d.Material(name: 'detail', baseColor: Vector4(0.9, 0.9, 0.2, 1.0)),
      name: 'detail',
    )..setPosition(0.4, 0, -2);
    _scene = Scene()
      ..add(_rig.stage)
      ..add(ball)
      ..add(_detail)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
    return _scene;
  }

  // #region view
  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      LessonStereoView(
        renderer: context.renderer,
        scene: _scene,
        rig: _rig,
        player: _player,
        nodes: <String, SceneNode>{'detail': _detail},
      );
  // #endregion view

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region apply
    // The first step hides the detail node; stepping forward shows it.
    _player.applyCurrent(_rig, nodes: <String, SceneNode>{'detail': _detail});
    final hiddenAtStart = !_detail.visible;
    _player.next();
    _player.applyCurrent(_rig, nodes: <String, SceneNode>{'detail': _detail});
    final shownAtStepTwo = _detail.visible;
    // #endregion apply
    if (!hiddenAtStart || !shownAtStepTwo) {
      throw StateError(
        'the detail node should be hidden on the first step '
        'and shown on the second',
      );
    }
  }
}
