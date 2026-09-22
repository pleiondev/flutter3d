/// Uploading a decoded document with `ModelAsset.fromDocument`, then
/// placing it in a scene with `instantiate`.
///
/// Quoted by `model_asset.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ModelAssetDemo extends ShowcaseDemo {
  late final ModelAsset _asset;
  ModelInstance? _instance;

  // #region document
  // A decoded document, the shape every format in this package produces.
  // `ModelAsset.fromDocument` does not care which one wrote it.
  final _document = PlainModelDocument(
    surfaces: <ModelSurface>[
      ModelSurface(
        mesh: SphereShape(segments: 32, rings: 16).build(),
        materialIndex: 0,
      ),
    ],
    materials: <SurfaceMaterial>[
      SurfaceMaterial(
        name: 'shell',
        baseColor: Vector4(0.75, 0.4, 0.6, 1.0),
        metallic: 0.2,
        roughness: 0.4,
      ),
    ],
    nodes: <ModelNode>[
      ModelNode(surfaces: <int>[0]),
    ],
  );
  // #endregion document

  @override
  Future<void> prepare(DemoContext context) async {
    // #region upload
    // Meshes and images are uploaded once, deduplicated by identity; a
    // document's materials become the engine's own `Material`, ready to be
    // placed as many times as a scene wants.
    _asset = await ModelAsset.fromDocument(_document, device: context.device);
    // #endregion upload
  }

  @override
  Scene build(DemoContext context) {
    // #region instantiate
    // `instantiate` rebuilds the asset's hierarchy as scene nodes and
    // returns a `ModelInstance`: the node it hangs from, one scene node a
    // decoded node, and a skeleton or an animation player when the asset
    // carries one.
    final scene = Scene();
    _instance = _asset.instantiate(scene);
    // #endregion instantiate

    scene.add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
    );
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_asset.vertexCount == 0) {
      throw StateError('the asset uploaded no vertices');
    }
    if (_instance == null || _instance!.meshes.isEmpty) {
      throw StateError('instantiate did not add a mesh to the scene');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the instance was not drawn');
    }
    // #endregion check
  }
}
