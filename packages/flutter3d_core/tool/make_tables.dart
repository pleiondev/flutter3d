/// Writes the engine's data tables — `G1`.
///
///     dart run tool/make_tables.dart
///
/// A table is bytes a shader samples that nobody should compute at startup:
/// blue noise today, the LTC fit and the sheen albedo later. Each is written
/// once, here, into a Dart file under `lib/src/engine/render/tables/`, so the
/// software rasteriser and the GPUs sample the same bytes and a test can pin
/// them by hash. Running this again writes the same files: every choice below
/// is seeded.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const String _out = 'lib/src/engine/render/tables';

void main() {
  final noise = blueNoiseSlices(size: 64, slices: 32);
  _write(
    'blue_noise.dart',
    name: 'blueNoise',
    doc: '''
/// 32 slices of 64×64 blue noise, one byte a texel, laid out as an 8×4 atlas
/// of slices (512×256, slice `i` at column `i % 8`, row `i ~/ 8`).
///
/// Each slice is its own void-and-cluster ranking (Ulichney 1993) on a torus,
/// with a Gaussian of σ = 1.5 texels, so it tiles. Every value 0–255 occurs
/// exactly sixteen times in a slice. Slices are seeded independently: a
/// temporal effect steps through them by `Renderer.frameIndex % 32`.''',
    width: 512,
    height: 256,
    format: 'r8UNormInt',
    bytes: _atlas(noise, size: 64, columns: 8, rows: 4),
  );
}

/// [slices] rankings of a [size]×[size] torus, each as bytes 0–255.
List<Uint8List> blueNoiseSlices({required int size, required int slices}) => [
  for (var s = 0; s < slices; s++) _voidAndCluster(size, seed: 0x5eed + s),
];

Uint8List _atlas(
  List<Uint8List> slices, {
  required int size,
  required int columns,
  required int rows,
}) {
  final width = size * columns;
  final out = Uint8List(width * size * rows);
  for (var s = 0; s < slices.length; s++) {
    final x0 = (s % columns) * size;
    final y0 = (s ~/ columns) * size;
    for (var y = 0; y < size; y++) {
      out.setRange(
        (y0 + y) * width + x0,
        (y0 + y) * width + x0 + size,
        slices[s],
        y * size,
      );
    }
  }
  return out;
}

/// One void-and-cluster ranking, mapped to bytes.
Uint8List _voidAndCluster(int size, {required int seed}) {
  final n = size * size;
  final kernel = _gaussian(size, sigma: 1.5);
  final random = math.Random(seed);

  // The energy a set of points puts on every texel, kept incrementally: a
  // point switched on adds the kernel centred on it, one switched off takes
  // it away.
  final energy = Float64List(n);
  final on = List<bool>.filled(n, false);
  void toggle(int p, {required bool set}) {
    on[p] = set;
    final sign = set ? 1.0 : -1.0;
    final px = p % size;
    final py = p ~/ size;
    for (var y = 0; y < size; y++) {
      final ky = ((y - py) % size) * size;
      for (var x = 0; x < size; x++) {
        energy[y * size + x] += sign * kernel[ky + (x - px) % size];
      }
    }
  }

  int extreme({required bool ofOn, required bool highest}) {
    var best = -1;
    for (var p = 0; p < n; p++) {
      if (on[p] != ofOn) continue;
      if (best < 0 ||
          (highest ? energy[p] > energy[best] : energy[p] < energy[best])) {
        best = p;
      }
    }
    return best;
  }

  // A tenth of the texels, at random, relaxed until moving the most crowded
  // point into the emptiest gap puts it back where it was.
  final initial = n ~/ 10;
  for (var placed = 0; placed < initial;) {
    final p = random.nextInt(n);
    if (on[p]) continue;
    toggle(p, set: true);
    placed++;
  }
  while (true) {
    final cluster = extreme(ofOn: true, highest: true);
    toggle(cluster, set: false);
    final gap = extreme(ofOn: false, highest: false);
    toggle(gap, set: true);
    if (gap == cluster) break;
  }

  final rank = Int32List(n);
  final prototype = List<bool>.of(on);
  final prototypeEnergy = Float64List.fromList(energy);

  // Down from the prototype: the most crowded point goes first and ranks
  // highest among what is left.
  for (var left = initial; left > 0; left--) {
    final cluster = extreme(ofOn: true, highest: true);
    toggle(cluster, set: false);
    rank[cluster] = left - 1;
  }

  // Up from the prototype: the emptiest gap is filled next.
  on.setAll(0, prototype);
  energy.setAll(0, prototypeEnergy);
  for (var filled = initial; filled < n; filled++) {
    final gap = extreme(ofOn: false, highest: false);
    toggle(gap, set: true);
    rank[gap] = filled;
  }

  return Uint8List.fromList([for (final r in rank) r * 256 ~/ n]);
}

/// A toroidal Gaussian, indexed by `dy * size + dx` with both wrapped.
Float64List _gaussian(int size, {required double sigma}) {
  final kernel = Float64List(size * size);
  for (var y = 0; y < size; y++) {
    final dy = math.min(y, size - y);
    for (var x = 0; x < size; x++) {
      final dx = math.min(x, size - x);
      kernel[y * size + x] = math.exp(
        -(dx * dx + dy * dy) / (2 * sigma * sigma),
      );
    }
  }
  return kernel;
}

void _write(
  String file, {
  required String name,
  required String doc,
  required int width,
  required int height,
  required String format,
  required Uint8List bytes,
}) {
  final encoded = base64.encode(bytes);
  final lines = [
    for (var i = 0; i < encoded.length; i += 76)
      "    '${encoded.substring(i, math.min(i + 76, encoded.length))}'",
  ];
  File('$_out/$file')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
// GENERATED by tool/make_tables.dart. Do not edit by hand.
//
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../engine_table.dart';

$doc
const EngineTable $name = EngineTable(
  name: '$name',
  width: $width,
  height: $height,
  format: TextureFormat.$format,
  base64:
${lines.join('\n')},
);
''');
  stdout.writeln('wrote $_out/$file (${bytes.length} bytes)');
}
