/// A pane of glass in front of a striped wall, showing the wall through it.
///
/// Quoted by `transmission.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class TransmissionDemo extends ShowcaseDemo {
  double transmission = 1.0;
  double roughness = 0.0;
  double thickness = 0.9;
  double ior = 1.5;

  late final Material _pane;
  late final Material _ball;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 2.6
      ..yaw = 0.0
      ..pitch = 0.0;
  }

  @override
  Scene build(DemoContext context) {
    final Quaternion upright = Quaternion.axisAngle(
      Vector3(1.0, 0.0, 0.0),
      math.pi / 2,
    );
    Material flat(Vector4 colour) =>
        Material(lighting: LightingModel.unlit, baseColor: colour);

    // #region wall
    final DeviceMesh half = DeviceMesh.upload(
      context.device,
      const PlaneShape(width: 3.0, depth: 4.0).build(),
    );
    final DeviceMesh stripe = DeviceMesh.upload(
      context.device,
      const PlaneShape(width: 0.08, depth: 4.0).build(),
    );
    final Scene scene = Scene()
      ..ambientIntensity = 0.2
      ..add(
        MeshNode(half, flat(Vector4(0.8, 0.1, 0.1, 1.0)), name: 'red wall')
          ..setRotation(upright)
          ..setPosition(-1.5, 0.0, -2.0),
      )
      ..add(
        MeshNode(half, flat(Vector4(0.1, 0.2, 0.9, 1.0)), name: 'blue wall')
          ..setRotation(upright)
          ..setPosition(1.5, 0.0, -2.0),
      );
    for (var i = 0; i < 9; i++) {
      scene.add(
        MeshNode(stripe, flat(Vector4(0.95, 0.95, 0.9, 1.0)), name: 'stripe')
          ..setRotation(upright)
          ..setPosition(-2.0 + i * 0.5, 0.0, -1.98),
      );
    }
    // #endregion wall

    // #region glass
    Material glass(String name, {required double thickness}) => Material(
      name: name,
      lighting: LightingModel.pbrLayered,
      baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
      roughness: roughness,
      doubleSided: true,
      extensions: MaterialExtensions(
        transmission: transmission,
        thickness: thickness,
        ior: ior,
      ),
    );
    _pane = glass('pane', thickness: 0.0);
    _ball = glass('ball', thickness: thickness);
    scene
      ..add(
        MeshNode(
            DeviceMesh.upload(
              context.device,
              const PlaneShape(width: 0.9, depth: 1.4).build(),
            ),
            _pane,
            name: 'pane',
          )
          ..setRotation(upright)
          ..setPosition(-0.6, 0.0, 0.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            SphereShape(radius: 0.45, segments: 48, rings: 24).build(),
          ),
          _ball,
          name: 'ball',
        )..setPosition(0.6, 0.0, 0.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.3, -0.6, -1.0).normalized()),
      );
    // #endregion glass
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    for (final (Material material, double depth) in <(Material, double)>[
      (_pane, 0.0),
      (_ball, thickness),
    ]) {
      material
        ..roughness = roughness
        ..extensions = MaterialExtensions(
          transmission: transmission,
          thickness: depth,
          ior: ior,
        );
    }
    // #endregion live
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Transmission',
      min: 0,
      max: 1,
      value: () => transmission,
      onChanged: (double v) => transmission = v,
    ),
    SliderControl(
      'Roughness',
      min: 0,
      max: 1,
      value: () => roughness,
      onChanged: (double v) => roughness = v,
    ),
    SliderControl(
      'Thickness',
      min: 0,
      max: 1.5,
      value: () => thickness,
      onChanged: (double v) => thickness = v,
      format: (double v) => '${v.toStringAsFixed(2)} m',
    ),
    SliderControl(
      'Index of refraction',
      min: 1.0,
      max: 2.4,
      value: () => ior,
      onChanged: (double v) => ior = v,
      format: (double v) => v.toStringAsFixed(2),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // A pane with no transmission is ordinary opaque metal-rough, and the
    // frame draws in one pass as it always did.
    if (transmission <= 0.0) return;
    final Set<String> ran = <String>{
      for (final FramePass pass in frame.passes) pass.name,
    };
    if (!ran.contains('scene colour copy')) {
      throw StateError(
        'the glass is in the frame but the scene was not copied',
      );
    }
    final FramePass? glass = frame.passes
        .where((FramePass p) => p.name == 'transparent')
        .firstOrNull;
    if (glass == null || glass.drawCalls < 1) {
      throw StateError('the pass that draws the glass drew nothing');
    }
  }
}
