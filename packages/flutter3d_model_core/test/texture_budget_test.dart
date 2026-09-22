/// `TextureBudget`, `measure`: what a project's images would cost re-encoded,
/// against Ж5's own preset numbers.
///
///     dart test test/texture_budget_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

Uint8List _png(int width, int height) {
  final bytes = Uint8List(33);
  final view = ByteData.sublistView(bytes);
  bytes.setAll(0, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  view.setUint32(8, 13, Endian.big);
  bytes.setAll(12, <int>[0x49, 0x48, 0x44, 0x52]);
  view.setUint32(16, width, Endian.big);
  view.setUint32(20, height, Endian.big);
  bytes.setAll(24, <int>[8, 6, 0, 0, 0]);
  return bytes;
}

void main() {
  group('the presets, which are Ж5\'s own numbers', () {
    test('desktop: 2048px, 256MB, BC7', () {
      expect(TextureBudget.desktop.maxSide, 2048);
      expect(TextureBudget.desktop.maxBytesOnDevice, 256 * 1024 * 1024);
      expect(TextureBudget.desktop.targetFormat, TextureFileFormat.bc7);
    });

    test('mobile: 1024px, 64MB, ASTC 4×4', () {
      expect(TextureBudget.mobile.maxSide, 1024);
      expect(TextureBudget.mobile.maxBytesOnDevice, 64 * 1024 * 1024);
      expect(TextureBudget.mobile.targetFormat, TextureFileFormat.astc4x4);
    });

    test('web: 2048px, 128MB, ETC2 RGBA8', () {
      expect(TextureBudget.web.maxSide, 2048);
      expect(TextureBudget.web.maxBytesOnDevice, 128 * 1024 * 1024);
      expect(TextureBudget.web.targetFormat, TextureFileFormat.etc2Rgba8);
    });

    test('the default profile carries the desktop budget, the mobile preset '
        'the mobile one', () {
      expect(const ProjectProfile().textures, TextureBudget.desktop);
      expect(ProjectProfile.mobile.textures, TextureBudget.mobile);
    });
  });

  group(
    'measure: one image counted once, however many materials sample it',
    () {
      test('two materials binding the same image index still sum to one '
          "image's weight", () {
        final project = ModelProject(
          images: <EncodedImage>[EncodedImage(bytes: _png(64, 64))],
          materials: <ProjectMaterial>[
            ProjectMaterial(
              surface: SurfaceMaterial(
                baseColorTexture: const TextureBinding(imageIndex: 0),
              ),
            ),
            ProjectMaterial(
              surface: SurfaceMaterial(
                normalTexture: const TextureBinding(imageIndex: 0),
              ),
            ),
          ],
        );

        const budget = TextureBudget(
          maxSide: 4096,
          maxBytesOnDevice: 1 << 30,
          targetFormat: TextureFileFormat.rgba8,
        );
        final usage = measure(project, budget);

        // Mutation: iterate `project.materials`' own bindings instead of
        // `project.images` directly, and this counts the one picture twice —
        // once for each material sampling it.
        expect(usage.totalBytes, 64 * 64 * 4);
      });
    },
  );

  group('measure: recomputed under the budget\'s own targetFormat', () {
    test('BC7 costs a quarter of RGBA8, on dimensions a 4×4 block divides '
        'evenly', () {
      final project = ModelProject(
        images: <EncodedImage>[EncodedImage(bytes: _png(64, 64))],
      );
      final bc7 = measure(
        project,
        const TextureBudget(
          maxSide: 4096,
          maxBytesOnDevice: 1 << 30,
          targetFormat: TextureFileFormat.bc7,
        ),
      );
      final rgba8 = measure(
        project,
        const TextureBudget(
          maxSide: 4096,
          maxBytesOnDevice: 1 << 30,
          targetFormat: TextureFileFormat.rgba8,
        ),
      );

      // Mutation: read the wrong block layout (say, BC3/ASTC's 16 bytes
      // where BC1's 8 would apply, or the reverse) and this ratio moves off
      // 1/4 for a format that is genuinely a quarter of RGBA8's own weight.
      expect(bc7.totalBytes * 4, rgba8.totalBytes);
      expect(rgba8.totalBytes, 64 * 64 * 4);
      expect(bc7.totalBytes, 64 * 64);
    });
  });

  group('measure: overs, the per-image half of the budget', () {
    test('a 3000² image over the desktop preset\'s 2048px side shows up in '
        'overs', () {
      final project = ModelProject(
        images: <EncodedImage>[
          EncodedImage(bytes: _png(512, 512)),
          EncodedImage(bytes: _png(3000, 3000)),
        ],
      );
      final usage = measure(project, TextureBudget.desktop);

      // Mutation: compare against `maxBytesOnDevice` instead of `maxSide`, or
      // drop the check, and the 3000² image — plainly over a 2048px side —
      // never appears.
      expect(usage.overs, <int>[1]);
    });

    test('a side exactly at the limit is not over it', () {
      final project = ModelProject(
        images: <EncodedImage>[EncodedImage(bytes: _png(2048, 2048))],
      );
      expect(measure(project, TextureBudget.desktop).overs, isEmpty);
    });
  });

  group('an image this reader cannot measure', () {
    test('is skipped: no bytes added, no place in overs', () {
      final project = ModelProject(
        images: <EncodedImage>[
          EncodedImage(bytes: _png(64, 64)),
          EncodedImage(bytes: Uint8List.fromList(<int>[1, 2, 3])),
        ],
      );
      final usage = measure(
        project,
        const TextureBudget(
          maxSide: 4096,
          maxBytesOnDevice: 1 << 30,
          targetFormat: TextureFileFormat.rgba8,
        ),
      );

      expect(usage.totalBytes, 64 * 64 * 4);
      expect(usage.overs, isEmpty);
    });
  });
}
