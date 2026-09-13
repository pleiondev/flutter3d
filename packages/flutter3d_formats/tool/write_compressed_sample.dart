// ignore_for_file: avoid_print — a command-line tool.

/// `fmt-30n`'s own one-time Khronos-validator check: writes a compressed
/// GLB to disk for `node` + `gltf-validator` (this repository's tree does
/// not carry either) to check independently.
///
///     dart run tool/write_compressed_sample.dart /tmp/compressed.glb
library;

import 'dart:io';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';

void main(List<String> args) {
  final mesh = SphereShape(segments: 32, rings: 16).build();
  final document = PlainModelDocument(
    surfaces: [ModelSurface(mesh: mesh)],
    nodes: [
      ModelNode(surfaces: const [0]),
    ],
  );
  final bytes = GltfWriter(document, compressGeometry: true).writeGlb();
  File(args[0]).writeAsBytesSync(bytes);
  print('wrote ${bytes.length} bytes to ${args[0]}');
}
