/// A 5×7 bitmap font, drawn straight into RGBA bytes — what this workspace
/// needed to put a word on a picture with no `dart:ui` behind it.
///
/// **Every other label in this project comes from a widget tree.** That is
/// fine for a screen and useless for [renderSheet], which runs in a plain
/// Dart process an agent started: there is no canvas, no `TextPainter` and
/// no font file, and a contact sheet whose quadrants are unlabelled makes
/// the reader count corners to work out which view is which. Seven bytes a
/// glyph and a nested loop is the whole of what that costs.
///
/// Uppercase only, plus digits, space, `-` and `.`. A lowercase letter is
/// drawn as its uppercase — a label is a label, and half a font that
/// silently drops characters would put holes in words. Anything else is
/// skipped, which is visible as a gap rather than as a crash: a caller
/// putting a character this cannot draw into a label has made a mistake
/// worth seeing, not worth stopping for.
library;

import 'dart:typed_data';

/// How many pixels wide one glyph is, before [drawTinyText]'s own `scale`.
const int tinyFontWidth = 5;

/// How many pixels tall.
const int tinyFontHeight = 7;

/// One blank column between glyphs, so `II` does not read as one letter.
const int tinyFontSpacing = 1;

/// Seven rows a glyph, five bits a row, the top bit leftmost.
const Map<String, List<int>> _glyphs = <String, List<int>>{
  'A': <int>[0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
  'B': <int>[0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
  'C': <int>[0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
  'D': <int>[0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E],
  'E': <int>[0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
  'F': <int>[0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
  'G': <int>[0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
  'H': <int>[0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
  'I': <int>[0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
  'J': <int>[0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
  'K': <int>[0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
  'L': <int>[0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
  'M': <int>[0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
  'N': <int>[0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11],
  'O': <int>[0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
  'P': <int>[0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
  'Q': <int>[0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
  'R': <int>[0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
  'S': <int>[0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
  'T': <int>[0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
  'U': <int>[0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
  'V': <int>[0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
  'W': <int>[0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11],
  'X': <int>[0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
  'Y': <int>[0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04],
  'Z': <int>[0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
  '0': <int>[0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
  '1': <int>[0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
  '2': <int>[0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
  '3': <int>[0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],
  '4': <int>[0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
  '5': <int>[0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
  '6': <int>[0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
  '7': <int>[0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
  '8': <int>[0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
  '9': <int>[0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
  ' ': <int>[0, 0, 0, 0, 0, 0, 0],
  '-': <int>[0, 0, 0, 0x0E, 0, 0, 0],
  '.': <int>[0, 0, 0, 0, 0, 0x0C, 0x0C],
};

/// How wide [text] will be at [scale], in pixels.
int tinyTextWidth(String text, {int scale = 1}) => text.isEmpty
    ? 0
    : (text.length * (tinyFontWidth + tinyFontSpacing) - tinyFontSpacing) *
          scale;

/// [text] drawn opaquely into [pixels] — RGBA8, [width] × [height] — with
/// its top-left corner at ([x], [y]).
///
/// Pixels outside the image are dropped rather than wrapped: a label that
/// runs off an edge loses its tail, where a wrapped one would reappear on
/// the other side of the picture as noise nobody can account for.
void drawTinyText(
  Uint8List pixels, {
  required int width,
  required int height,
  required int x,
  required int y,
  required String text,
  int scale = 1,
  int red = 0xFF,
  int green = 0xFF,
  int blue = 0xFF,
}) {
  var penX = x;
  for (final String character in text.toUpperCase().split('')) {
    final glyph = _glyphs[character];
    if (glyph != null) {
      for (var row = 0; row < tinyFontHeight; row++) {
        for (var column = 0; column < tinyFontWidth; column++) {
          if (glyph[row] & (1 << (tinyFontWidth - 1 - column)) == 0) continue;
          for (var dy = 0; dy < scale; dy++) {
            for (var dx = 0; dx < scale; dx++) {
              final px = penX + column * scale + dx;
              final py = y + row * scale + dy;
              if (px < 0 || py < 0 || px >= width || py >= height) continue;
              final at = (py * width + px) * 4;
              pixels[at] = red;
              pixels[at + 1] = green;
              pixels[at + 2] = blue;
              pixels[at + 3] = 0xFF;
            }
          }
        }
      }
    }
    penX += (tinyFontWidth + tinyFontSpacing) * scale;
  }
}

/// [text] drawn so it can be read over anything: black one pixel down and
/// right, then white on top.
///
/// **A white label is invisible on a white render and a black one is
/// invisible on a dark one**, and a contact sheet is drawn over whatever
/// clear colour the caller picked. The shadow costs one extra pass and
/// removes the whole question.
void drawTinyTextWithShadow(
  Uint8List pixels, {
  required int width,
  required int height,
  required int x,
  required int y,
  required String text,
  int scale = 1,
}) {
  drawTinyText(
    pixels,
    width: width,
    height: height,
    x: x + scale,
    y: y + scale,
    text: text,
    scale: scale,
    red: 0x00,
    green: 0x00,
    blue: 0x00,
  );
  drawTinyText(
    pixels,
    width: width,
    height: height,
    x: x,
    y: y,
    text: text,
    scale: scale,
  );
}
