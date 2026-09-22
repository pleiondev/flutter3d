/// `fmt-30n`'s own vertex codec, checked against itself first — every one
/// of these round-trips through [encodeMeshoptVertexBufferV0] and back
/// through [decodeMeshoptVertexBufferV0] and must land on the exact bytes
/// it started from. This is necessary, not sufficient: `meshopt_vertex_codec_reference_test.dart`
/// is what checks this file's own encoder against a decoder this repository
/// did not write.
///
///     dart test test/meshopt/meshopt_vertex_codec_roundtrip_test.dart
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter3d_core/src/formats/meshopt/meshopt_vertex_codec.dart';
import 'package:test/test.dart';

void roundTrips(
  String label,
  Uint8List source,
  int elementCount,
  int byteStride,
) {
  test(label, () {
    final encoded = encodeMeshoptVertexBufferV0(
      source,
      elementCount,
      byteStride,
    );
    final decoded = decodeMeshoptVertexBufferV0(
      encoded,
      elementCount,
      byteStride,
    );
    expect(decoded, source, reason: 'round trip must be byte-exact');
    expect(encoded[0], kMeshoptVertexHeaderV0);
  });
}

Uint8List randomBytes(int length, Random random) => Uint8List.fromList(<int>[
  for (var i = 0; i < length; i++) random.nextInt(256),
]);

void main() {
  group('the shapes a single group can take', () {
    roundTrips('all zero', Uint8List(16 * 12), 16, 12);

    roundTrips(
      'small deltas throughout (2-bit territory)',
      Uint8List.fromList(<int>[
        for (var i = 0; i < 16; i++) ...<int>[i % 3, (i * 2) % 3, 0, 0],
      ]),
      16,
      4,
    );

    roundTrips(
      'medium deltas throughout (4-bit territory)',
      Uint8List.fromList(<int>[
        for (var i = 0; i < 16; i++) ...<int>[(i * 5) % 16, 0, 0, 0],
      ]),
      16,
      4,
    );

    roundTrips(
      'wild swings that force verbatim',
      Uint8List.fromList(<int>[
        for (var i = 0; i < 16; i++) ...<int>[
          (i * 97) % 256,
          (i * 211) % 256,
          0,
          0,
        ],
      ]),
      16,
      4,
    );

    roundTrips(
      'one escape among small deltas',
      Uint8List.fromList(<int>[
        for (var i = 0; i < 16; i++) ...<int>[i == 7 ? 200 : 1, 0, 0, 0],
      ]),
      16,
      4,
    );
  });

  group('block and group boundaries', () {
    roundTrips(
      'exactly one group (16 elements)',
      randomBytes(16 * 8, Random(1)),
      16,
      8,
    );
    roundTrips(
      'a short last group (17 elements)',
      randomBytes(17 * 8, Random(2)),
      17,
      8,
    );
    roundTrips('a single element', randomBytes(1 * 12, Random(3)), 1, 12);
    roundTrips(
      'a short first-and-only group (3 elements)',
      randomBytes(3 * 4, Random(4)),
      3,
      4,
    );

    // maxBlockElements for byteStride=12 is min((0x2000/12)&~0xf, 0x100) = 672;
    // this exercises a real block boundary, not just a group one.
    roundTrips(
      'more elements than one block holds (byteStride 12)',
      randomBytes(700 * 12, Random(5)),
      700,
      12,
    );

    // A tiny byteStride pushes maxBlockElements to its own cap (0x100).
    roundTrips(
      'more elements than one block holds (byteStride 1)',
      randomBytes(300 * 1, Random(6)),
      300,
      1,
    );
  });

  group('real vertex shapes', () {
    roundTrips(
      'Vector3 positions, locally coherent (a line of points)',
      Uint8List.fromList(<int>[
        for (var i = 0; i < 200; i++)
          ...(() {
            final bytes = ByteData(12);
            bytes.setFloat32(0, i * 0.01, Endian.little);
            bytes.setFloat32(4, 1.0, Endian.little);
            bytes.setFloat32(8, -i * 0.005, Endian.little);
            return bytes.buffer.asUint8List();
          })(),
      ]),
      200,
      12,
    );

    roundTrips(
      'random bytes, 4-byte stride',
      randomBytes(500 * 4, Random(7)),
      500,
      4,
    );
    roundTrips(
      'random bytes, 32-byte stride',
      randomBytes(120 * 32, Random(8)),
      120,
      32,
    );
    roundTrips('zero elements', Uint8List(0), 0, 12);
  });

  test('a wrong header byte is refused, not silently misread', () {
    final bad = Uint8List.fromList(<int>[0xff, ...List<int>.filled(31, 0)]);
    expect(
      () => decodeMeshoptVertexBufferV0(bad, 0, 12),
      throwsFormatException,
    );
  });

  test('encode refuses a source of the wrong length', () {
    expect(
      () => encodeMeshoptVertexBufferV0(Uint8List(10), 1, 12),
      throwsArgumentError,
    );
  });

  test('compression actually compresses a coherent stream', () {
    // 1000 near-identical Vector3s: the whole point of this codec.
    final source = Uint8List.fromList(<int>[
      for (var i = 0; i < 1000; i++)
        ...(() {
          final bytes = ByteData(12);
          bytes.setFloat32(0, 1.0 + i * 0.0001, Endian.little);
          bytes.setFloat32(4, 2.0, Endian.little);
          bytes.setFloat32(8, 3.0 - i * 0.0001, Endian.little);
          return bytes.buffer.asUint8List();
        })(),
    ]);
    final encoded = encodeMeshoptVertexBufferV0(source, 1000, 12);
    expect(
      encoded.length,
      lessThan(source.length ~/ 2),
      reason: 'locally coherent floats should compress well under half size',
    );
  });
}
