/// Temporal anti-aliasing: the scene drawn a fraction of a pixel off each
/// frame and blended into a history of the frames before it.
///
/// Quoted by `temporal_anti_aliasing.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class TemporalAntiAliasingDemo extends ShowcaseDemo {
  bool temporal = true;
  bool swapWall = true;
  double historyWeight = 0.9;
  double sharpen = 0.25;
  TemporalClip clip = TemporalClip.aabb;

  /// Seconds since the page opened, which is what moves the railing.
  double _time = 0.0;

  late final SceneNode _railing;
  late final RenderMaterial _wallPaint;

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
    RenderMaterial flat(Vector4 color) => RenderMaterial(
      lighting: LightingModel.unlit,
      baseColor: _fromSrgb(color),
    );
    final DeviceMesh cube = DeviceMesh.upload(
      context.device,
      CuboidShape().build(),
    );
    _wallPaint = flat(Vector4(0.75, 0.25, 0.5, 1.0));
    final RenderMaterial barPaint = flat(Vector4(0.0, 0.0, 1.0, 1.0));

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
    // Pink and yellow. Pink lies inside the YCoCg box that yellow and the
    // blue bars span, so the box keeps it as history.
    final bool yellow = swapWall && (_time ~/ 2).isOdd;
    if (yellow) {
      _wallPaint.baseColor = LinearColor.fromSrgb(1.0, 1.0, 0.0, 1.0);
    } else {
      _wallPaint.baseColor = LinearColor.fromSrgb(0.75, 0.25, 0.5, 1.0);
    }
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
    // #endregion reported
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
