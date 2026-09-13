// ignore_for_file: avoid_print — a command-line tool whose whole output is
// stdout, meant to be piped into a file.

/// `fmt-30n`'s own one-time ground-truth check for the index codec — see
/// `meshopt_reference_vectors.dart`'s own top comment; this is the same
/// idea, for `meshopt_index_codec.dart` instead.
///
///     dart run tool/meshopt_index_reference_vectors.dart > /tmp/meshopt_index_vectors.json
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter3d_formats/src/meshopt/meshopt_index_codec.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _grid(int rows, int cols) => <int>[
  for (var row = 0; row < rows; row++)
    for (var col = 0; col < cols; col++) ...<int>[
      row * (cols + 1) + col,
      row * (cols + 1) + col + 1,
      (row + 1) * (cols + 1) + col,
      (row + 1) * (cols + 1) + col,
      row * (cols + 1) + col + 1,
      (row + 1) * (cols + 1) + col + 1,
    ],
];

void main() {
  final random = Random(9);
  final cases = <Map<String, Object?>>[
    for (final entry in <(String, List<int>)>[
      ('single triangle', <int>[0, 1, 2]),
      ('quad, shared edge', <int>[0, 1, 2, 0, 2, 3]),
      ('a 20x20 grid', _grid(20, 20)),
      ('a 40x40 grid', _grid(40, 40)),
      (
        'random indices',
        <int>[for (var i = 0; i < 300; i++) random.nextInt(1 << 20)],
      ),
      ('degenerate, all zero', <int>[for (var i = 0; i < 30; i++) 0]),
      ('empty', <int>[]),
    ])
      {
        'label': entry.$1,
        'count': entry.$2.length,
        'indices': entry.$2,
        'encodedHex': _hex(encodeMeshoptIndexBuffer(entry.$2)),
      },
  ];

  print(jsonEncode(cases));
}
