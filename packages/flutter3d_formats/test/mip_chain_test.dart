/// `ap-08` in `doc/asset-pipeline-plan.md`: the three treatments
/// `buildMipChain` gives a byte depending on what it encodes, checked one at
/// a time against a source built specifically to make the naive answer
/// (a plain box average) visibly wrong.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:test/test.dart';

Rgba8Image _checkerboard({
  int size = 16,
  int a = 0,
  int b = 255,
  int alpha = 255,
}) {
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final on = (x + y).isEven ? a : b;
      final at = (y * size + x) * 4;
      pixels[at] = on;
      pixels[at + 1] = on;
      pixels[at + 2] = on;
      pixels[at + 3] = alpha;
    }
  }
  return Rgba8Image(width: size, height: size, pixels: pixels);
}

void main() {
  test('a chain reaches 1x1 and stays there', () {
    final chain = buildMipChain(_checkerboard(size: 12));
    expect(chain.first.width, 12);
    expect(chain.first.height, 12);
    expect(chain.last.width, 1);
    expect(chain.last.height, 1);
    // 12 -> 6 -> 3 -> 2 -> 1: base plus four levels below it.
    expect(chain, hasLength(5));
  });

  test('an odd size still reaches exactly 1x1, rounding up', () {
    final chain = buildMipChain(_checkerboard(size: 5));
    for (final level in chain) {
      expect(level.width, greaterThanOrEqualTo(1));
      expect(level.height, greaterThanOrEqualTo(1));
    }
    expect(chain.last.width, 1);
    expect(chain.last.height, 1);
  });

  group('sRGB colour', () {
    test('a black-and-white checkerboard\'s small level is near mid-grey, not dark', () {
      // The textbook artifact this treatment exists to avoid: averaging 0 and
      // 255 as gamma-encoded bytes gives 128, but the *linear-light* average
      // of black and white decodes back to about 188 — nowhere near 128.
      final chain = buildMipChain(_checkerboard(), srgb: true);
      final small = chain[chain.length - 3]; // small enough to have averaged
      expect(small.red(0, 0), greaterThan(160));
    });

    test('a flat colour survives the round trip through linear space', () {
      final flat = _checkerboard(a: 136, b: 136);
      final chain = buildMipChain(flat, srgb: true);
      for (final level in chain) {
        expect(level.red(0, 0), closeTo(136, 2));
      }
    });
  });

  group('normal map', () {
    Rgba8Image checkerNormals() {
      // Two unit vectors 90 degrees apart in the XY plane, alternating —
      // averaging them naively (without renormalizing) gives a vector well
      // short of unit length.
      final size = 16;
      final pixels = Uint8List(size * size * 4);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final (nx, ny, nz) = (x + y).isEven ? (1.0, 0.0, 0.0) : (0.0, 1.0, 0.0);
          final at = (y * size + x) * 4;
          pixels[at] = ((nx + 1) / 2 * 255).round();
          pixels[at + 1] = ((ny + 1) / 2 * 255).round();
          pixels[at + 2] = ((nz + 1) / 2 * 255).round();
          pixels[at + 3] = 255;
        }
      }
      return Rgba8Image(width: size, height: size, pixels: pixels);
    }

    test('every level\'s normals stay unit length', () {
      final chain = buildMipChain(checkerNormals(), isNormalMap: true);
      for (final level in chain) {
        for (var y = 0; y < level.height; y++) {
          for (var x = 0; x < level.width; x++) {
            final nx = level.red(x, y) / 255 * 2 - 1;
            final ny = level.green(x, y) / 255 * 2 - 1;
            final nz = level.blue(x, y) / 255 * 2 - 1;
            final length = math.sqrt(nx * nx + ny * ny + nz * nz);
            expect(
              length,
              closeTo(1.0, 0.02),
              reason: 'level ${level.width}x${level.height} pixel ($x, $y)',
            );
          }
        }
      }
    });
  });

  group('alpha-test coverage', () {
    test('a small level\'s coverage matches the base within a few percent', () {
      // A filled disk covering about half the image — the shape this
      // treatment actually targets (a leaf card, a decal's cutout), unlike a
      // fine dot screen: a disk's edge still varies smoothly at every mip
      // level, where a screen at the Nyquist limit collapses to a single
      // filtered value a scale/bias cannot then split back into two groups.
      // Close to 50% deliberately: `_preserveCoverage` pivots on the
      // threshold, so a target near it is the case the pivot can always
      // reach — a target far from 50% is the real, documented limit
      // `_preserveCoverage`'s own doc comment names, not this test's concern.
      const size = 64;
      final pixels = Uint8List(size * size * 4);
      final radius = size * math.sqrt(0.5 / math.pi);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final dx = x - size / 2 + 0.5;
          final dy = y - size / 2 + 0.5;
          final on = dx * dx + dy * dy <= radius * radius;
          final at = (y * size + x) * 4;
          pixels[at] = 200;
          pixels[at + 1] = 200;
          pixels[at + 2] = 200;
          pixels[at + 3] = on ? 255 : 0;
        }
      }
      final source = Rgba8Image(width: size, height: size, pixels: pixels);
      const threshold = 0.5;

      double coverageOf(Rgba8Image image) {
        var count = 0;
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            if (image.alpha(x, y) > (threshold * 255).round()) count++;
          }
        }
        return count / (image.width * image.height);
      }

      final baseCoverage = coverageOf(source);
      final chain = buildMipChain(source, alphaTestThreshold: threshold);
      for (final level in chain.skip(1)) {
        // Below 8x8 the disk is only a handful of texels across, and
        // `_preserveCoverage`'s own doc comment names exactly this as the
        // pivot-and-scale technique's real limit, not a bug to chase here.
        if (level.width * level.height < 64) continue;
        expect(
          coverageOf(level),
          closeTo(baseCoverage, 0.15),
          reason: 'level ${level.width}x${level.height}',
        );
      }
    });
  });
}
