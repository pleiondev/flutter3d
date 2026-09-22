/// `texture_slot.dart`: what a slot shows, from a texture's header alone.
///
///     flutter test test/texture_slot_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/texture_slot.dart';
import 'package:flutter_test/flutter_test.dart';

/// A PNG whose `IHDR` names [width]/[height], padded out to [totalBytes] so a
/// weight can be asserted on it too. Nothing past the header is a real PNG
/// stream — `textureInfo` never reads past it, and neither does this test.
Uint8List _png(int width, int height, {int totalBytes = 33}) {
  final bytes = Uint8List(totalBytes);
  final view = ByteData.sublistView(bytes);
  bytes.setAll(0, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  view.setUint32(8, 13, Endian.big);
  bytes.setAll(12, <int>[0x49, 0x48, 0x44, 0x52]);
  view.setUint32(16, width, Endian.big);
  view.setUint32(20, height, Endian.big);
  bytes.setAll(24, <int>[8, 6, 0, 0, 0]);
  return bytes;
}

const List<int> _ktx2Identifier = <int>[
  0xAB,
  0x4B,
  0x54,
  0x58,
  0x20,
  0x32,
  0x30,
  0xBB,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// A KTX2 header naming [width]/[height]/[vkFormat], with no level index —
/// `_fileFormatFor` and `blockLayoutFor` compute a BC7 slot's device bytes
/// from the header alone, so this needs nothing past it.
Uint8List _ktx2(int width, int height, {required int vkFormat}) {
  final bytes = Uint8List(48);
  final view = ByteData.sublistView(bytes);
  bytes.setAll(0, _ktx2Identifier);
  view.setUint32(12, vkFormat, Endian.little);
  view.setUint32(20, width, Endian.little);
  view.setUint32(24, height, Endian.little);
  view.setUint32(40, 1, Endian.little); // levelCount
  return bytes;
}

const int _vkFormatBc7SrgbBlock = 146;

void main() {
  group('textureSlotDisplay', () {
    test('a 256×128 PNG shows its dimensions, weight and no badge', () {
      final image = EncodedImage(
        bytes: _png(256, 128, totalBytes: 174 * 1024),
        name: 'albedo.png',
      );

      final display = textureSlotDisplay(image);

      expect(display.name, 'albedo.png');
      expect(display.dimensionsText, '256×128');
      expect(display.weightText, '174 KB');
      expect(display.formatBadge, isNull);
      expect(display.thumbnail, same(image.bytes));
    });

    test('a KTX2 BC7 file gets a format badge', () {
      final image = EncodedImage(
        bytes: _ktx2(64, 64, vkFormat: _vkFormatBc7SrgbBlock),
        name: 'normal.ktx2',
      );

      final display = textureSlotDisplay(image);

      expect(display.formatBadge, 'BC7');
      expect(display.dimensionsText, '64×64');
    });

    test('falls back to the given name when the image has none', () {
      final image = EncodedImage(bytes: _png(4, 4));

      final display = textureSlotDisplay(image, fallbackName: 'image 3');

      expect(display.name, 'image 3');
    });

    test('bytes too short for any known header show no dimensions', () {
      final image = EncodedImage(bytes: Uint8List.fromList(<int>[1, 2, 3]));

      final display = textureSlotDisplay(image);

      expect(display.dimensionsText, isNull);
      expect(display.formatBadge, isNull);
      expect(display.weightText, '3 B');
    });
  });

  group('formatBadgeFor', () {
    test('a plain RGBA texture has no badge to show', () {
      expect(formatBadgeFor(TextureFileFormat.rgba8), isNull);
    });

    test('every compressed format names its own badge', () {
      expect(formatBadgeFor(TextureFileFormat.bc1), 'BC1');
      expect(formatBadgeFor(TextureFileFormat.bc3), 'BC3');
      expect(formatBadgeFor(TextureFileFormat.bc7), 'BC7');
      expect(formatBadgeFor(TextureFileFormat.etc2Rgba8), 'ETC2');
      expect(formatBadgeFor(TextureFileFormat.astc4x4), 'ASTC 4×4');
      expect(formatBadgeFor(TextureFileFormat.other), 'KTX2');
    });
  });

  group('textureSamplingDisplay', () {
    test('the default sampling reads as linear, mipmapped, repeating', () {
      final display = textureSamplingDisplay(const TextureSampling());

      expect(display.magFilterLabel, 'Linear');
      expect(display.minFilterLabel, 'Linear, mipmapped');
      expect(display.wrapSLabel, 'Repeat');
      expect(display.wrapTLabel, 'Repeat');
    });

    test('nearest filtering with no mips names both plainly', () {
      final display = textureSamplingDisplay(
        const TextureSampling(
          magLinear: false,
          minLinear: false,
          useMipmaps: false,
        ),
      );

      expect(display.magFilterLabel, 'Nearest');
      expect(display.minFilterLabel, 'Nearest');
    });

    test('a nearest-chosen mip is distinguished from a blended one', () {
      final display = textureSamplingDisplay(
        const TextureSampling(mipLinear: false),
      );

      expect(display.minFilterLabel, 'Linear, mipmapped (nearest mip)');
    });

    test('clamp and mirrored wrap read as their own words', () {
      final display = textureSamplingDisplay(
        const TextureSampling(
          wrapS: TextureWrap.clampToEdge,
          wrapT: TextureWrap.mirroredRepeat,
        ),
      );

      expect(display.wrapSLabel, 'Clamp to edge');
      expect(display.wrapTLabel, 'Mirrored repeat');
    });
  });

  test('a slot always shows texcoord set 0', () {
    expect(textureSlotTexCoordSet, 0);
  });
}
