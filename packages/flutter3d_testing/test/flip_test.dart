/// FLIP in Dart gives the reference implementation's answers — `N2`.
///
/// The crops in `test/flip/` are 96 × 96 cut from the reference repository's
/// own `images/reference.png`, `images/test.png` and the error map its C++
/// tool is tested against, `src/tests/correct_ldrflip_cpp.png` (magma-mapped,
/// 67 pixels per degree). Away from a crop's border, where no filter reaches
/// past it, a pixel's error depends on nothing the crop dropped, so it has to
/// come out as the published one.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'flip/magma.dart';

({Uint8List pixels, int width, int height}) _read(String path) {
  final image = img.decodePng(File(path).readAsBytesSync())!;
  final pixels = image
      .convert(format: img.Format.uint8, numChannels: 3)
      .getBytes(order: img.ChannelOrder.rgb);
  return (pixels: pixels, width: image.width, height: image.height);
}

/// The error level a magma-mapped pixel stands for: the nearest entry.
int _level(Uint8List rgb, int at) {
  var best = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < magma.length; i++) {
    final (r, g, b) = magma[i];
    final dr = rgb[at] - (r * 255.0 + 0.5).floorToDouble();
    final dg = rgb[at + 1] - (g * 255.0 + 0.5).floorToDouble();
    final db = rgb[at + 2] - (b * 255.0 + 0.5).floorToDouble();
    final d = dr * dr + dg * dg + db * db;
    if (d < bestDistance) {
      bestDistance = d;
      best = i;
    }
  }
  return best;
}

void main() {
  test('a picture against itself is nought everywhere', () {
    final a = _read('test/flip/reference_a.png');
    final result = flip(
      a.pixels,
      a.pixels,
      width: a.width,
      height: a.height,
      channels: 3,
    );
    expect(result.mean, 0.0);
  });

  for (final crop in <String>['a', 'b']) {
    test('crop $crop matches the published error map away from its border', () {
      final reference = _read('test/flip/reference_$crop.png');
      final testImage = _read('test/flip/test_$crop.png');
      final published = _read('test/flip/error_$crop.png');
      final result = flip(
        reference.pixels,
        testImage.pixels,
        width: reference.width,
        height: reference.height,
        channels: 3,
      );

      // The colour filter's radius at 67 ppd; the feature filter's is 9.
      const margin = 10;
      var compared = 0;
      var exact = 0;
      var worst = 0;
      for (var y = margin; y < reference.height - margin; y++) {
        for (var x = margin; x < reference.width - margin; x++) {
          final at = y * reference.width + x;
          // The tool's own quantisation: `int(error * 255 + 0.5)`.
          final ours = (result.errors[at] * 255.0 + 0.5).floor();
          final theirs = _level(published.pixels, at * 3);
          final d = (ours - theirs).abs();
          if (d == 0) exact++;
          if (d > worst) worst = d;
          compared++;
        }
      }
      // Mutation: drop the Hunt adjustment, or the second blue–yellow lobe,
      // and whole regions move by tens of levels.
      expect(worst, lessThanOrEqualTo(1), reason: 'levels apart at worst');
      // Off by one only where a float and a double round either side of a
      // level boundary.
      expect(exact / compared, greaterThan(0.98));
    });
  }

  // The full 1920 × 1080 pair and the mean the reference repository's test
  // expects, 0.159691. The images are 9.5 MB, so they are not in this
  // repository: point `FLIP_IMAGES` at a checkout's `images/` to run it.
  const images = String.fromEnvironment('FLIP_IMAGES');
  test(
    'the full reference pair has the published mean',
    () {
      final reference = _read('$images/reference.png');
      final testImage = _read('$images/test.png');
      final result = flip(
        reference.pixels,
        testImage.pixels,
        width: reference.width,
        height: reference.height,
        channels: 3,
      );
      expect(result.mean, closeTo(0.159691, 5e-6));
    },
    skip: images.isEmpty ? 'set FLIP_IMAGES to the reference images' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
