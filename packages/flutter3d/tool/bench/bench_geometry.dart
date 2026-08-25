// ignore_for_file: avoid_print — see bench.dart.

import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:vector_math/vector_math.dart';

import 'bench_util.dart';

/// Cost of building and transforming procedural geometry.
Future<void> benchGeometryGeneration() async {
  print('');
  print('--- geometry generation ------------------------------------------');

  const sphere = SphereShape(segments: 256, rings: 128);
  final builtSphere = sphere.build();
  final sphereVertices = builtSphere.vertexCount;
  print('reference sphere: $sphereVertices vertices, '
      '${builtSphere.triangleCount} triangles');

  await bench(
    'SphereShape.build (256x128)',
    20,
    () async => sphere.build(),
    items: sphereVertices,
    unit: 'vertex',
  );

  await bench(
    'MeshData.signedVolume',
    20,
    () async => builtSphere.signedVolume(),
    items: builtSphere.triangleCount,
    unit: 'triangle',
  );

  final scale = Matrix4.diagonal3(Vector3(2.0, 0.5, 1.0));
  await bench(
    'MeshData.transformed (position + normal)',
    20,
    () async => builtSphere.transformed(scale),
    items: sphereVertices,
    unit: 'vertex',
  );
}
