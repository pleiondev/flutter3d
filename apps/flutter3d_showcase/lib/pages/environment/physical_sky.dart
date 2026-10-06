/// A physical sky: sunlight scattered by the air, so the colours come from
/// where the sun is, and a fog that lies on the ground and thins with height.
///
/// Quoted by `physical_sky.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class PhysicalSkyDemo extends ShowcaseDemo {
  double sunHeight = 20.0;
  double fogDensity = 0.03;
  double heightFalloff = FogSettings.defaultHeightFalloff;

  late final LightNode _sun;

  // #region air
  // The Earth's air, as the defaults have it. Every colour below is read off
  // this one value: the sky, the sun's light and the fog.
  static const PhysicalSky _air = PhysicalSky();
  // #endregion air

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 14.0
      ..pitch = 0.05
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 3.0, -12.0);
  }

  /// The way to the sun at [sunHeight] degrees, in front of the camera.
  Vector3 get _towardsSun {
    final double up = sunHeight * math.pi / 180.0;
    return Vector3(0.35 * math.cos(up), math.sin(up), -math.cos(up));
  }

  @override
  Scene build(DemoContext context) {
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.6, 0.57, 0.52, 1.0),
      roughness: 0.9,
    );
    final DeviceMesh house = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(2.0, 2.0, 2.0)).build(),
    );
    final Scene scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 200, depth: 200).build(),
          ),
          stone.copy()..doubleSided = true,
          name: 'ground',
        ),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(2.0, 16.0, 2.0)).build(),
          ),
          stone,
          name: 'tower',
        )..setPosition(4.0, 8.0, -40.0),
      );
    // A street of low houses running away from the eye, into the fog.
    for (var i = 0; i < 10; i++) {
      scene.add(
        MeshNode(house, stone, name: 'house $i')
          ..setPosition(i.isEven ? -4.0 : 2.0, 1.0, -6.0 - i * 6.0),
      );
    }
    // #region sun
    _sun = LightNode(name: 'sun', intensity: 3.0);
    scene.add(_sun);
    // #endregion sun
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region sunlight
    // The light that stands for the sun takes the colour the air leaves of
    // it: white at noon, orange low down, nothing once it has set.
    _sun
      ..setLocalForward(-_towardsSun)
      ..color.setFrom(_air.sunlight(_towardsSun));
    // #endregion sunlight
  }

  @override
  RenderSettings settings(DemoContext context) {
    // #region sky
    final SkySettings sky = SkySettings(
      enabled: true,
      physical: _air,
      directionToSun: _towardsSun,
    );
    // #endregion sky
    return RenderSettings(
      sky: sky,
      // #region fog
      fog: FogSettings(
        // The sky along the horizon ahead, so the far end of the street
        // melts into it at any hour.
        color: sky.sample(Vector3(0.0, 0.02, -1.0)),
        density: fogDensity,
        heightFalloff: heightFalloff,
      ),
      // #endregion fog
    );
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Sun height',
      min: -15,
      max: 85,
      value: () => sunHeight,
      onChanged: (double v) => sunHeight = v,
      format: (double v) => '${v.round()} deg',
    ),
    SliderControl(
      'Fog density',
      min: 0,
      max: 0.1,
      value: () => fogDensity,
      onChanged: (double v) => fogDensity = v,
      format: (double v) => '${v.toStringAsFixed(3)} per m',
    ),
    SliderControl(
      'Height falloff',
      min: 0,
      max: 0.3,
      value: () => heightFalloff,
      onChanged: (double v) => heightFalloff = v,
      format: (double v) => '${v.toStringAsFixed(2)} per m',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // The sky is one full-screen draw in the scene pass, after the meshes.
    final FramePass draw = frame.passes.firstWhere(
      (FramePass p) => p.name == 'scene',
    );
    final int meshes = scene.meshes.where((MeshNode m) => m.visible).length;
    if (draw.drawCalls != meshes + 1) {
      throw StateError(
        'expected $meshes mesh draws and one for the sky, '
        'got ${draw.drawCalls}',
      );
    }
    // Twenty degrees up, the sun has come through enough air to lose more
    // blue than red, and the light standing for it says so.
    final Vector3 light = _sun.color;
    if (!(light.x > light.z && light.z > 0.0)) {
      throw StateError('a sun twenty degrees up should be warm: $light');
    }
    // #endregion check
  }
}
