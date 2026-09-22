/// A mesh whose triangle order is scrambled, then rebuilt for GPU cache reuse.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class VertexCacheDemo extends ShowcaseDemo {
  double _beforeRatio = 0.0;
  double _afterRatio = 0.0;
  late final int _originalVertexCount;
  late final int _reorderedIndexCount;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.5
      ..pitch = 0.24
      ..yaw = 0.4;
  }

  @override
  Scene build(DemoContext context) {
    // #region scramble
    final MeshData sphere = const SphereShape(
      radius: 1.1,
      segments: 32,
      rings: 16,
    ).build();
    final int triangleCount = sphere.triangleCount;
    final List<int> order = List<int>.generate(triangleCount, (int i) => i)
      ..shuffle(math.Random(7));
    final Uint32List scrambled = Uint32List(sphere.indices.length);
    for (var t = 0; t < triangleCount; t++) {
      final int from = order[t] * 3;
      scrambled[t * 3] = sphere.indices[from];
      scrambled[t * 3 + 1] = sphere.indices[from + 1];
      scrambled[t * 3 + 2] = sphere.indices[from + 2];
    }
    // #endregion scramble

    // #region reorder
    _beforeRatio = averageCacheMissRatio(scrambled);
    final Uint32List cacheOrdered = optimizeTriangleOrder(
      scrambled,
      sphere.vertexCount,
    );
    final ({Uint32List indices, Uint32List oldToNew}) fetch =
        optimizeVertexFetch(cacheOrdered, sphere.vertexCount);
    _afterRatio = averageCacheMissRatio(cacheOrdered);
    // #endregion reorder

    // #region rebuild
    final int stride = sphere.layout.floatsPerVertex;
    final Float32List vertices = Float32List(sphere.vertices.length);
    for (var oldV = 0; oldV < sphere.vertexCount; oldV++) {
      final int newV = fetch.oldToNew[oldV];
      vertices.setRange(
        newV * stride,
        newV * stride + stride,
        sphere.vertices,
        oldV * stride,
      );
    }
    final MeshData reordered = MeshData(
      layout: sphere.layout,
      vertices: vertices,
      indices: fetch.indices,
    );
    _originalVertexCount = sphere.vertexCount;
    _reorderedIndexCount = reordered.indexCount;
    // #endregion rebuild

    final Scene scene = Scene()
      ..ambientColor = Vector3(0.44, 0.5, 0.66)
      ..ambientIntensity = 0.16
      ..add(
        MeshNode(
          DeviceMesh.upload(context.device, reordered),
          Material(
            name: 'sphere',
            baseColor: Vector4(0.3, 0.62, 0.86, 1.0),
            roughness: 0.5,
          ),
          name: 'sphere',
        ),
      )
      ..add(
        LightNode(name: 'key', intensity: 3.2)
          ..setLocalForward(Vector3(-0.42, -0.8, -0.36)),
      );
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_reorderedIndexCount == 0 ||
        _originalVertexCount == 0 ||
        _afterRatio > _beforeRatio ||
        frame.drawCalls < 1) {
      throw StateError('reordering the mesh did not improve cache locality');
    }
    // #endregion check
  }
}
