/// Projected box decals: a box that paints a colour onto whatever geometry
/// stands inside it, a stain on a floor or a sign on a wall, without a
/// polygon of its own.
///
/// Quoted by `decals.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class DecalsDemo extends ShowcaseDemo {
  bool decals = true;
  bool blueOnTop = true;
  double opacity = 0.9;
  double angleLimitDegrees = 75.0;

  late final DecalNode _stain;
  late final DecalNode _puddle;
  late final DecalNode _sign;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 7.0
      ..pitch = 0.6
      ..yaw = 0.5;
    context.orbit.target.setValues(0.0, 0.6, 0.0);
  }

  MeshNode _slab(
    DemoContext context,
    String name,
    Vector3 size,
    Vector3 at,
    Vector4 colour,
  ) => MeshNode(
    DeviceMesh.upload(context.device, CuboidShape(size: size).build()),
    Material(name: name, baseColor: colour, roughness: 0.8),
    name: name,
  )..setPositionFrom(at);

  @override
  Scene build(DemoContext context) {
    // #region room
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.55, 0.6, 0.7)
      ..ambientIntensity = 0.35
      ..add(
        _slab(
          context,
          'floor',
          Vector3(6.0, 0.1, 6.0),
          Vector3(0.0, -0.05, 0.0),
          Vector4(0.8, 0.8, 0.78, 1.0),
        ),
      )
      ..add(
        _slab(
          context,
          'wall',
          Vector3(6.0, 3.0, 0.1),
          Vector3(0.0, 1.5, -2.0),
          Vector4(0.82, 0.8, 0.76, 1.0),
        ),
      )
      ..add(
        // A crate standing in the stain's box: its top takes the stain, and
        // its sides only as far as the angle limit lets them.
        _slab(
          context,
          'crate',
          Vector3(0.6, 0.6, 0.6),
          Vector3(0.5, 0.3, 0.4),
          Vector4(0.7, 0.62, 0.5, 1.0),
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.0, castsShadow: true)
          ..setLocalForward(Vector3(-0.4, -0.8, -0.35)),
      );
    // #endregion room

    // #region floor
    // With no rotation a decal's box lies flat and stamps down its own y
    // axis: x and z are the size of the picture, y how deep it reaches.
    _stain = DecalNode(name: 'stain', color: Vector4(0.85, 0.2, 0.1, opacity))
      ..setPosition(0.3, 0.0, 0.3)
      ..setScale(2.0, 1.4, 2.0);
    _puddle = DecalNode(name: 'puddle', color: Vector4(0.15, 0.3, 0.9, opacity))
      ..setPosition(-0.6, 0.0, 0.6)
      ..setScale(1.8, 0.4, 1.4);
    scene
      ..add(_stain)
      ..add(_puddle);
    // #endregion floor

    // #region wall
    // On a wall the box is turned until its up points out of the wall.
    _sign = DecalNode(name: 'sign', color: Vector4(0.95, 0.8, 0.1, 1.0))
      ..setPosition(-1.2, 1.6, -1.95)
      ..setScale(1.4, 0.3, 0.8);
    _sign.setRotation(
      Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2),
    );
    scene.add(_sign);
    // #endregion wall
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region order
    // Where the two floor decals overlap, the higher order is painted over
    // the lower one.
    _puddle.order = blueOnTop ? 1 : 0;
    _stain.order = blueOnTop ? 0 : 1;
    // #endregion order
    // #region angle
    // The crate's sides turn ninety degrees from the stain's up: a limit
    // under ninety keeps the stain off them, one past it paints them too.
    _stain.angleLimit = angleLimitDegrees * math.pi / 180.0;
    // #endregion angle
    _stain.color.w = opacity;
    _puddle.color.w = opacity;
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region switch
    decals: DecalSettings(enabled: decals),
    // #endregion switch
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Decals',
      value: () => decals,
      onChanged: (bool v) => decals = v,
    ),
    ToggleControl(
      'Blue over red',
      value: () => blueOnTop,
      onChanged: (bool v) => blueOnTop = v,
    ),
    SliderControl(
      'Opacity',
      min: 0,
      max: 1,
      value: () => opacity,
      onChanged: (double v) => opacity = v,
      format: (double v) => v.toStringAsFixed(2),
    ),
    SliderControl(
      'Angle limit',
      min: 10,
      max: 110,
      value: () => angleLimitDegrees,
      onChanged: (double v) => angleLimitDegrees = v,
      format: (double v) => '${v.round()}°',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // Three decals in the scene and the switch on: the pass that paints them
    // has to have run, not been culled or skipped.
    if (scene.decals.length != 3) {
      throw StateError('the scene holds ${scene.decals.length} decals, not 3');
    }
    final PassSkip? skipped = frame.skipReasonOf('decals');
    if (skipped != null) {
      throw StateError('the decal pass was skipped: $skipped');
    }
    if (!frame.passes.any((FramePass p) => p.name == 'decals')) {
      throw StateError('the decal pass did not run');
    }
    // #endregion check
  }
}
