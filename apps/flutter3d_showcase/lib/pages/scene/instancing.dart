/// Sixty-four coloured copies stored in one `InstancedMeshNode`.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class InstancingDemo extends ShowcaseDemo {
  static const int instanceCount = 64;

  double rotationSpeed = 0.25;
  double _angle = 0.0;

  late final InstancedMeshNode _field;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 16.0
      ..pitch = 0.52
      ..yaw = 0.55;
  }

  @override
  Scene build(DemoContext context) {
    // #region batch
    _field = InstancedMeshNode(
      DeviceMesh.upload(
        context.device,
        const CapsuleShape(
          radius: 0.28,
          height: 0.55,
          segments: 20,
          rings: 6,
        ).build(),
      ),
      Material(
        name: 'instance material',
        baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
        roughness: 0.48,
      ),
      capacity: instanceCount,
      name: 'capsule field',
    );
    // #endregion batch

    // #region instances
    const int side = 8;
    for (var i = 0; i < instanceCount; i++) {
      final int x = i % side;
      final int z = i ~/ side;
      final double height = 0.7 + 0.3 * math.sin(x * 0.9 + z * 0.65);
      final Matrix4 transform = Matrix4.identity()
        ..setTranslationRaw((x - 3.5) * 1.35, height, (z - 3.5) * 1.35)
        ..rotateY((x + z) * 0.24)
        ..scaleByDouble(1.0, 0.85 + height * 0.2, 1.0, 1.0);
      _field.addInstance(
        transform,
        color: Vector4(
          0.3 + x / 12.0,
          0.32 + z / 13.0,
          0.78 - (x + z) / 36.0,
          1.0,
        ),
      );
    }
    // #endregion instances

    // #region scene
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.45, 0.52, 0.68)
      ..ambientIntensity = 0.13
      ..add(_field)
      ..add(
        LightNode(name: 'sun', intensity: 3.2)
          ..setLocalForward(Vector3(-0.5, -0.8, -0.32)),
      );
    // #endregion scene
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region motion
    _angle = (_angle + dt * rotationSpeed) % (math.pi * 2.0);
    _field.setRotationYawPitchRoll(_angle, 0.0, 0.0);
    // #endregion motion
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Field rotation',
      min: 0.0,
      max: 1.5,
      value: () => rotationSpeed,
      onChanged: (double value) => rotationSpeed = value,
      format: (double value) => value.toStringAsFixed(2),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_field.count != instanceCount ||
        _field.capacity < instanceCount ||
        frame.instances < instanceCount ||
        frame.drawCalls < 1) {
      throw StateError('the instanced field was not drawn');
    }
    // #endregion check
  }
}
