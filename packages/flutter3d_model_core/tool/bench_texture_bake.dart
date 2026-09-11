// ignore_for_file: avoid_print — a command-line benchmark whose whole output
// is stdout.

/// `mat-11`'s own "замер 6 нод 2048² в doc" — a six-node graph baked at
/// 2048×2048, measured cold and cached, on the calling isolate and through
/// `bakeTextureFull`'s own `Isolate.run`.
///
///     dart run tool/bench_texture_bake.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';

Uint8List _chunk(String type, List<int> data) {
  final out = BytesBuilder();
  out.add(
    (ByteData(4)..setUint32(0, data.length, Endian.big)).buffer.asUint8List(),
  );
  out.add(ascii.encode(type));
  out.add(data);
  out.add(const <int>[0, 0, 0, 0]);
  return out.toBytes();
}

/// A 64×64 chequer PNG, stored (uncompressed) — big enough to make the
/// `Image` node's own resample worth measuring, small enough to build
/// without a real encoder.
Uint8List _checkerPng(int side) {
  final row = Uint8List(side * 4);
  for (var x = 0; x < side; x++) {
    final on = (x ~/ 8).isEven;
    row[x * 4] = on ? 220 : 30;
    row[x * 4 + 1] = on ? 220 : 30;
    row[x * 4 + 2] = on ? 220 : 30;
    row[x * 4 + 3] = 255;
  }
  final scanlines = BytesBuilder();
  for (var y = 0; y < side; y++) {
    scanlines.addByte((y ~/ 8).isEven ? 0 : 1); // filter: None, or Sub
    scanlines.add(row);
  }
  final out = BytesBuilder();
  out.add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = ByteData(13)
    ..setUint32(0, side)
    ..setUint32(4, side)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  out.add(_chunk('IHDR', ihdr.buffer.asUint8List()));
  out.add(_chunk('IDAT', ZLibCodec().encode(scanlines.toBytes())));
  out.add(_chunk('IEND', const <int>[]));
  return out.toBytes();
}

/// Six nodes, the row's own count: `Image`, `Noise`, `NormalFromHeight`,
/// `Checker`, `Blend`, `Output`.
TextureGraph sixNodes() => TextureGraph(
  nodes: <TextureNode>[
    const ImageTextureNode(id: 1, imageId: 0),
    const NoiseTextureNode(id: 2, seed: 11, scale: 6),
    NormalFromHeightTextureNode(id: 3, height: 2, strength: 2.0),
    CheckerTextureNode(id: 4, scale: 16),
    BlendTextureNode(id: 5, base: 1, overlay: 3, factor: 0.4),
    const OutputTextureNode(id: 6, result: 5),
  ],
);

Future<double> milliseconds(int runs, Future<void> Function() body) async {
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    await body();
  }
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds / runs / 1000.0;
}

void main() async {
  const size = 2048;
  final graph = sixNodes();
  final images = <int, Uint8List>{0: _checkerPng(64)};
  print('six nodes, ${size}x$size, RGBA8 output (${size * size * 4} bytes)');
  print('');

  final cold = await milliseconds(1, () async {
    bakeTextureGraph(graph, 6, images, size: size, cache: TextureBakeCache());
  });
  print('cold (fresh cache)              ${cold.toStringAsFixed(1)} ms');

  final warmCache = TextureBakeCache();
  bakeTextureGraph(graph, 6, images, size: size, cache: warmCache);
  final warm = await milliseconds(3, () async {
    bakeTextureGraph(graph, 6, images, size: size, cache: warmCache);
  });
  print('warm (same graph, same cache)   ${warm.toStringAsFixed(1)} ms');

  final viaIsolate = await milliseconds(3, () async {
    await bakeTextureFull(graph, 6, images, size: size);
  });
  print('through bakeTextureFull         ${viaIsolate.toStringAsFixed(1)} ms');
}
