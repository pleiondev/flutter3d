/// Reading a real GLB with `GltfLoader`, into meshes this page draws.
///
/// Quoted by `gltf_load.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class GltfLoadDemo extends ShowcaseDemo {
  late final GltfAsset _asset;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.0
      ..pitch = 0.35
      ..yaw = 0.6;
  }

  @override
  Future<void> prepare(DemoContext context) async {
    // #region load
    // A self-contained GLB from the sample set: one mesh, one material, no
    // sibling files to resolve. `GltfLoader.load` reads the binary container,
    // its accessors and its materials, and hands back a `GltfAsset`.
    const AssetSource source = BundleAssetSource(
      'packages/flutter3d_samples/assets/Box.glb',
    );
    final bytes = await source.read();
    _asset = await GltfLoader().load(bytes);
    // #endregion load
  }

  @override
  Scene build(DemoContext context) {
    // #region upload
    // `GltfAsset` is a `ModelDocument`: a list of surfaces, each a mesh in
    // its own local space plus an index into the document's materials. This
    // page uploads each surface by hand rather than through `ModelAsset`, to
    // keep the loader itself the whole story; `model-asset` is the page that
    // shows the upload path a real application uses, textures included.
    final scene = Scene();
    for (final ModelSurface surface in _asset.surfaces) {
      final SurfaceMaterial? material = surface.materialIndex == null
          ? null
          : _asset.materials[surface.materialIndex!];
      final mesh = MeshNode(
        DeviceMesh.upload(context.device, surface.mesh),
        Material(
          name: material?.name,
          baseColor: material?.baseColor ?? Vector4(0.8, 0.8, 0.8, 1.0),
          metallic: material?.metallic ?? 0.0,
          roughness: material?.roughness ?? 0.6,
        ),
        name: surface.name,
      )..setLocalMatrix(surface.transform);
      scene.add(mesh);
    }
    // #endregion upload

    scene.add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
    );
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_asset.surfaces.isEmpty) {
      throw StateError('the GLB decoded to no surfaces');
    }
    if (_asset.vertexCount == 0) {
      throw StateError('the decoded mesh has no vertices');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the loaded mesh was not drawn');
    }
    // #endregion check
  }
}
