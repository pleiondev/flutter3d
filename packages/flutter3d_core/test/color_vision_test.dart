/// Colour vision: the picture as someone missing a cone sees it, and the
/// picture moved for them, both as the colour table the composite reads.
///
///     flutter test test/color_vision_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

double _distance((double, double, double) a, (double, double, double) b) =>
    math.sqrt(
      (a.$1 - b.$1) * (a.$1 - b.$1) +
          (a.$2 - b.$2) * (a.$2 - b.$2) +
          (a.$3 - b.$3) * (a.$3 - b.$3),
    );

void main() {
  test('at no severity the table is the neutral one, byte for byte', () {
    // Mutation: blending towards the deficiency by one minus the severity.
    for (final kind in ColorVisionDeficiency.values) {
      expect(
        ColorVision.simulate(kind, severity: 0.0).toStrip(size: 17),
        buildIdentityLut(size: 17),
        reason: '$kind',
      );
      expect(
        ColorVision.correct(kind, severity: 0.0).toStrip(size: 17),
        buildIdentityLut(size: 17),
      );
    }
  });

  test('white and black stay what they are, whoever is looking', () {
    for (final kind in ColorVisionDeficiency.values) {
      for (final vision in <ColorVision>[
        ColorVision.simulate(kind),
        ColorVision.correct(kind),
      ]) {
        final (r, g, b) = vision.applyLinear(1.0, 1.0, 1.0);
        expect(<double>[r, g, b], everyElement(closeTo(1.0, 1e-3)));
        expect(vision.applyLinear(0.0, 0.0, 0.0), (0.0, 0.0, 0.0));
      }
    }
  });

  test(
    'missing a red or green cone, red and green differ only in lightness',
    () {
      // A red-green dichromat sees along a blue-yellow axis: red and green land
      // on the same hue, red darker. So the ratio of red to green in what they
      // see is the same for both, where for anybody else it is nothing alike.
      // Mutation: a matrix that is not the paper's — a transposed one, say.
      for (final kind in <ColorVisionDeficiency>[
        ColorVisionDeficiency.protan,
        ColorVisionDeficiency.deutan,
      ]) {
        final vision = ColorVision.simulate(kind);
        final red = vision.applyLinear(0.8, 0.1, 0.05);
        final green = vision.applyLinear(0.1, 0.8, 0.05);
        expect(
          red.$1 / red.$2,
          closeTo(green.$1 / green.$2, 0.15),
          reason: '$kind',
        );
      }
    },
  );

  test('corrected, the colours each runs together are told further apart', () {
    // Each deficiency's own pair: red and green for the two red-green ones,
    // blue and green for the blue one. Shown to the same eyes as they were
    // and corrected first, the corrected pair is further apart: nearly twice
    // for a deutan or a tritan, a seventh for a protan, to whom red is dark
    // and there is little of it left to move.
    // Mutation: adding the error back unshifted, which is the identity.
    final pairs = <ColorVisionDeficiency, List<(double, double, double)>>{
      ColorVisionDeficiency.protan: <(double, double, double)>[
        (0.8, 0.15, 0.1),
        (0.15, 0.6, 0.1),
      ],
      ColorVisionDeficiency.deutan: <(double, double, double)>[
        (0.8, 0.15, 0.1),
        (0.15, 0.6, 0.1),
      ],
      ColorVisionDeficiency.tritan: <(double, double, double)>[
        (0.1, 0.3, 0.8),
        (0.1, 0.6, 0.3),
      ],
    };
    for (final MapEntry(key: kind, value: pair) in pairs.entries) {
      final sees = ColorVision.simulate(kind);
      final fixes = ColorVision.correct(kind);
      final (a, b) = (pair[0], pair[1]);
      final plain = _distance(
        sees.applyLinear(a.$1, a.$2, a.$3),
        sees.applyLinear(b.$1, b.$2, b.$3),
      );
      final ca = fixes.applyLinear(a.$1, a.$2, a.$3);
      final cb = fixes.applyLinear(b.$1, b.$2, b.$3);
      final corrected = _distance(
        sees.applyLinear(ca.$1, ca.$2, ca.$3),
        sees.applyLinear(cb.$1, cb.$2, cb.$3),
      );
      expect(corrected, greaterThan(plain * 1.1), reason: '$kind');
    }
  });

  test('a game\'s own grade is applied first, then the vision', () {
    // A grade that turns everything to its negative: the table's corner at
    // black holds what the vision makes of white.
    final negative = CubeLut.parse(
      'LUT_3D_SIZE 2\n'
      '1 1 1\n0 1 1\n1 0 1\n0 0 1\n'
      '1 1 0\n0 1 0\n1 0 0\n0 0 0\n',
    );
    final vision = ColorVision.simulate(ColorVisionDeficiency.tritan);
    final strip = vision.toStrip(size: 2, grade: negative);
    final (r, g, b) = vision.applyEncoded(1.0, 1.0, 1.0);
    expect(strip[0], (r * 255).round());
    expect(strip[1], (g * 255).round());
    expect(strip[2], (b * 255).round());
  });

  group('the lint for cues told apart by hue alone', () {
    test('names the pair a deficiency runs together, and who', () {
      // Red against a green of nearly its lightness: 78 apart to normal eyes,
      // under 4 to a deutan's, and still apart to a protan's or a tritan's.
      // Blue against teal, the other way: only a tritan loses it.
      final found = ColorVision.confusions(<String, (double, double, double)>{
        'red': (0.8, 0.25, 0.2),
        'green': (0.45, 0.55, 0.2),
        'blue': (0.3, 0.45, 0.85),
        'teal': (0.2, 0.6, 0.6),
      });
      // Mutation: measuring the pair without simulating it finds nothing.
      expect(found.map((c) => '${c.a}/${c.b} ${c.by}').toSet(), <String>{
        'green/red deutan',
        'blue/teal tritan',
      });
    });

    test('says nothing of a pair everybody tells apart', () {
      expect(
        ColorVision.confusions(<String, (double, double, double)>{
          'black': (0.0, 0.0, 0.0),
          'white': (1.0, 1.0, 1.0),
        }),
        isEmpty,
      );
    });

    test('nor of a pair nobody does — that is not a hue cue', () {
      // Two greys a hair apart are a problem for every player, and this is
      // the lint for the ones only some players have.
      expect(
        ColorVision.confusions(<String, (double, double, double)>{
          'grey': (0.5, 0.5, 0.5),
          'greyer': (0.52, 0.52, 0.52),
        }),
        isEmpty,
      );
    });
  });
}
