/// Smaller copies of a texture, made once and uploaded by every backend.
///
/// **Nothing here may import a graphics API** — `tool/structure.dart` holds it.
///
/// ## Why the engine builds these rather than the backends
///
/// WebGL2 has `glGenerateMipmap`. Impeller has nothing of the kind — 3.47's own
/// documentation refers to a `CommandBuffer.generateMipmap` that does not
/// exist — and the software backend would have to write one anyway. So letting
/// each backend make its own chain means two of them agreeing because they
/// happen to share a filter, and a third answering differently.
///
/// That exact shape has already cost this repository once. `SamplerOptions`
/// defaulted to `linearRepeat` on both hardware backends, nobody wrote the rule
/// down, and the third backend read the interface, took the constructor
/// defaults, and drew every textured picture with hard seams — two percent of
/// every textured golden, looking exactly like a filtering bug rather than like
/// a question the contract had never answered.
///
/// One chain, built here, uploaded verbatim. A backend that disagreed would
/// have to disagree about `overwrite`, which is a much louder thing to be wrong
/// about.
library;

import 'dart:typed_data';

/// Builds the levels below the base, from half size down to one by one.
abstract final class MipChain {
  /// How many levels a chain for [width] by [height] has *below* the base.
  ///
  /// Counted to one-by-one. flutter_gpu's own `Texture.fullMipCount` stops
  /// earlier — it uses the smaller dimension and subtracts one — but that is a
  /// bound on what it will allocate, not a statement about what a chain is, and
  /// a caller passing a longer list gets it clamped there rather than here.
  static int levelsFor(int width, int height) {
    var levels = 0;
    var w = width;
    var h = height;
    while (w > 1 || h > 1) {
      w = w > 1 ? w >> 1 : 1;
      h = h > 1 ? h >> 1 : 1;
      levels++;
    }
    return levels;
  }

  /// Halves [pixels] repeatedly, returning every level below the base.
  ///
  /// Four texels averaged into one — a box filter, and deliberately the plain
  /// one. A better kernel exists for every purpose; what matters here is that
  /// the result is *identical on three backends*, and the simplest filter is
  /// the one least likely to be transcribed differently into a fourth.
  ///
  /// **Averaged in linear space, which is what these bytes are.** Every texture
  /// this engine builds a chain for is linear — the format enum says so, and
  /// the lit path works in linear throughout. Averaging sRGB bytes as though
  /// they were linear darkens every level, and the darkening compounds down the
  /// chain until a distant surface is visibly murkier than a near one. If an
  /// sRGB format ever gets a chain, this is the line that has to learn about
  /// it, and `format` is not taken here precisely so that adding it is a
  /// deliberate change rather than a default that was already wrong.
  ///
  /// Odd sizes round down, so a 5-wide level becomes 2 and the rightmost column
  /// is dropped rather than blended with its neighbour at the wrong weight.
  static List<ByteData> build(ByteData pixels, int width, int height) {
    final levels = <ByteData>[];
    var source = pixels.buffer.asUint8List(pixels.offsetInBytes, width * height * 4);
    var w = width;
    var h = height;

    while (w > 1 || h > 1) {
      final nw = w > 1 ? w >> 1 : 1;
      final nh = h > 1 ? h >> 1 : 1;
      final out = Uint8List(nw * nh * 4);

      for (var y = 0; y < nh; y++) {
        // Two source rows per destination row, unless this axis is already at
        // one, in which case the same row is read twice and the average is
        // itself.
        final y0 = h > 1 ? y * 2 : 0;
        final y1 = h > 1 ? y0 + 1 : 0;
        for (var x = 0; x < nw; x++) {
          final x0 = w > 1 ? x * 2 : 0;
          final x1 = w > 1 ? x0 + 1 : 0;
          final a = (y0 * w + x0) * 4;
          final b = (y0 * w + x1) * 4;
          final c = (y1 * w + x0) * 4;
          final d = (y1 * w + x1) * 4;
          final at = (y * nw + x) * 4;
          for (var channel = 0; channel < 4; channel++) {
            // Plus two before the shift: rounding to nearest rather than always
            // down, which over ten levels is the difference between a chain
            // that keeps its brightness and one that fades.
            out[at + channel] = (source[a + channel] +
                    source[b + channel] +
                    source[c + channel] +
                    source[d + channel] +
                    2) >>
                2;
          }
        }
      }

      levels.add(ByteData.sublistView(out));
      source = out;
      w = nw;
      h = nh;
    }

    return levels;
  }
}
