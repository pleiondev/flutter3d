/// Where the head is, fed to a stereo rig every frame.
///
/// **`SensorHeadTracker`, the real implementation, reads a phone's rotation
/// sensor through a platform channel** — nothing this test environment or a
/// desktop browser has. This page implements the same `HeadTracker`
/// interface by hand, driven by the pointer instead of a sensor, which is
/// the honest stand-in: the rig on the other end cannot tell the difference,
/// because all either one ever hands it is a `HeadPose`.
///
/// Quoted by `head_tracking.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_stereo/flutter3d_stereo.dart';
import 'package:vector_math/vector_math.dart';

// #region tracker
/// Turns pointer drags into a head pose, the same shape a sensor would.
final class _PointerHeadTracker implements HeadTracker {
  final ValueNotifier<HeadPose> _pose = ValueNotifier<HeadPose>(
    HeadPose.still(),
  );
  double _yaw = 0.0;

  @override
  ValueListenable<HeadPose> get pose => _pose;

  void dragBy(double dx) {
    _yaw -= dx * 0.01;
    _pose.value = HeadPose(
      rotation: Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), _yaw),
      position: Vector3.zero(),
    );
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
// #endregion tracker

final class HeadTrackingDemo extends ShowcaseDemo {
  final _PointerHeadTracker _tracker = _PointerHeadTracker();
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
    // A ring of posts round the viewer, each its own colour, so that turning
    // the head visibly sweeps across something.
    final List<SceneNode> posts = <SceneNode>[
      for (var i = 0; i < 8; i++)
        blockNode(
          context,
          'post $i',
          Vector3(0.5, 1.0 + 0.4 * (i % 3), 0.5),
          Vector4(
            0.5 + 0.45 * math.sin(i * 0.8),
            0.5 + 0.35 * math.sin(i * 1.6 + 1.0),
            0.45 + 0.4 * math.sin(i * 2.4 + 2.0),
            1.0,
          ),
          at: Vector3(
            4.0 * math.sin(i * math.pi / 4),
            (1.0 + 0.4 * (i % 3)) / 2 - 1.6,
            -4.0 * math.cos(i * math.pi / 4),
          ),
        ),
    ];
    _scene = sceneOf(<SceneNode>[
      _rig.stage,
      ball,
      floorNode(context, width: 14.0, depth: 14.0)
        ..setPosition(0.0, -1.65, 0.0),
      ...posts,
    ]);
    return _scene;
  }

  // #region apply
  void _applyHead() => _rig.applyHead(_tracker.pose.value);
  // #endregion apply

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    _applyHead();
    return GestureDetector(
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        _tracker.dragBy(details.delta.dx);
        _applyHead();
      },
      child: StereoSurface(
        renderer: context.renderer,
        scene: _scene,
        rig: _rig,
        settings: () => const RenderSettings().forStereo(),
        onBeforeFrame: _applyHead,
      ),
    );
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region turn
    final before = _rig.gaze();
    _tracker.dragBy(200.0);
    _applyHead();
    final after = _rig.gaze();
    // #endregion turn
    if ((before - after).length < 0.1) {
      throw StateError(
        'dragging should turn the head, and turning the head '
        'should turn where the rig looks',
      );
    }
  }
}
