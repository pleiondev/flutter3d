// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter3d/src/engine/assets/gltf/gltf.dart';

Future<void> main(List<String> args) async {
  for (final path in args) {
    final bytes = File(path).readAsBytesSync();
    final watch = Stopwatch()..start();
    final asset = await GltfLoader().load(bytes);
    watch.stop();
    var tris = 0, verts = 0, vbytes = 0, ibytes = 0;
    for (final surface in asset.surfaces) {
      tris += surface.mesh.triangleCount;
      verts += surface.mesh.vertexCount;
      vbytes += surface.mesh.vertices.lengthInBytes;
      ibytes += surface.mesh.indices.lengthInBytes;
    }
    final images = asset.images.fold<int>(0, (a, i) => a + i.bytes.length);
    print(
      '${path.split('/').last.padRight(24)} '
      '${(bytes.length / 1e6).toStringAsFixed(2)} MB file  '
      '${tris.toString().padLeft(8)} tris  '
      '${verts.toString().padLeft(8)} verts  '
      'gpu ${((vbytes + ibytes) / 1e6).toStringAsFixed(1)} MB  '
      'tex ${(images / 1e6).toStringAsFixed(1)} MB  '
      'decode ${watch.elapsedMilliseconds} ms',
    );
  }
}
