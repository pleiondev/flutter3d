/// `uploadEncodedImage` routes KTX2 to `Ktx2Texture` before `dart:ui` ever
/// sees the bytes — this proves the routing itself, not the transcoder
/// (`ktx2_etc1s_test.dart` already proves that against a real encoder's
/// output pixel for pixel).
///
/// Runs off-device: [FakeBackend] records rather than draws, and the KTX2
/// path never reaches `ui.instantiateImageCodec`, so nothing here needs a
/// live Flutter binding.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/ktx2/ktx2.dart';
import 'package:flutter3d/src/engine/assets/model_document.dart';
import 'package:flutter3d/src/engine/assets/texture_upload.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/build_ktx2.dart';

Uint8List _readSample(String name) =>
    File('$kSamplesPath/$name').readAsBytesSync();

/// One BC7 block per level: sixteen bytes of anything, since the fake never
/// decodes them and this file is about what reaches the device, not what it
/// means.
List<int> _block(int seed) => List<int>.generate(16, (i) => (seed + i) & 0xFF);

void main() {
  test(
    'a block-compressed KTX2 file reaches a device that samples it',
    () async {
      final device = FakeBackend();
      final bytes = buildKtx2(
        vkFormat: VkFormat.bc7UNormBlock,
        levels: [_block(1)],
      );
      final reports = <String>[];

      final handle = await uploadEncodedImage(
        device,
        bytes,
        report: reports.add,
      );

      expect(handle, isNotNull);
      expect(reports, isEmpty);
      final spec = device.uploadedTextures.single;
      expect(spec.format, TextureFormat.bc7RGBAUNormInt);
      expect(spec.width, 4);
      expect(spec.height, 4);
      expect(device.uploadedPixels.single.lengthInBytes, 16);
      expect(device.uploadedMipLevels.single, isNull);
    },
  );

  test(
    'a device that does not sample the format gets no texture and a reason',
    () async {
      final device = FakeBackend(
        unsupportedFormats: const <TextureFormat>{
          TextureFormat.bc7RGBAUNormInt,
        },
      );
      final bytes = buildKtx2(vkFormat: VkFormat.bc7UNormBlock);
      final reports = <String>[];

      expect(
        await uploadEncodedImage(device, bytes, report: reports.add),
        isNull,
      );
      expect(device.uploadedTextures, isEmpty);
      expect(reports.single, contains('bc7RGBAUNormInt'));
    },
  );

  test(
    'a compressed texture that is not whole blocks is refused by name',
    () async {
      final device = FakeBackend();
      // 6×6 is two blocks across with a half block spare; flutter_gpu refuses
      // the allocation, so the loader refuses first, with the size in the
      // sentence.
      final bytes = buildKtx2(
        vkFormat: VkFormat.bc7UNormBlock,
        pixelWidth: 6,
        pixelHeight: 6,
        levels: [List<int>.filled(64, 0)],
      );
      final reports = <String>[];

      expect(
        await uploadEncodedImage(device, bytes, report: reports.add),
        isNull,
      );
      expect(reports.single, contains('6x6'));
      expect(reports.single, contains('4x4'));
    },
  );

  test(
    'a file with its own mip chain uploads the chain rather than building one',
    () async {
      final device = FakeBackend();
      // 8×8 BC7 is four blocks, 4×4 is one, 2×2 and 1×1 are one each.
      final bytes = buildKtx2(
        vkFormat: VkFormat.bc7UNormBlock,
        pixelWidth: 8,
        pixelHeight: 8,
        levels: [
          [..._block(1), ..._block(2), ..._block(3), ..._block(4)],
          _block(5),
          _block(6),
          _block(7),
        ],
      );

      await uploadEncodedImage(device, bytes);

      final chain = device.uploadedMipLevels.single;
      expect(chain, hasLength(3));
      expect(chain![0].lengthInBytes, 16);
      expect(chain[2].getUint8(0), 7);
    },
  );

  test('a chain is dropped when the asset asked for a single level', () async {
    final device = FakeBackend();
    final bytes = buildKtx2(
      vkFormat: VkFormat.bc7UNormBlock,
      levels: [_block(1), _block(2), _block(3)],
    );

    await uploadEncodedImage(
      device,
      bytes,
      sampling: const TextureSampling(useMipmaps: false),
    );

    expect(device.uploadedMipLevels.single, isNull);
  });

  test(
    'a plain RGBA8 KTX2 with a chain keeps the chain it came with',
    () async {
      final device = FakeBackend();
      final bytes = buildKtx2(
        vkFormat: VkFormat.r8g8b8a8UNorm,
        pixelWidth: 2,
        pixelHeight: 2,
        levels: [List<int>.filled(16, 9), List<int>.filled(4, 3)],
      );

      await uploadEncodedImage(device, bytes);

      final spec = device.uploadedTextures.single;
      expect(spec.format, TextureFormat.r8g8b8a8UNormInt);
      final chain = device.uploadedMipLevels.single;
      expect(chain, hasLength(1));
      expect(chain![0].getUint8(0), 3);
    },
  );

  test(
    'a Basis file with mips and alpha uploads RGBA8 with the file\'s chain',
    () async {
      final device = FakeBackend();
      final bytes = _readSample('ktx2/etc1s_alpha_mips.ktx2');

      final handle = await uploadEncodedImage(device, bytes);

      expect(handle, isNotNull);
      final spec = device.uploadedTextures.single;
      expect(spec.format, TextureFormat.r8g8b8a8UNormInt);
      expect(spec.width, 16);
      expect(device.uploadedMipLevels.single, hasLength(4));
      // Alpha ramps across x: the leftmost column is nearly clear, the
      // rightmost nearly opaque.
      final pixels = device.uploadedPixels.single;
      expect(pixels.getUint8(3), lessThan(64));
      expect(pixels.getUint8(15 * 4 + 3), greaterThan(192));
    },
  );

  test('a refused feature is reported in a sentence, not swallowed', () async {
    final device = FakeBackend();
    final bytes = buildKtx2(
      supercompressionScheme: Ktx2SupercompressionScheme.zstandard,
    );
    final reports = <String>[];

    expect(
      await uploadEncodedImage(device, bytes, report: reports.add),
      isNull,
    );
    expect(reports.single, contains('Zstandard'));
  });

  test('a Basis Universal KTX2 file uploads as plain RGBA8', () async {
    final device = FakeBackend();
    final bytes = _readSample('ktx2/etc1s_gradient_quadrants.ktx2');

    final handle = await uploadEncodedImage(device, bytes);

    expect(handle, isNotNull);
    expect(device.uploadedTextures, hasLength(1));
    final spec = device.uploadedTextures.single;
    expect(spec.width, 8);
    expect(spec.height, 8);
    expect(spec.format, TextureFormat.r8g8b8a8UNormInt);

    // The same ground truth `ktx2_etc1s_test.dart` checks the transcoder
    // against directly — this test is about the wiring, not the codec, so one
    // corner pixel of each quadrant is enough to know the right bytes made it
    // through `uploadEncodedImage` rather than, say, the source PNG bytes
    // misread as an image of the wrong format.
    final pixels = device.uploadedPixels.single;
    int at(int x, int y) => pixels.getUint32((y * 8 + x) * 4, Endian.little);
    int rgba(int r, int g, int b) => r | (g << 8) | (b << 16) | (0xFF << 24);
    expect(at(0, 0), rgba(253, 0, 0));
    expect(at(7, 0), rgba(6, 253, 0));
    expect(at(0, 7), rgba(0, 6, 253));
    expect(at(7, 7), rgba(255, 255, 2));
  });

  test('empty bytes upload nothing', () async {
    final device = FakeBackend();
    expect(await uploadEncodedImage(device, Uint8List(0)), isNull);
    expect(device.uploadedTextures, isEmpty);
  });

  test('a truncated KTX2 file degrades to no texture', () async {
    final device = FakeBackend();
    final bytes = _readSample('ktx2/etc1s_gradient_quadrants.ktx2');
    final truncated = Uint8List.sublistView(bytes, 0, 16);

    expect(await uploadEncodedImage(device, truncated), isNull);
    expect(device.uploadedTextures, isEmpty);
  });
}
