/// A short march toward the sun that darkens the crease where an object meets
/// what it stands on.
///
/// Quoted by `contact_shadows.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ContactShadowsDemo extends ShowcaseDemo {
  bool contact = true;
  bool shadowMap = false;
  double length = 0.4;
  double steps = 12.0;
  double thickness = 0.15;
  double strength = 1.0;

  late final LightNode _sun;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.0
      ..pitch = 0.5
      ..yaw = 0.5;
  }

  @override
  Scene build(DemoContext context) {
    // #region props
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.78, 0.76, 0.72, 1.0),
      roughness: 0.9,
    );
    final Material clay = Material(
      name: 'clay',
      baseColor: Vector4(0.85, 0.45, 0.3, 1.0),
      roughness: 0.7,
    );
    final Scene scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 10, depth: 10).build(),
          ),
          stone,
          name: 'ground',
        ),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(1.4, 1.0, 1.0)).build(),
          ),
          clay,
          name: 'crate',
        )..setPosition(-1.2, 0.5, 0.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            SphereShape(radius: 0.6, segments: 32, rings: 16).build(),
          ),
          clay,
          name: 'ball',
        )..setPosition(1.3, 0.6, 0.3),
      );
    // #endregion props

    // #region sun
    _sun = LightNode(name: 'sun', intensity: 3.0)
      ..setLocalForward(Vector3(-0.6, -0.55, -0.4));
    // #endregion sun
    return scene..add(_sun);
  }

  @override
  void update(DemoContext context, double dt) {
    // #region map
    _sun.castsShadow = shadowMap;
    // #endregion map
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    contactShadows: ContactShadowSettings(
      enabled: contact,
      length: length,
      steps: steps.round(),
      thickness: thickness,
      strength: strength,
    ),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Contact shadows',
      value: () => contact,
      onChanged: (bool v) => contact = v,
    ),
    ToggleControl(
      'Shadow map too',
      value: () => shadowMap,
      onChanged: (bool v) => shadowMap = v,
    ),
    SliderControl(
      'Length',
      min: 0.05,
      max: 1.5,
      value: () => length,
      onChanged: (double v) => length = v,
      format: (double v) => '${v.toStringAsFixed(2)} m',
    ),
    SliderControl(
      'Steps',
      min: 1,
      max: 16,
      divisions: 15,
      value: () => steps,
      onChanged: (double v) => steps = v,
      format: (double v) => '${v.round()}',
    ),
    SliderControl(
      'Thickness',
      min: 0.02,
      max: 0.6,
      value: () => thickness,
      onChanged: (double v) => thickness = v,
      format: (double v) => '${v.toStringAsFixed(2)} m',
    ),
    SliderControl(
      'Strength',
      min: 0,
      max: 1,
      value: () => strength,
      onChanged: (double v) => strength = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final FramePass? pass = frame.passes
        .where((FramePass p) => p.name == 'contact shadows')
        .firstOrNull;
    if (pass == null) {
      throw StateError('the contact shadow pass did not run');
    }
    if (pass.drawCalls < 1) {
      throw StateError('the contact shadow pass ran and drew nothing');
    }
  }
}
