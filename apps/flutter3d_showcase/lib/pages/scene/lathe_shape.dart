/// A vessel made by sweeping a profile around the Y axis.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class LatheShapeDemo extends ShowcaseDemo {
  final List<MeshNode> _vessels = <MeshNode>[];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.24
      ..yaw = 0.42;
    context.orbit.target.setValues(0.0, 1.15, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region profile
    final List<Vector2> profile = <Vector2>[
      Vector2(0.0, -1.25),
      Vector2(0.72, -1.25),
      Vector2(0.78, -1.1),
      Vector2(0.82, -0.55),
      Vector2(0.62, 0.05),
      Vector2(0.46, 0.7),
      Vector2(0.46, 1.05),
      Vector2(0.62, 1.18),
      Vector2(0.62, 1.25),
      Vector2(0.5, 1.25),
    ];
    // #endregion profile

    // #region sweep
    final List<(String, double, int)> variants = <(String, double, int)>[
      ('faceted', math.pi * 2.0, 12),
      ('smooth', math.pi * 2.0, 48),
      ('open sweep', math.pi * 1.5, 36),
    ];
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.48, 0.56, 0.72)
      ..ambientIntensity = 0.14;
    for (var i = 0; i < variants.length; i++) {
      final (String name, double sweep, int segments) = variants[i];
      final MeshData data = LatheShape(
        profile: profile,
        segments: segments,
        sweepAngle: sweep,
        name: name,
      ).build();
      final Material clay = Material(
        name: '$name clay',
        baseColor: Vector4(0.78, 0.35 + i * 0.12, 0.2 + i * 0.16, 1.0),
        roughness: 0.48,
        doubleSided: sweep < math.pi * 2.0,
      );
      final MeshNode node = MeshNode(
        DeviceMesh.upload(context.device, data),
        clay,
        name: name,
      )..setPosition((i - 1) * 2.6, 1.25, 0.0);
      _vessels.add(node);
      scene.add(node);
    }
    // #endregion sweep

    // #region light
    scene
      ..add(
        LightNode(name: 'key', intensity: 3.2)
          ..setLocalForward(Vector3(-0.45, -0.82, -0.34)),
      )
      ..add(
        LightNode(
          type: LightType.point,
          intensity: 8.0,
          range: 10.0,
          name: 'rim',
        )..setPosition(2.5, 3.8, -2.5),
      );
    // #endregion light
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    const Set<String> expected = <String>{'faceted', 'smooth', 'open sweep'};
    final Set<String?> actual = <String?>{
      for (final MeshNode node in _vessels) node.name,
    };
    if (_vessels.length != 3 ||
        !actual.containsAll(expected) ||
        frame.drawCalls < 3) {
      throw StateError('the three lathe variants were not drawn');
    }
    // #endregion check
  }
}
