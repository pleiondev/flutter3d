/// `resizeRgba`, `toPowerOfTwo`, `FitTexturesToProfile` — `mat-29`'s own
/// row.
///
///     dart test test/texture_resize_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

void main() {
  group('resizeRgba, box filter', () {
    test('a 4x4 checkerboard becomes flat mid-grey at 2x2 — the row\'s '
        'own acceptance line', () {
      // Mutation: average only the first pixel of each 2x2 box instead of
      // all four (a nearest-pixel resize wearing a box filter's name) —
      // every 2x2 box here is exactly half black, half white, so a real
      // average always lands on mid-grey and a corner sample never does
      // on this particular pattern.
      const side = 4;
      final rgba = Uint8List(side * side * 4);
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final on = (x + y).isEven;
          final at = (y * side + x) * 4;
          final v = on ? 255 : 0;
          rgba[at] = v;
          rgba[at + 1] = v;
          rgba[at + 2] = v;
          rgba[at + 3] = 255;
        }
      }
      final resized = resizeRgba(
        rgba,
        side,
        side,
        2,
        2,
        filter: ResizeFilter.box,
      );
      expect(resized, hasLength(2 * 2 * 4));
      for (var i = 0; i < resized.length; i += 4) {
        expect(resized[i], 127, reason: 'pixel ${i ~/ 4} red');
        expect(resized[i + 1], 127, reason: 'pixel ${i ~/ 4} green');
        expect(resized[i + 2], 127, reason: 'pixel ${i ~/ 4} blue');
        expect(resized[i + 3], 255, reason: 'pixel ${i ~/ 4} alpha');
      }
    });

    test('a flat colour stays exactly itself at any size', () {
      final rgba = Uint8List(6 * 6 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 12;
        rgba[i + 1] = 34;
        rgba[i + 2] = 56;
        rgba[i + 3] = 255;
      }
      final resized = resizeRgba(
        rgba,
        6,
        6,
        3,
        3,
        filter: ResizeFilter.box,
      );
      for (var i = 0; i < resized.length; i += 4) {
        expect(resized.sublist(i, i + 4), <int>[12, 34, 56, 255]);
      }
    });

    test('the same size in and out is a plain copy, not a crash', () {
      final rgba = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
      final resized = resizeRgba(rgba, 2, 1, 2, 1, filter: ResizeFilter.box);
      expect(resized, rgba);
      expect(identical(resized, rgba), isFalse);
    });
  });

  group('resizeRgba, bilinear filter', () {
    test('growing a 2x1 image samples smoothly between the two pixels', () {
      final rgba = Uint8List.fromList(<int>[
        0, 0, 0, 255, // left: black
        200, 200, 200, 255, // right: light grey
      ]);
      final resized = resizeRgba(
        rgba,
        2,
        1,
        4,
        1,
        filter: ResizeFilter.bilinear,
      );
      // Mutation: sample nearest instead of interpolating — the middle two
      // output pixels would then jump straight from 0 to 200 rather than
      // stepping through, which is exactly what this checks for.
      final reds = <int>[for (var i = 0; i < resized.length; i += 4) resized[i]];
      expect(reds[0], lessThan(reds[1]));
      expect(reds[1], lessThan(reds[2]));
      expect(reds[2], lessThan(reds[3]));
    });
  });

  group('toPowerOfTwo', () {
    test('an exact power of two is itself', () {
      for (final n in <int>[1, 2, 4, 8, 16, 256, 1024]) {
        expect(toPowerOfTwo(n), n);
      }
    });

    test('rounds to the nearer power, ties going up', () {
      expect(toPowerOfTwo(5), 4); // nearer to 4 than to 8
      expect(toPowerOfTwo(6), 8); // nearer to 8 than to 4
      expect(toPowerOfTwo(12), 16); // tie between 8 and 16 -> up
      expect(toPowerOfTwo(0), 1);
    });
  });

  group('FitTexturesToProfile', () {
    Uint8List solidPng(int width, int height) {
      final rgba = Uint8List(width * height * 4);
      for (var i = 3; i < rgba.length; i += 4) {
        rgba[i] = 255;
      }
      return encodeCompressedPng(width, height, rgba);
    }

    test('mat-29\'s own acceptance: 1000x600 against a 512px budget '
        'becomes 512x512, not aspect-preserved', () {
      // Mutation: scale both dimensions by the same factor to keep
      // proportions (512x307 for this image) — the row's own numbers say
      // otherwise: each axis is clamped on its own.
      final project = ModelProject(
        profile: const ProjectProfile(
          textures: TextureBudget(
            maxSide: 512,
            maxBytesOnDevice: 999999999,
            targetFormat: TextureFileFormat.rgba8,
          ),
        ),
        images: <EncodedImage>[EncodedImage(bytes: solidPng(1000, 600))],
      );
      final fitted = FitTexturesToProfile(project);
      final dims = imageDimensions(fitted.images.single.bytes);
      expect(dims, ImageDimensions(512, 512));
    });

    test('an image already within budget is untouched, byte for byte', () {
      final original = solidPng(256, 256);
      final project = ModelProject(
        profile: const ProjectProfile(textures: TextureBudget.desktop),
        images: <EncodedImage>[EncodedImage(bytes: original)],
      );
      final fitted = FitTexturesToProfile(project);
      expect(fitted.images.single.bytes, original);
      expect(identical(fitted, project), isTrue);
    });

    test('never mutates the project handed in', () {
      final project = ModelProject(
        profile: const ProjectProfile(
          textures: TextureBudget(
            maxSide: 64,
            maxBytesOnDevice: 999999999,
            targetFormat: TextureFileFormat.rgba8,
          ),
        ),
        images: <EncodedImage>[EncodedImage(bytes: solidPng(500, 500))],
      );
      final before = project.images.single.bytes;
      FitTexturesToProfile(project);
      expect(project.images.single.bytes, before);
    });

    test('an explicit budget overrides the project\'s own profile, without '
        'changing it', () {
      // Desktop's own 2048px budget would leave a 1000x600 image untouched;
      // the override below is the only reason it shrinks.
      final project = ModelProject(
        profile: const ProjectProfile(textures: TextureBudget.desktop),
        images: <EncodedImage>[EncodedImage(bytes: solidPng(1000, 600))],
      );
      const override = TextureBudget(
        maxSide: 512,
        maxBytesOnDevice: 999999999,
        targetFormat: TextureFileFormat.rgba8,
      );
      // Mutation: read `project.profile.textures` unconditionally, ignoring
      // the `budget` parameter — this image would come back untouched.
      final fitted = FitTexturesToProfile(project, budget: override);
      final dims = imageDimensions(fitted.images.single.bytes);
      expect(dims, ImageDimensions(512, 512));
      expect(fitted.profile.textures, TextureBudget.desktop); // unchanged
    });
  });
}
