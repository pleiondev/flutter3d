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
    // #region write
    // A real GLB, written by this engine's own `GltfWriter` so this page
    // needs no bundled asset to read: two surfaces, one material each.
    final source = PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(
          mesh: CuboidShape(size: Vector3.all(0.9)).build(),
          materialIndex: 0,
        ),
        ModelSurface(
          mesh: SphereShape(segments: 32, rings: 16).build(),
          materialIndex: 1,
        ),
      ],
      materials: <SurfaceMaterial>[
        SurfaceMaterial(baseColor: Vector4(0.8, 0.4, 0.3, 1.0)),
        SurfaceMaterial(
          baseColor: Vector4(0.3, 0.6, 0.8, 1.0),
          metallic: 0.8,
          roughness: 0.3,
        ),
      ],
      nodes: <ModelNode>[
        ModelNode(surfaces: <int>[0]),
        ModelNode(surfaces: <int>[1], translation: Vector3(1.6, 0.0, 0.0)),
      ],
    );
    final bytes = GltfWriter(source).writeGlb();
    // #endregion write

    // #region load
    // `GltfLoader.load` reads the container, walks its accessors and
    // materials, and hands back a `GltfAsset`, whatever wrote the file.
    _asset = await GltfLoader().load(bytes);
    // #endregion load
  }

  @override
  Scene build(DemoContext context) {
    // #region upload
    // `GltfAsset` is a `ModelDocument`: a list of surfaces, each with an
    // index into the document's materials, plus a node hierarchy that
    // places them. This page uploads each surface by hand rather than
    // through `ModelAsset`, to keep the loader itself the whole story; the
    // `model-asset` page shows the upload path a real application uses,
    // textures included.
    final scene = Scene();
    for (final ModelNode node in _asset.nodes) {
      for (final int surfaceIndex in node.surfaces) {
        final ModelSurface surface = _asset.surfaces[surfaceIndex];
        final SurfaceMaterial? material = surface.materialIndex == null
            ? null
            : _asset.materials[surface.materialIndex!];
        scene.add(
          MeshNode(
            DeviceMesh.upload(context.device, surface.mesh),
            Material(
              name: material?.name,
              baseColor: material?.baseColor ?? Vector4(0.8, 0.8, 0.8, 1.0),
              metallic: material?.metallic ?? 0.0,
              roughness: material?.roughness ?? 0.6,
            ),
            name: surface.name,
          )..setPositionFrom(node.translation),
        );
      }
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
    if (_asset.surfaces.length != 2) {
      throw StateError('the GLB decoded to the wrong number of surfaces');
    }
    if (_asset.vertexCount == 0) {
      throw StateError('the decoded mesh has no vertices');
    }
    if (frame.drawCalls < 2) {
      throw StateError('both surfaces were not drawn');
    }
    // #endregion check
  }
}
