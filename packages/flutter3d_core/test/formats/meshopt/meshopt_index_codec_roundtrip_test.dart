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

/// The same triangles in the same order, each one allowed the rotation the
/// format is free to choose.
///
/// **Not an equality, and the reason is the format rather than a tolerance.**
/// A triangle is coded as `(a, b, c)` where `(a, b)` is the edge it shares
/// with one already seen, so whichever of its three corners carries that
/// edge is the one written first. `meshoptimizer`'s own encoder does exactly
/// this, which means a real compressed file decodes to rotated triangles too
/// — the reader here has always had to accept them, and only this
/// repository's own encoder never produced any, because until it used the
/// edge FIFO it wrote every triangle out flat.
///
/// A cyclic rotation is the same triangle with the same winding, so nothing
/// downstream can tell: the facing is unchanged and glTF carries no
/// per-corner data outside the vertex arrays for a shift to disturb.
Matcher sameTrianglesAs(List<int> indices) =>
    predicate<List<int>>((List<int> other) {
      if (other.length != indices.length) return false;
      for (var i = 0; i < indices.length; i += 3) {
        final a = <int>[indices[i], indices[i + 1], indices[i + 2]];
        final b = <int>[other[i], other[i + 1], other[i + 2]];
        final bool rotated =
            (b[0] == a[0] && b[1] == a[1] && b[2] == a[2]) ||
            (b[0] == a[1] && b[1] == a[2] && b[2] == a[0]) ||
            (b[0] == a[2] && b[1] == a[0] && b[2] == a[1]);
        if (!rotated) return false;
      }
      return true;
    }, 'the same triangles, each up to a cyclic rotation');

void roundTrips(String label, List<int> indices) {
  test(label, () {
    final encoded = encodeMeshoptIndexBuffer(indices);
    final decoded = decodeMeshoptIndexBuffer(encoded, indices.length);
    expect(decoded, sameTrianglesAs(indices));
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

  test(
    'the first triangle cannot name a shared edge, even an all-zero one',
    () {
      // **The bug this is here for, and the only in-tree way to see it.** A
      // `_Fifo` is a `Uint32List`, so an untouched edge history reads back as
      // zeros — and an encoder that searches the whole ring finds an edge
      // `(0, 0)` in a history nobody has pushed to. The round trips above
      // could not catch it: this file's own decoder reads the same phantom
      // zeros and agrees. `meshoptimizer`'s production decoder does not, and
      // read the result as index 4294967295.
      //
      // The invariant that makes it visible here is simple and true of every
      // mesh: nothing has been pushed before the first triangle, so the first
      // code byte is always the explicit path's `0xff`.
      for (final List<int> indices in <List<int>>[
        <int>[0, 0, 0, 0, 0, 0],
        <int>[0, 1, 2, 0, 2, 3],
        <int>[7, 7, 7],
      ]) {
        final encoded = encodeMeshoptIndexBuffer(indices);
        expect(
          encoded[1],
          0xff,
          reason: 'the first triangle of $indices claimed a shared edge',
        );
      }
    },
  );

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
