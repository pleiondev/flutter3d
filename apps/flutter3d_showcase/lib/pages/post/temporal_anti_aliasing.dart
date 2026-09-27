/// Temporal anti-aliasing: the scene drawn a fraction of a pixel off each
/// frame and blended into a history of the frames before it.
///
/// Quoted by `temporal_anti_aliasing.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class TemporalAntiAliasingDemo extends ShowcaseDemo {
  bool temporal = true;
  bool swapWall = true;
  double historyWeight = 0.9;
  double sharpen = 0.25;
  TemporalClip clip = TemporalClip.aabb;

  /// Seconds since the page opened, which is what moves the railing.
  double _time = 0.0;

  late final SceneNode _railing;
  late final Material _wallPaint;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.5
      ..pitch = 0.0
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region railing
    Material flat(Vector4 colour) =>
        Material(lighting: LightingModel.unlit, baseColor: colour);
    final DeviceMesh cube = DeviceMesh.upload(
      context.device,
      CuboidShape().build(),
    );
    _wallPaint = flat(Vector4(1.0, 0.0, 0.0, 1.0));
    final Material barPaint = flat(Vector4(0.0, 0.0, 1.0, 1.0));

    _railing = SceneNode(name: 'railing');
    for (int i = -6; i <= 6; i++) {
      _railing.add(
        MeshNode(cube, barPaint, name: 'bar $i')
          ..setPosition(i * 0.45, 0.0, 0.0)
          ..setRotationYawPitchRoll(0.0, 0.0, 0.3)
          ..setScale(0.04, 6.0, 0.04),
      );
    }
    final MeshNode wall = MeshNode(cube, _wallPaint, name: 'wall')
      ..setPosition(0.0, 0.0, -0.3)
      ..setScale(20.0, 20.0, 0.1);
    // #endregion railing
    return Scene()
      ..add(wall)
      ..add(_railing);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region motion
    _time += dt;
    _railing.setPosition(0.25 * math.sin(_time * 1.5), 0.0, 0.0);
    final bool green = swapWall && (_time ~/ 2).isOdd;
    _wallPaint.baseColor.setValues(green ? 0.0 : 1.0, green ? 1.0 : 0.0, 0, 1);
    // #endregion motion
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    antiAlias: AntiAliasSettings(
      temporal: TemporalSettings(
        enabled: temporal,
        historyWeight: historyWeight,
        sharpen: sharpen,
        clip: clip,
      ),
    ),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Temporal resolve',
      value: () => temporal,
      onChanged: (bool v) => temporal = v,
    ),
    ToggleControl(
      'Swap the wall colour',
      value: () => swapWall,
      onChanged: (bool v) => swapWall = v,
    ),
    // #region clips
    ChoiceControl(
      'History clip',
      options: <String>[
        for (final TemporalClip c in TemporalClip.values) c.name,
      ],
      index: () => clip.index,
      onChanged: (int i) => clip = TemporalClip.values[i],
    ),
    // #endregion clips
    SliderControl(
      'History weight',
      min: 0,
      max: 0.98,
      value: () => historyWeight,
      onChanged: (double v) => historyWeight = v,
    ),
    SliderControl(
      'Sharpen',
      min: 0,
      max: 1,
      value: () => sharpen,
      onChanged: (double v) => sharpen = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region reported
    expectPassOrDecline(frame, 'temporal resolve');
    if (passRan(frame, 'temporal resolve') && !frame.antiAliasing.temporal) {
      throw StateError(
        'the resolve ran and the frame did not report temporal anti-aliasing',
      );
    }
    // #endregion reported
  }
}
