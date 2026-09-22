/// Draw order and depth state: which surface is drawn first, whether it writes
/// depth, how it is tested, and whether the back of a triangle is drawn.
///
/// Quoted by `draw_state.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class DrawStateDemo extends ShowcaseDemo {
  int bucket = -1;
  bool panelWritesDepth = false;
  int testChoice = 0;
  bool cullBackFaces = true;

  static const List<String> _tests = <String>['less', 'always'];

  late final Material _panel;
  late final MeshNode _box;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.0
      ..yaw = 0.5
      ..pitch = 0.2;
  }

  @override
  Scene build(DemoContext context) {
    final Quaternion upright = Quaternion.axisAngle(
      Vector3(1.0, 0.0, 0.0),
      math.pi / 2,
    );

    // #region box
    _box = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(1.6, 1.6, 1.6)).build(),
      ),
      Material(name: 'box', baseColor: Vector4(0.25, 0.45, 0.85, 1.0)),
      name: 'box',
    );
    // #endregion box

    // #region panel
    _panel = Material(
      name: 'panel',
      baseColor: Vector4(0.95, 0.55, 0.2, 1.0),
      drawBucket: bucket,
      depthWrite: panelWritesDepth ? null : false,
      depthCompare: testChoice == 0 ? null : CompareFunction.always,
    );
    final MeshNode panel =
        MeshNode(
            DeviceMesh.upload(
              context.device,
              const PlaneShape(width: 5, depth: 3).build(),
            ),
            _panel,
            name: 'panel',
          )
          ..setRotation(upright)
          ..setPosition(0.0, 0.0, 1.8);
    // #endregion panel

    // #region flag
    final MeshNode flag =
        MeshNode(
            DeviceMesh.upload(
              context.device,
              const PlaneShape(width: 1.4, depth: 1.4).build(),
            ),
            Material(name: 'flag', baseColor: Vector4(0.8, 0.15, 0.2, 1.0)),
            name: 'flag',
          )
          ..setRotation(
            Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), -math.pi / 2),
          )
          ..setPosition(-2.9, 0.0, -0.5);
    // #endregion flag

    return Scene()
      ..add(_box)
      ..add(panel)
      ..add(flag)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.3, -0.5, -1.0)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _panel
      ..drawBucket = bucket
      ..depthWrite = panelWritesDepth ? null : false
      ..depthCompare = testChoice == 0 ? null : CompareFunction.always;
    // #endregion live
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region culling
    backfaceCulling: cullBackFaces,
    // #endregion culling
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Panel draw bucket',
      min: -1,
      max: 1,
      divisions: 2,
      value: () => bucket.toDouble(),
      onChanged: (double v) => bucket = v.round(),
      format: (double v) => '${v.round()}',
    ),
    ToggleControl(
      'Panel writes depth',
      value: () => panelWritesDepth,
      onChanged: (bool v) => panelWritesDepth = v,
    ),
    ChoiceControl(
      'Panel depth test',
      options: _tests,
      index: () => testChoice,
      onChanged: (int i) => testChoice = i,
    ),
    ToggleControl(
      'Back-face culling',
      value: () => cullBackFaces,
      onChanged: (bool v) => cullBackFaces = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (_panel.drawBucket >= _box.material.drawBucket) {
      throw StateError('the panel is not ordered before the box');
    }
    if (_panel.depthWrite != false) {
      throw StateError('the panel still writes depth');
    }
    final int sceneDraws = frame.passes
        .where((FramePass pass) => pass.name == 'scene')
        .fold(0, (int sum, FramePass pass) => sum + pass.drawCalls);
    if (sceneDraws != scene.meshes.length) {
      throw StateError(
        'the scene pass drew $sceneDraws of ${scene.meshes.length} meshes',
      );
    }
  }
}
