/// Reducing a rendered frame to a comparable grid.
///
/// Split out of `parity_scene.dart`: building the fixture and judging what a
/// backend did with it are two different jobs — one produces a [Scene]/camera
/// pair the renderer never sees, the other reads back pixels the renderer
/// produced — and neither reaches into the other's state.
library;

/// Width and height both runs render at.
const int kParityWidth = 256;
const int kParityHeight = 192;

/// Cells across and down in the comparison grid.
const int kParityGrid = 16;

/// Average luminance per cell, 0..255, row-major from the top.
///
/// A grid rather than the pixels themselves, because the question is whether
/// the two backends draw the *same picture*, not whether they produce identical
/// bytes — they will not, and demanding it would mean choosing a tolerance for
/// every pixel instead of one for the comparison. Two different GPUs, two
/// shader compilers and two rounding regimes disagree in the last bits
/// everywhere and agree completely about where the spheres are.
///
/// Averaging is what makes that distinction: it survives a fraction of a bit
/// per pixel and does not survive a shape in the wrong place, a light from the
/// wrong side, or a mirrored frame.
List<int> parityGrid(List<int> rgba, int width, int height) {
  final cells = List<int>.filled(kParityGrid * kParityGrid, 0);
  final cellW = width / kParityGrid;
  final cellH = height / kParityGrid;
  for (var cy = 0; cy < kParityGrid; cy++) {
    for (var cx = 0; cx < kParityGrid; cx++) {
      final x0 = (cx * cellW).floor();
      final x1 = ((cx + 1) * cellW).ceil().clamp(0, width);
      final y0 = (cy * cellH).floor();
      final y1 = ((cy + 1) * cellH).ceil().clamp(0, height);
      var total = 0;
      var count = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final i = (y * width + x) * 4;
          // Rec. 601 luma, integer weights. The exact coefficients matter less
          // than both sides using the same ones, which is why this is here and
          // not written out twice.
          total +=
              (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
          count++;
        }
      }
      cells[cy * kParityGrid + cx] = count == 0 ? 0 : total ~/ count;
    }
  }
  return cells;
}
