// ignore_for_file: avoid_print — a command-line tool whose whole output is
// stdout, meant to be piped into a file.

/// `fmt-30n`'s own one-time ground-truth check: writes a handful of vectors
/// this package's encoder produced, for `meshopt_reference_check.mjs` to
/// decode with the reference JS decoder this repository did not write and
/// compare byte-for-byte against what was actually asked to be encoded.
///
/// Not part of the regular test suite — it shells out to Node, which the
/// rest of this repository's tests do not require — see the commit this
/// file landed in for the one recorded run of the check it feeds.
///
///     dart run tool/meshopt_reference_vectors.dart > /tmp/meshopt_vectors.json
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter3d_formats/src/meshopt/meshopt_vertex_codec.dart';

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _randomBytes(int length, Random random) => Uint8List.fromList(<int>[
  for (var i = 0; i < length; i++) random.nextInt(256),
]);

Uint8List _coherentPositions(int count) => Uint8List.fromList(<int>[
  for (var i = 0; i < count; i++)
    ...(() {
      final bytes = ByteData(12);
      bytes.setFloat32(0, 1.0 + i * 0.001, Endian.little);
      bytes.setFloat32(4, 2.0 - i * 0.0005, Endian.little);
      bytes.setFloat32(8, i * 0.01, Endian.little);
      return bytes.buffer.asUint8List();
    })(),
]);

void main() {
  final cases = <Map<String, Object?>>[
    for (final entry in <(String, Uint8List, int, int)>[
      ('all zero, 16x12', Uint8List(16 * 12), 16, 12),
      ('random, 500x4', _randomBytes(500 * 4, Random(1)), 500, 4),
      ('random, 120x32', _randomBytes(120 * 32, Random(2)), 120, 32),
      ('random, 300x1', _randomBytes(300 * 1, Random(3)), 300, 1),
      ('coherent positions, 1000x12', _coherentPositions(1000), 1000, 12),
      ('short, 3x4', _randomBytes(3 * 4, Random(4)), 3, 4),
      ('short, 17x8', _randomBytes(17 * 8, Random(5)), 17, 8),
      (
        'spanning two blocks, 700x12',
        _randomBytes(700 * 12, Random(6)),
        700,
        12,
      ),
      ('single element, 1x12', _randomBytes(1 * 12, Random(7)), 1, 12),
      ('zero elements, 0x12', Uint8List(0), 0, 12),
    ])
      {
        'label': entry.$1,
        'elementCount': entry.$3,
        'byteStride': entry.$4,
        'sourceHex': _hex(entry.$2),
        'encodedHex': _hex(
          encodeMeshoptVertexBufferV0(entry.$2, entry.$3, entry.$4),
        ),
      },
  ];

  print(jsonEncode(cases));
}
