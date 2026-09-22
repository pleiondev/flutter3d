/// The 5×7 font `renderSheet` labels its quadrants with — `mcp-07n`.
///
///     dart test test/tiny_font_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

/// A blank RGBA image, transparent black.
Uint8List _canvas(int width, int height) => Uint8List(width * height * 4);

/// The lit pixels of [pixels], as `(x, y)` pairs.
Set<(int, int)> _lit(Uint8List pixels, int width, int height) => <(int, int)>{
  for (var y = 0; y < height; y++)
    for (var x = 0; x < width; x++)
      if (pixels[(y * width + x) * 4 + 3] != 0) (x, y),
};

void main() {
  test('one glyph lands exactly where the font says it does', () {
    // `T`: a full top row and a stem down the middle. Written out here
    // rather than read back off the table, so a wrong table is a failing
    // test instead of a test that agrees with the mistake.
    final pixels = _canvas(8, 8);
    drawTinyText(pixels, width: 8, height: 8, x: 0, y: 0, text: 'T');

    expect(_lit(pixels, 8, 8), <(int, int)>{
      (0, 0),
      (1, 0),
      (2, 0),
      (3, 0),
      (4, 0),
      (2, 1),
      (2, 2),
      (2, 3),
      (2, 4),
      (2, 5),
      (2, 6),
    });
  });

  test('a lowercase letter draws as its uppercase', () {
    final upper = _canvas(8, 8);
    final lower = _canvas(8, 8);
    drawTinyText(upper, width: 8, height: 8, x: 0, y: 0, text: 'T');
    drawTinyText(lower, width: 8, height: 8, x: 0, y: 0, text: 't');
    expect(lower, upper);
  });

  test('an unknown character leaves a gap rather than throwing', () {
    final pixels = _canvas(32, 8);
    drawTinyText(pixels, width: 32, height: 8, x: 0, y: 0, text: 'A©A');

    // Two glyphs of ink, and the second one where the third character sits.
    final lit = _lit(pixels, 32, 8);
    expect(lit.where(((int, int) p) => p.$1 < 6), isNotEmpty);
    expect(lit.where(((int, int) p) => p.$1 >= 6 && p.$1 < 12), isEmpty);
    expect(lit.where(((int, int) p) => p.$1 >= 12), isNotEmpty);
  });

  test('a label that runs off the edge loses its tail, not its place', () {
    // Eight glyphs into six pixels of width: everything past the edge is
    // dropped. A wrapped pixel would come back on the far side of the row
    // as noise nobody could account for, so the first glyph is checked to
    // still be exactly itself.
    final clipped = _canvas(6, 8);
    drawTinyText(clipped, width: 6, height: 8, x: 0, y: 0, text: 'TTTTTTTT');

    final one = _canvas(6, 8);
    drawTinyText(one, width: 6, height: 8, x: 0, y: 0, text: 'T');
    expect(clipped, one);
  });

  test('tinyTextWidth counts the gaps between glyphs, not after them', () {
    expect(tinyTextWidth(''), 0);
    expect(tinyTextWidth('A'), tinyFontWidth);
    expect(tinyTextWidth('AB'), tinyFontWidth * 2 + tinyFontSpacing);
    expect(
      tinyTextWidth('AB', scale: 3),
      (tinyFontWidth * 2 + tinyFontSpacing) * 3,
    );
  });

  test('scale multiplies a glyph rather than resampling it', () {
    final small = _canvas(16, 16);
    final large = _canvas(16, 16);
    drawTinyText(small, width: 16, height: 16, x: 0, y: 0, text: 'T');
    drawTinyText(large, width: 16, height: 16, x: 0, y: 0, text: 'T', scale: 2);

    for (final (int x, int y) in _lit(small, 16, 16)) {
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          expect(
            _lit(large, 16, 16),
            contains((x * 2 + dx, y * 2 + dy)),
            reason: 'the doubled glyph is missing ($x, $y)\'s own block',
          );
        }
      }
    }
  });

  test('the shadow puts black under white, offset by the scale', () {
    final pixels = _canvas(16, 16);
    drawTinyTextWithShadow(
      pixels,
      width: 16,
      height: 16,
      x: 1,
      y: 1,
      text: 'T',
    );

    // The top-left pixel of the crossbar is white; one down and right of
    // the bar's own last pixel is black. Both are opaque either way, which
    // is the point: the label reads on a light render and a dark one.
    int channelAt(int x, int y, int channel) =>
        pixels[(y * 16 + x) * 4 + channel];
    expect(
      <int>[
        channelAt(1, 1, 0),
        channelAt(1, 1, 1),
        channelAt(1, 1, 2),
        channelAt(1, 1, 3),
      ],
      <int>[0xFF, 0xFF, 0xFF, 0xFF],
    );
    expect(
      <int>[
        channelAt(6, 2, 0),
        channelAt(6, 2, 1),
        channelAt(6, 2, 2),
        channelAt(6, 2, 3),
      ],
      <int>[0x00, 0x00, 0x00, 0xFF],
    );
  });

  test('every glyph in the table is five wide and seven tall', () {
    // A row wider than five bits would bleed into the next glyph's column,
    // which reads as a font that cannot be laid out rather than as one
    // wrong letter.
    for (final String character
        in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -.'.split('')) {
      final pixels = _canvas(tinyFontWidth, tinyFontHeight);
      drawTinyText(
        pixels,
        width: tinyFontWidth,
        height: tinyFontHeight,
        x: 0,
        y: 0,
        text: character,
      );
      final lit = _lit(pixels, tinyFontWidth, tinyFontHeight);
      if (character != ' ') {
        expect(lit, isNotEmpty, reason: '"$character" draws nothing');
      }
      for (final (int x, int y) in lit) {
        expect(x, lessThan(tinyFontWidth));
        expect(y, lessThan(tinyFontHeight));
      }
    }
  });
}
