// ignore_for_file: avoid_print — see bench.dart.

import 'dart:io';

import 'package:flutter3d/src/engine/assets/f3d/f3d.dart';
import 'package:flutter3d/src/engine/assets/gltf/gltf.dart';
import 'package:flutter3d/src/engine/assets/obj/obj.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';

import 'bench_util.dart';

/// Decoding cost for OBJ, glTF/GLB and the engine's own `.f3d` container.
Future<void> benchAssetDecoding() async {
  final teapotBytes = File('$kSamplesPath/teapot.obj').readAsBytesSync();
  final glbBytes = File('$kSamplesPath/BoxTextured.glb').readAsBytesSync();

  print('--- asset decoding -----------------------------------------------');

  final teapotDoc = await ObjLoader().load(teapotBytes);
  final teapotTriangles = teapotDoc.triangleCount;

  await bench(
    'OBJ teapot, full load (smooth normals)',
    40,
    () => ObjLoader().load(teapotBytes),
    items: teapotTriangles,
    unit: 'triangle',
  );

  await bench(
    'OBJ teapot, normals disabled',
    40,
    () => ObjLoader(normals: ObjNormals.none).load(teapotBytes),
    items: teapotTriangles,
    unit: 'triangle',
  );

  await bench(
    'GLB BoxTextured, full load',
    200,
    () => GltfLoader().load(glbBytes),
  );

  // The same geometry through the engine's own container. `.f3d` exists for
  // exactly this comparison: the parse happens once, offline, and the runtime
  // is left holding views over bytes it already has.
  final teapotF3d = F3dWriter(teapotDoc).write();
  await bench(
    'F3D teapot, header only',
    2000,
    () async => F3dDocument.parse(teapotF3d),
    items: teapotTriangles,
    unit: 'triangle',
  );

  await bench(
    'F3D teapot, full load (every array touched)',
    2000,
    () async {
      // What ModelAsset.fromDocument actually reaches for. Without it this
      // would only measure the header, since the rest is lazy — and a
      // "0.1 us load" that decodes nothing is not a measurement, it is a
      // rounding error with a headline.
      final document = F3dDocument.parse(teapotF3d);
      var total = 0;
      for (final surface in document.surfaces) {
        total += surface.mesh.vertices.length + surface.mesh.indices.length;
      }
      if (total == 0) throw StateError('nothing loaded');
    },
    items: teapotTriangles,
    unit: 'triangle',
  );
}
