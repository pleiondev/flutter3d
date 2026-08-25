/// The cube a surface reflects, convolved by roughness.
///
///     flutter test test/environment_map_test.dart
///
/// **A convolution has two ways to be wrong and only one of them is visible.**
/// It can blur too little or too much, which anybody notices; and its direction
/// mapping can disagree with the sampler's, which produces a cube that is
/// complete, seamless, and reflects the wrong half of the world. The second is
/// what most of this file is about.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

const int _size = 8;

/// Six faces, each a flat colour, so a direction's answer names its face.
List<ByteData> _colouredFaces([int side = _size]) {
  const colours = <List<int>>[
    <int>[255, 0, 0], // +X
    <int>[0, 255, 0], // −X
    <int>[0, 0, 255], // +Y
    <int>[255, 255, 0], // −Y
    <int>[255, 0, 255], // +Z
    <int>[0, 255, 255], // −Z
  ];
  return <ByteData>[
    for (final colour in colours)
      () {
        final face = ByteData(side * side * 4);
        for (var i = 0; i < side * side; i++) {
          face.setUint8(i * 4, colour[0]);
          face.setUint8(i * 4 + 1, colour[1]);
          face.setUint8(i * 4 + 2, colour[2]);
          face.setUint8(i * 4 + 3, 255);
        }
        return face;
      }(),
  ];
}

/// One texel of a level's face, as red, green, blue.
List<int> _texel(List<ByteData> faces, int face, int side, int x, int y) {
  final at = (y * side + x) * 4;
  return <int>[
    faces[face].getUint8(at),
    faces[face].getUint8(at + 1),
    faces[face].getUint8(at + 2),
  ];
}

void main() {
  group('a prefiltered environment', () {
    test('is a chain of halving levels, six faces each', () {
      // Mutation: halve the side before the first level instead of inside the
      // loop — the chain starts at a quarter and the upload refuses it, but by
      // then the failure is a null texture rather than a named size.
      final chain =
          EnvironmentMap.prefilter(_colouredFaces(), size: _size, levels: 3);

      expect(chain, isNotNull);
      expect(chain!, hasLength(3));
      var side = _size;
      for (final level in chain) {
        side = side ~/ 2;
        expect(level, hasLength(6), reason: 'a cube level has six faces');
        for (final face in level) {
          expect(face.lengthInBytes, side * side * 4,
              reason: 'level side should be $side');
        }
      }
    });

    test('and refuses input that is not six square faces', () {
      // The same refusal the upload makes, made earlier so the caller learns it
      // before a device is involved.
      expect(EnvironmentMap.prefilter(<ByteData>[], size: _size), isNull);
      expect(
          EnvironmentMap.prefilter(_colouredFaces().sublist(0, 5), size: _size),
          isNull);
      expect(EnvironmentMap.prefilter(_colouredFaces(), size: _size + 1),
          isNull);
    });

    test('and keeps each face nearest its own colour at the first level',
        () async {
      // **This is the seam check.** The convolution gathers along directions it
      // computes itself, and the sampler resolves directions to faces by its
      // own mapping; if the two disagree, +X ends up carrying −Z's colour and
      // the cube looks fine until somebody compares it with the source.
      //
      // Level one is blurred but not yet mixed across the whole sphere, so each
      // face's centre must still be dominated by its own colour.
      //
      // Mutation: transpose any two cases in `_directionFor`, or flip a sign in
      // one — the dominant channel moves to another face and this fails.
      final chain =
          EnvironmentMap.prefilter(_colouredFaces(), size: _size, levels: 3)!;
      final first = chain.first;
      const side = _size ~/ 2;
      const middle = side ~/ 2;

      // +X is pure red, so red must lead at the centre of face zero.
      final px = _texel(first, 0, side, middle, middle);
      expect(px[0], greaterThan(px[1]), reason: '+X should still read red');
      expect(px[0], greaterThan(px[2]), reason: '+X should still read red');

      // −X is pure green.
      final nx = _texel(first, 1, side, middle, middle);
      expect(nx[1], greaterThan(nx[0]), reason: '−X should still read green');

      // +Y is pure blue.
      final py = _texel(first, 2, side, middle, middle);
      expect(py[2], greaterThan(py[0]), reason: '+Y should still read blue');
    });

    test('and blurs further at every level', () {
      // A rougher level gathers a wider lobe, so a face's centre drifts towards
      // the average of the whole environment. Measured as distance from that
      // average rather than as a colour, which is what "further" means.
      //
      // Mutation: use the same roughness for every level — the two distances
      // come out equal and this fails.
      final chain =
          EnvironmentMap.prefilter(_colouredFaces(16), size: 16, levels: 4)!;

      double spreadOf(List<ByteData> level, int side) {
        final centre = _texel(level, 0, side, side ~/ 2, side ~/ 2);
        // The six faces average to (170, 170, 170) — each channel is full on
        // four of the six.
        return (centre[0] - 170).abs().toDouble() +
            (centre[1] - 170).abs() +
            (centre[2] - 170).abs();
      }

      final sharp = spreadOf(chain[0], 8);
      final rough = spreadOf(chain[3], 1);
      expect(rough, lessThan(sharp),
          reason: 'the roughest level is nearest the environment average');
    });

    test('and is the same bytes every time it is built', () {
      // **Nothing random in it.** The tap set is a fixed spiral, not a sampled
      // one, because a golden image compares bytes and a convolution seeded
      // from a clock would produce a different environment on every run.
      //
      // Mutation: replace the spiral with `Random()` draws — this fails, and
      // nothing else in the suite would.
      final first =
          EnvironmentMap.prefilter(_colouredFaces(), size: _size, levels: 2)!;
      final again =
          EnvironmentMap.prefilter(_colouredFaces(), size: _size, levels: 2)!;

      for (var level = 0; level < first.length; level++) {
        for (var face = 0; face < 6; face++) {
          expect(first[level][face].buffer.asUint8List(),
              equals(again[level][face].buffer.asUint8List()));
        }
      }
    });
  });
}
