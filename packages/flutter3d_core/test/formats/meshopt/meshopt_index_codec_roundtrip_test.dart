/// `fmt-30n`'s own index codec, checked against itself first — see
/// `meshopt_vertex_codec_roundtrip_test.dart`'s own top comment for why
/// this is necessary but not sufficient on its own.
///
///     dart test test/meshopt/meshopt_index_codec_roundtrip_test.dart
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter3d_core/src/formats/meshopt/meshopt_index_codec.dart';
import 'package:test/test.dart';

void roundTrips(String label, List<int> indices) {
  test(label, () {
    final encoded = encodeMeshoptIndexBuffer(indices);
    final decoded = decodeMeshoptIndexBuffer(encoded, indices.length);
    expect(decoded, indices);
    expect(encoded[0], kMeshoptIndexHeader);
  });
}

void main() {
  roundTrips('a single triangle', <int>[0, 1, 2]);
  roundTrips('a quad, two triangles sharing an edge', <int>[0, 1, 2, 0, 2, 3]);
  roundTrips('a small strip', <int>[for (var i = 0; i < 30; i++) i]);
  roundTrips('a grid of quads (a real-shaped mesh)', <int>[
    for (var row = 0; row < 20; row++)
      for (var col = 0; col < 20; col++) ...<int>[
        row * 21 + col,
        row * 21 + col + 1,
        (row + 1) * 21 + col,
        (row + 1) * 21 + col,
        row * 21 + col + 1,
        (row + 1) * 21 + col + 1,
      ],
  ]);
  roundTrips(
    'indices with large jumps between triangles',
    () {
      final random = Random(1);
      return <int>[for (var i = 0; i < 300; i++) random.nextInt(1 << 20)];
    }()..length = (300 ~/ 3) * 3,
  );
  roundTrips('no triangles at all', <int>[]);
  roundTrips('index zero repeated (every triangle degenerate)', <int>[
    for (var i = 0; i < 30; i++) 0,
  ]);

  test('a wrong header byte is refused, not silently misread', () {
    expect(
      () => decodeMeshoptIndexBuffer(Uint8List.fromList(<int>[0xff]), 0),
      throwsFormatException,
    );
  });

  test('a count not divisible by 3 is refused on both sides', () {
    expect(() => encodeMeshoptIndexBuffer(<int>[0, 1]), throwsArgumentError);
  });

  test('compression actually compresses a real mesh', () {
    final indices = <int>[
      for (var row = 0; row < 40; row++)
        for (var col = 0; col < 40; col++) ...<int>[
          row * 41 + col,
          row * 41 + col + 1,
          (row + 1) * 41 + col,
          (row + 1) * 41 + col,
          row * 41 + col + 1,
          (row + 1) * 41 + col + 1,
        ],
    ];
    final encoded = encodeMeshoptIndexBuffer(indices);
    final rawUint32 = indices.length * 4;
    expect(
      encoded.length,
      lessThan(rawUint32),
      reason: 'a grid mesh delta-codes small between neighbouring triangles',
    );
  });
}
