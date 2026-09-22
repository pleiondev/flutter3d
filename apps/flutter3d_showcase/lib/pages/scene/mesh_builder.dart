/// A pyramid, written vertex by vertex instead of generated from a shape.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class MeshBuilderDemo extends ShowcaseDemo {
  late final MeshData _pyramid;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.5
      ..pitch = 0.28
      ..yaw = 0.5;
  }

  @override
  Scene build(DemoContext context) {
    // #region builder
    final MeshBuilder builder = MeshBuilder(VertexLayout.standard);
    const double half = 0.9;
    const double apexHeight = 1.3;
    final Vector3 apex = Vector3(0.0, apexHeight, 0.0);
    final List<Vector3> base = <Vector3>[
      Vector3(-half, 0.0, -half),
      Vector3(half, 0.0, -half),
      Vector3(half, 0.0, half),
      Vector3(-half, 0.0, half),
    ];
    // #endregion builder

    // #region faces
    final int apexIndex = builder.addVertex(
      position: apex,
      normal: Vector3(0.0, 1.0, 0.0),
      texcoord: Vector2(0.5, 0.0),
      color: Vector4(1.0, 0.92, 0.6, 1.0),
    );
    final List<int> baseIndices = <int>[];
    for (var i = 0; i < base.length; i++) {
      final Vector3 edge = base[(i + 1) % base.length] - base[i];
      final Vector3 toApex = apex - base[i];
      final Vector3 normal = edge.cross(toApex)..normalize();
      baseIndices.add(
        builder.addVertex(
          position: base[i],
          normal: normal,
          texcoord: Vector2(i / base.length, 1.0),
          color: Vector4(0.65, 0.7, 0.8, 1.0),
        ),
      );
    }
    for (var i = 0; i < base.length; i++) {
      builder.addTriangle(baseIndices[i], baseIndices[(i + 1) % 4], apexIndex);
    }
    builder.addQuad(
      baseIndices[3],
      baseIndices[2],
      baseIndices[1],
      baseIndices[0],
    );
    _pyramid = builder.build();
    // #endregion faces

    // #region scene
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.42, 0.5, 0.66)
      ..ambientIntensity = 0.16
      ..add(
        MeshNode(
          DeviceMesh.upload(context.device, _pyramid),
          Material(name: 'pyramid', roughness: 0.6),
          name: 'pyramid',
        ),
      )
      ..add(
        LightNode(name: 'key', intensity: 3.2)
          ..setLocalForward(Vector3(-0.42, -0.78, -0.4)),
      );
    // #endregion scene
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_pyramid.vertexCount != 5 ||
        _pyramid.indexCount != 18 ||
        frame.drawCalls < 1) {
      throw StateError('the hand-built pyramid did not reach the frame');
    }
    // #endregion check
  }
}
