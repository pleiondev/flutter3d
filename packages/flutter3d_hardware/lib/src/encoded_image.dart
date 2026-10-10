/// Encoded images handed to a device whole — `A4.16`/`A4.17`.
///
/// **A browser decodes a PNG faster than Dart can, and off the main thread.**
/// `createImageBitmap` runs the platform's own decoder, and the bitmap it
/// hands back goes into a texture without its pixels ever being copied into
/// the Dart heap. A device that can do that implements [EncodedImageUpload];
/// one that cannot is handed RGBA8 by a decoder the caller chose, which is the
/// path every native backend keeps.
///
/// The size arithmetic is here rather than in a backend because three places
/// ask it — the browser decode, the native codec's target size and the CPU
/// fallback that scales a decoder's oversized answer down — and three copies
/// of "fit inside a square, keep the aspect" are three answers waiting to
/// disagree by a pixel.
library;

import 'dart:typed_data';

import 'graphics_device.dart';
import 'texture.dart';

/// A device that decodes and uploads an encoded image itself.
///
/// Optional, and asked with `device is EncodedImageUpload`: a device that is
/// not one is still a whole [GraphicsDevice], and its caller decodes on the
/// CPU and calls [GraphicsDevice.createTextureFromPixels] as it always did.
/// The WebGL2 and WebGPU backends implement it.
base mixin EncodedImageUpload on GraphicsDevice {
  /// A sampled `r8g8b8a8UNormInt` texture holding [encoded] — a PNG, JPEG,
  /// WebP or GIF — decoded by the platform, or null when the platform will
  /// not decode it. Null is a fallback, not an error: the caller decodes on
  /// the CPU instead, and a file neither path reads is a texture left out.
  ///
  /// [maxDimension] caps the longer side; a larger image is scaled down
  /// while it is decoded, keeping its aspect ([cappedImageSize]), so the full
  /// size never exists in memory. Null decodes at the file's own size.
  ///
  /// [mipmaps] asks for a full chain, built on the GPU from the base level.
  /// The pixels are straight (not premultiplied) and not colour-converted:
  /// a normal map's bytes are vectors, and a decoder that "corrected" them
  /// for a display profile would bend every normal.
  Future<TextureHandle?> decodeTexture(
    Uint8List encoded, {
    bool mipmaps = false,
    int? maxDimension,
  });
}

/// [width] by [height] scaled down so neither side exceeds [maxDimension],
/// keeping the aspect ratio, or unchanged when it already fits or
/// [maxDimension] is null.
///
/// Rounded, and never below one texel on either side: a 4096×16 strip capped
/// at 1024 is 1024×4, and a 100000×1 line is still one texel tall.
({int width, int height}) cappedImageSize(
  int width,
  int height, {
  int? maxDimension,
}) {
  if (maxDimension == null || maxDimension < 1) {
    return (width: width, height: height);
  }
  final longer = width > height ? width : height;
  if (longer <= maxDimension) return (width: width, height: height);
  final scale = maxDimension / longer;
  int side(int v) {
    final scaled = (v * scale).round();
    return scaled < 1 ? 1 : (scaled > maxDimension ? maxDimension : scaled);
  }

  return (width: side(width), height: side(height));
}

/// The pixel size an encoded image's header states, or null when the header
/// is not one this reads — PNG, JPEG, GIF and WebP (lossy, lossless and
/// extended).
///
/// **Read so that a cap can be applied before the decode, not after it.** A
/// browser's resize options and a native codec's target size both want the
/// output size up front; knowing it from a few header bytes is what lets the
/// full-size image never be decoded at all. Null costs one extra step on the
/// web — decode, then scale — and nothing natively, where the codec reports
/// the size itself.
({int width, int height})? encodedImageSize(Uint8List bytes) {
  final n = bytes.length;
  int be16(int i) => (bytes[i] << 8) | bytes[i + 1];
  int le16(int i) => bytes[i] | (bytes[i + 1] << 8);
  int be32(int i) =>
      (bytes[i] << 24) |
      (bytes[i + 1] << 16) |
      (bytes[i + 2] << 8) |
      bytes[i + 3];

  // PNG: signature, then IHDR's width and height.
  if (n >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return (width: be32(16), height: be32(20));
  }

  // GIF: logical screen size.
  if (n >= 10 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return (width: le16(6), height: le16(8));
  }

  // WebP: RIFF....WEBP and one of three chunk kinds.
  if (n >= 30 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45) {
    final kind = String.fromCharCodes(bytes, 12, 16);
    switch (kind) {
      case 'VP8 ':
        return (width: le16(26) & 0x3FFF, height: le16(28) & 0x3FFF);
      case 'VP8L':
        final b =
            bytes[21] |
            (bytes[22] << 8) |
            (bytes[23] << 16) |
            (bytes[24] << 24);
        return (width: (b & 0x3FFF) + 1, height: ((b >> 14) & 0x3FFF) + 1);
      case 'VP8X':
        return (
          width: (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)) + 1,
          height: (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16)) + 1,
        );
    }
    return null;
  }

  // JPEG: walk the markers to the first start-of-frame.
  if (n >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var i = 2;
    while (i + 9 < n) {
      if (bytes[i] != 0xFF) return null;
      final marker = bytes[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      // Standalone markers carry no length.
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final isFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isFrame) return (width: be16(i + 7), height: be16(i + 5));
      i += 2 + be16(i + 2);
    }
  }
  return null;
}
