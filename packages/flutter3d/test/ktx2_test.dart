/// Proves the one thing `flutter3d`'s KTX2 wrapper adds over the container
/// reader in `flutter3d_formats`: mapping a Khronos `vkFormat` number to this
/// engine's own `TextureFormat`.
///
/// Everything about the container itself — the header, the level index, the
/// key/value refusals, `isKtx2File` — is proven once, without a Flutter SDK,
/// in `flutter3d_formats/test/ktx2_test.dart`; duplicating it here would only
/// prove the wrapper delegates, which reading `Ktx2Texture`'s three-line body
/// already shows. `ap-01` in `doc/asset-pipeline-plan.md`.
///
/// Runs off-device: everything is `ByteData` over a plain `Uint8List`, the
/// same property `f3d_test.dart` and `gpu_formats_test.dart` rely on.
library;

import 'package:flutter3d/src/engine/assets/ktx2/ktx2.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/build_ktx2.dart';

void main() {
  // The sampler must not decode, because the shader already does:
  // `surface.glsl` calls `SrgbToLinear` on the albedo texel and
  // `cpu_shaders_surface.dart` calls `toLinear` on it, unconditionally and on
  // every backend. An sRGB `TextureFormat` becomes a real sRGB sampler on
  // Impeller and WebGL2 and nothing at all on the rasteriser, so a file
  // written as `_SRGB` used to draw dark on two backends out of three from
  // bytes the third read right. Mutation: mapping any of these back to its
  // `...SRGB` engine format — the pairing this switch used to have — makes
  // the matching expectation report false.
  test('an sRGB vkFormat reads as the linear format with the same bits', () {
    TextureFormat formatOf(int vkFormat) =>
        Ktx2Texture.parse(buildKtx2(vkFormat: vkFormat)).format;

    expect(formatOf(VkFormat.bc7SrgbBlock), TextureFormat.bc7RGBAUNormInt);
    expect(
      formatOf(VkFormat.bc7SrgbBlock),
      formatOf(VkFormat.bc7UNormBlock),
      reason: 'the two carry identical blocks',
    );
    expect(formatOf(VkFormat.bc1RgbaSrgbBlock), TextureFormat.bc1RGBAUNormInt);
    expect(formatOf(VkFormat.bc3SrgbBlock), TextureFormat.bc3RGBAUNormInt);
    expect(
      formatOf(VkFormat.etc2R8g8b8SrgbBlock),
      TextureFormat.etc2RGB8UNormInt,
    );
    expect(
      formatOf(VkFormat.etc2R8g8b8a8SrgbBlock),
      TextureFormat.etc2RGBA8UNormInt,
    );
    expect(formatOf(VkFormat.astc4x4SrgbBlock), TextureFormat.astc4x4LDR);
    expect(formatOf(VkFormat.astc8x8SrgbBlock), TextureFormat.astc8x8LDR);
    expect(formatOf(VkFormat.r8g8b8a8Srgb), TextureFormat.r8g8b8a8UNormInt);
    expect(formatOf(VkFormat.b8g8r8a8Srgb), TextureFormat.b8g8r8a8UNormInt);
  });

  test('an unknown vkFormat names its number and is refused', () {
    final bytes = buildKtx2(vkFormat: 999999);
    expect(
      () => Ktx2Texture.parse(bytes),
      throwsA(
        isA<Ktx2FormatException>().having(
          (e) => e.message,
          'message',
          contains('999999'),
        ),
      ),
    );
  });
}
