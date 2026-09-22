/// One torus left with a flat, constant tangent and one with tangents
/// generated from its UVs, both lit by the same tilted normal map.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class TangentsDemo extends ShowcaseDemo {
  late final MeshData _flatMesh;
  late final MeshData _generatedMesh;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.5
      ..pitch = 0.2
      ..yaw = 0.4;
  }

  @override
  Scene build(DemoContext context) {
    // #region undressed
    final MeshData undressed = const TorusShape(
      radius: 0.85,
      tubeRadius: 0.34,
      segments: 40,
      tubeSegments: 20,
    ).build(layout: VertexLayout.positionNormalTexcoord);
    // #endregion undressed

    // #region compare
    _flatMesh = undressed.convertedTo(VertexLayout.standard);
    _generatedMesh = undressed.withGeneratedTangents(
      target: VertexLayout.standard,
    );
    // #endregion compare

    // #region bump
    final TextureHandle tilt = SolidColorTexture(
      Vector4(0.78, 0.5, 0.86, 1.0),
    ).upload(context.device);
    Material bumpMaterial(String name) => Material(
      name: name,
      baseColor: Vector4(0.6, 0.64, 0.7, 1.0),
      metallic: 0.85,
      roughness: 0.2,
      normal: tilt,
    );
    // #endregion bump

    final Scene scene = Scene()
      ..ambientColor = Vector3(0.4, 0.48, 0.64)
      ..ambientIntensity = 0.14
      ..add(
        MeshNode(
          DeviceMesh.upload(context.device, _flatMesh),
          bumpMaterial('flat tangent'),
          name: 'flat',
        )..setPosition(-1.3, 1.0, 0.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(context.device, _generatedMesh),
          bumpMaterial('generated tangent'),
          name: 'generated',
        )..setPosition(1.3, 1.0, 0.0),
      )
      ..add(
        LightNode(name: 'key', intensity: 3.4)
          ..setLocalForward(Vector3(-0.4, -0.7, -0.5)),
      );
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final int stride = VertexLayout.standard.floatsPerVertex;
    final int tangentOffset = VertexLayout.standard.floatOffsetOf(
      VertexLayout.tangent.name,
    );
    bool tangentVaries(MeshData mesh) {
      double? firstX;
      for (var v = 0; v < mesh.vertexCount; v++) {
        final double x = mesh.vertices[v * stride + tangentOffset];
        firstX ??= x;
        if ((x - firstX).abs() > 1e-4) return true;
      }
      return false;
    }

    if (tangentVaries(_flatMesh) ||
        !tangentVaries(_generatedMesh) ||
        frame.drawCalls < 2) {
      throw StateError('the generated tangents did not follow the surface');
    }
    // #endregion check
  }
}
