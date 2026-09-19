/// Five meshes generated from shape values without loading an asset.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ProceduralShapesDemo extends ShowcaseDemo {
  final List<MeshNode> _shapes = <MeshNode>[];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 11.0
      ..pitch = 0.25
      ..yaw = 0.12;
    context.orbit.target.setValues(0.0, 0.35, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region descriptions
    final List<(String, Shape)> descriptions = <(String, Shape)>[
      ('cuboid', CuboidShape(size: Vector3(1.4, 1.4, 1.4))),
      ('sphere', const SphereShape(radius: 0.8, segments: 32, rings: 16)),
      (
        'torus',
        const TorusShape(
          radius: 0.58,
          tubeRadius: 0.24,
          segments: 40,
          tubeSegments: 18,
        ),
      ),
      (
        'capsule',
        const CapsuleShape(radius: 0.45, height: 0.8, segments: 32, rings: 8),
      ),
      ('disc', const DiscShape(radius: 0.9, innerRadius: 0.28, segments: 40)),
    ];
    // #endregion descriptions

    // #region build
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.55, 0.62, 0.78)
      ..ambientIntensity = 0.16;
    for (var i = 0; i < descriptions.length; i++) {
      final (String name, Shape shape) = descriptions[i];
      final MeshData data = shape.build();
      final Material material = Material(
        name: '$name material',
        baseColor: Vector4(
          0.28 + i * 0.12,
          0.68 - i * 0.07,
          0.82 - i * 0.1,
          1.0,
        ),
        roughness: 0.42,
        metallic: i == 2 ? 0.55 : 0.05,
        doubleSided: name == 'disc',
      );
      final MeshNode node = MeshNode(
        DeviceMesh.upload(context.device, data),
        material,
        name: name,
      )..setPosition((i - 2) * 2.0, name == 'disc' ? 0.25 : 0.85, 0.0);
      _shapes.add(node);
      scene.add(node);
    }
    // #endregion build

    // #region lighting
    scene
      ..add(
        LightNode(name: 'key', intensity: 3.4)
          ..setLocalForward(Vector3(-0.45, -0.8, -0.38)),
      )
      ..add(
        LightNode(
          type: LightType.point,
          intensity: 10.0,
          range: 12.0,
          name: 'fill',
        )..setPosition(-3.0, 3.5, 3.0),
      );
    // #endregion lighting
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final Set<String?> names = <String?>{
      for (final MeshNode node in _shapes) node.name,
    };
    const Set<String> expected = <String>{
      'cuboid',
      'sphere',
      'torus',
      'capsule',
      'disc',
    };
    if (_shapes.length != expected.length ||
        !names.containsAll(expected) ||
        frame.drawCalls < expected.length) {
      throw StateError('not every procedural shape was drawn');
    }
    // #endregion check
  }
}
