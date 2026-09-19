/// A camera and a light, written into a GLB and read back out of it.
///
/// Quoted by `gltf_cameras_lights.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class GltfCamerasLightsDemo extends ShowcaseDemo {
  late final GltfAsset _readBack;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.5
      ..pitch = 0.3
      ..yaw = 0.6;
  }

  @override
  Future<void> prepare(DemoContext context) async {
    // #region document
    // glTF's own `KHR_lights_punctual` and `camera` are held on a document as
    // `ModelLight` and `ModelCamera`, addressed from a node the same way a
    // surface is. This document has one of each, plus a cube to see by.
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(mesh: CuboidShape(size: Vector3.all(1.0)).build()),
      ],
      lights: <ModelLight>[
        ModelLight(
          type: ModelLightType.directional,
          color: Vector3(1.0, 0.95, 0.85),
          intensity: 2.4,
        ),
      ],
      cameras: <ModelCamera>[
        const ModelCamera(
          projection: ModelPerspectiveCamera(yfov: 0.9, znear: 0.1),
          name: 'framing',
        ),
      ],
      nodes: <ModelNode>[
        ModelNode(surfaces: <int>[0]),
        ModelNode(name: 'sun', lightIndex: 0),
        ModelNode(name: 'framing', cameraIndex: 0),
      ],
    );
    // #endregion document

    // #region roundtrip
    final bytes = GltfWriter(document).writeGlb();
    _readBack = await GltfLoader().load(bytes);
    // #endregion roundtrip
  }

  @override
  Scene build(DemoContext context) {
    // #region scene
    final scene = Scene();
    for (final ModelSurface surface in _readBack.surfaces) {
      scene.add(
        MeshNode(
          DeviceMesh.upload(context.device, surface.mesh),
          Material(baseColor: Vector4(0.7, 0.75, 0.82, 1.0), roughness: 0.6),
          name: 'cube',
        ),
      );
    }
    for (final ModelLight light in _readBack.lights) {
      scene.add(
        LightNode(name: light.name, intensity: light.intensity)
          ..setLocalForward(Vector3(-0.4, -0.9, -0.3)),
      );
    }
    // #endregion scene
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_readBack.lights.length != 1) {
      throw StateError('the light did not survive the round trip');
    }
    if (_readBack.cameras.length != 1) {
      throw StateError('the camera did not survive the round trip');
    }
    final ModelCameraProjection projection =
        _readBack.cameras.single.projection;
    if (projection is! ModelPerspectiveCamera) {
      throw StateError('the camera came back as the wrong projection');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the cube was not drawn');
    }
    // #endregion check
  }
}
