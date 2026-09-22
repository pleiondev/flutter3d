/// Three sphere meshes, packed into one `ModelAsset` with levels of detail and
/// selected by their projected screen size.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class LevelOfDetailDemo extends ShowcaseDemo {
  late final LodGroup _group;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.0
      ..pitch = 0.18
      ..yaw = 0.35;
  }

  @override
  Scene build(DemoContext context) {
    // #region parts
    final List<(String, SphereShape, Vector4)> definitions =
        <(String, SphereShape, Vector4)>[
          (
            'fine',
            const SphereShape(radius: 1.6, segments: 48, rings: 24),
            Vector4(0.16, 0.68, 0.92, 1.0),
          ),
          (
            'medium',
            const SphereShape(radius: 1.6, segments: 20, rings: 10),
            Vector4(0.95, 0.62, 0.16, 1.0),
          ),
          (
            'coarse',
            const SphereShape(radius: 1.6, segments: 8, rings: 4),
            Vector4(0.84, 0.24, 0.28, 1.0),
          ),
        ];
    final List<ModelPart> parts = <ModelPart>[
      for (final (String name, SphereShape shape, Vector4 color) in definitions)
        ModelPart(
          mesh: DeviceMesh.upload(context.device, shape.build()),
          material: Material(
            name: '$name material',
            baseColor: color,
            roughness: 0.52,
          ),
          name: name,
        ),
    ];
    // #endregion parts

    // #region asset
    final ModelNode node = ModelNode(
      name: 'sphere lod',
      surfaces: const <int>[0],
      lods: const <ModelLod>[
        ModelLod(surfaceIndices: <int>[1], maxScreenFraction: 0.34),
        ModelLod(surfaceIndices: <int>[2], maxScreenFraction: 0.15),
      ],
    );
    final ModelAsset asset = ModelAsset(
      name: 'sphere lod asset',
      parts: parts,
      nodes: <ModelNode>[node],
      roots: const <int>[0],
      localBounds: parts.first.mesh.bounds,
    );
    // #endregion asset

    // #region instantiate
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.42, 0.5, 0.68)
      ..ambientIntensity = 0.14
      ..add(
        LightNode(name: 'sun', intensity: 3.2)
          ..setLocalForward(Vector3(-0.46, -0.82, -0.34)),
      );
    asset.instantiate(scene);
    _group = scene.lodGroups.single;
    // #endregion instantiate
    return scene;
  }

  // #region selection
  double _screenFraction(Scene scene) =>
      _group.screenFraction(scene.cameras.single);
  // #endregion selection

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final int visibleLevels = _group.levels
        .where((LodLevel level) => level.node.visible)
        .length;
    final double fraction = _screenFraction(scene);
    if (scene.lodGroups.single != _group ||
        _group.activeLevel < 0 ||
        _group.activeLevel >= _group.levels.length ||
        visibleLevels != 1 ||
        fraction <= 0.0 ||
        frame.drawCalls < 1) {
      throw StateError('the LOD group did not select one visible mesh');
    }
    // #endregion check
  }
}
