/// `.cube` colour tables read into the strip the composite grades through —
/// `P2`.
///
///     dart test test/formats/cube_lut_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

/// A 3D table of [size] whose entry is what [map] makes of its input.
String _cube(
  int size,
  (double, double, double) Function(double r, double g, double b) map, {
  String header = '',
}) {
  final out = StringBuffer()
    ..writeln('# written by a test')
    ..writeln('TITLE "test table"')
    ..write(header)
    ..writeln('LUT_3D_SIZE $size');
  final last = size - 1;
  for (var b = 0; b < size; b++) {
    for (var g = 0; g < size; g++) {
      for (var r = 0; r < size; r++) {
        final (x, y, z) = map(r / last, g / last, b / last);
        out.writeln('$x $y $z');
      }
    }
  }
  return out.toString();
}

void main() {
  test('the identity table is the identity strip, byte for byte', () {
    // Mutation: run green fastest instead of red in `lookup`, and the strip
    // comes out transposed.
    final lut = CubeLut.parse(_cube(17, (r, g, b) => (r, g, b)));
    expect(lut.title, 'test table');
    expect(lut.size, 17);
    expect(lut.toStrip(), buildIdentityLut(size: 17));
  });

  test('uploads as the strip the composite grades through', () {
    final lut = CubeLut.parse(_cube(17, (r, g, b) => (r, g, b)));
    final texture = lut.upload(FakeBackend())!;
    expect(texture.width, 17 * 17);
    expect(texture.height, 17);
  });

  test('a table is resampled into a strip of another size', () {
    final lut = CubeLut.parse(_cube(9, (r, g, b) => (r, g, b)));
    expect(lut.toStrip(stripSize: 33), buildIdentityLut());
  });

  test('entries are interpolated between, and red runs fastest', () {
    // Swaps red and blue: a channel-order mistake reads as this table being
    // the identity.
    final lut = CubeLut.parse(_cube(2, (r, g, b) => (b, g, r)));
    final (r, g, b) = lut.lookup(0.25, 0.5, 0.75);
    expect(r, closeTo(0.75, 1e-6));
    expect(g, closeTo(0.5, 1e-6));
    expect(b, closeTo(0.25, 1e-6));
  });

  test('a domain wider than the unit cube is mapped onto it', () {
    final lut = CubeLut.parse(
      _cube(
        2,
        (r, g, b) => (r, g, b),
        header: 'DOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2\n',
      ),
    );
    // Input 1 is halfway along a domain of 0…2.
    expect(lut.lookup(1.0, 1.0, 1.0).$1, closeTo(0.5, 1e-6));
    // Past the edge is held to it.
    expect(lut.lookup(3.0, 3.0, 3.0).$1, closeTo(1.0, 1e-6));
  });

  test('a 1D table is three curves', () {
    const text = '''
LUT_1D_SIZE 3
0 0 0
0.25 0.5 0.75
1 1 1
''';
    final lut = CubeLut.parse(text);
    expect(lut.isOneD, isTrue);
    final (r, g, b) = lut.lookup(0.5, 0.5, 0.5);
    expect(r, closeTo(0.25, 1e-6));
    expect(g, closeTo(0.5, 1e-6));
    expect(b, closeTo(0.75, 1e-6));
    expect(lut.toStrip().length, 33 * 33 * 33 * 4);
  });

  group('refuses', () {
    test('a table with no size', () {
      expect(
        () => CubeLut.parse('0 0 0\n1 1 1\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('a table with the wrong number of entries', () {
      expect(
        () => CubeLut.parse('LUT_3D_SIZE 2\n0 0 0\n1 1 1\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('expected 8 entries'),
          ),
        ),
      );
    });

    test('a line that is not three numbers, naming it', () {
      expect(
        () => CubeLut.parse('LUT_1D_SIZE 2\n0 0 0\n1 one 1\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('line 3'),
          ),
        ),
      );
    });

    test('an empty domain', () {
      expect(
        () => CubeLut.parse(
          'LUT_1D_SIZE 2\nDOMAIN_MIN 1 1 1\nDOMAIN_MAX 1 1 1\n0 0 0\n1 1 1\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
