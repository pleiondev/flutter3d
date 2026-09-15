/// [decodePng]: `mat-09n`'s pure-Dart PNG half — chunks walked, `IDAT`
/// inflated through [zlibInflate], scanlines unfiltered, and every pixel
/// converted to plain RGBA8. No `dart:ui`, no `package:image`: this package
/// has no window (`flutter3d_model_core.dart`'s own doc comment), and a
/// texture node's own bake (`mat-11`) needs pixels somewhere that does not.
///
/// **What this reads.** Colour types 0 (grey), 2 (RGB), 3 (palette), 4
/// (grey+alpha) and 6 (RGBA), at bit depths 1/2/4/8 for palette and 8/16 for
/// the other four — the row's own acceptance line. Every filter type
/// (None/Sub/Up/Average/Paeth), every chunk order a real encoder writes.
///
/// **What this does not.** Interlacing (Adam7): refused, named in the
/// return value the same way a truncated file is — nothing in this
/// repository's own goldens or fixtures is interlaced, and Adam7's seven
/// passes are a second scanline walk this row's acceptance never asks for.
/// `tRNS` (a palette's own per-index alpha): not read, so a palette image
/// with a transparent entry decodes opaque — a real gap, not an oversight,
/// left for whoever first needs one. Chunk CRCs and the zlib stream's own
/// Adler-32: not checked, the same choice [zlibInflate] already makes about
/// its own trailer — a bit flipped in the pixels is a wrong picture either
/// way, checksum or not, and this reader already refuses what it cannot
/// parse structurally.
library;

import 'dart:typed_data';

import 'inflate.dart';

/// A PNG decoded down to plain RGBA8 — top row first, four bytes a pixel,
/// `width * height * 4` bytes long.
final class DecodedImage {
  const DecodedImage({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;
}

const List<int> _signature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// [bytes] decoded, or null on anything this reader cannot make sense of:
/// a signature that does not match, a chunk running past the end of the
/// file, a colour type or bit depth combination the PNG specification does
/// not allow, interlacing, or an `IDAT` stream [zlibInflate] itself refuses.
DecodedImage? decodePng(Uint8List bytes) {
  if (bytes.length < 8) return null;
  for (var i = 0; i < _signature.length; i++) {
    if (bytes[i] != _signature[i]) return null;
  }

  final view = ByteData.sublistView(bytes);
  var offset = 8;

  int? width;
  int? height;
  int? bitDepth;
  int? colorType;
  Uint8List? palette;
  final idat = BytesBuilder(copy: false);
  var sawIend = false;

  while (offset < bytes.length && !sawIend) {
    if (offset + 8 > bytes.length) return null;
    final length = view.getUint32(offset, Endian.big);
    final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    final dataStart = offset + 8;
    final dataEnd = dataStart + length;
    if (dataEnd + 4 > bytes.length) return null;

    switch (type) {
      case 'IHDR':
        if (length != 13) return null;
        width = view.getUint32(dataStart, Endian.big);
        height = view.getUint32(dataStart + 4, Endian.big);
        bitDepth = bytes[dataStart + 8];
        colorType = bytes[dataStart + 9];
        final compression = bytes[dataStart + 10];
        final filter = bytes[dataStart + 11];
        final interlace = bytes[dataStart + 12];
        if (width == 0 || height == 0) return null;
        if (compression != 0 || filter != 0) return null;
        if (interlace != 0) return null; // Adam7 — see the library comment
      case 'PLTE':
        if (length % 3 != 0) return null;
        palette = Uint8List.sublistView(bytes, dataStart, dataEnd);
      case 'IDAT':
        idat.add(Uint8List.sublistView(bytes, dataStart, dataEnd));
      case 'IEND':
        sawIend = true;
    }
    offset = dataEnd + 4; // past the chunk's own CRC, unread
  }

  if (width == null ||
      height == null ||
      bitDepth == null ||
      colorType == null) {
    return null;
  }
  final channels = switch (colorType) {
    0 => 1, // grey
    2 => 3, // RGB
    3 => 1, // palette index
    4 => 2, // grey + alpha
    6 => 4, // RGBA
    _ => null,
  };
  if (channels == null) return null;
  final allowedDepths = colorType == 3
      ? const <int>{1, 2, 4, 8}
      : const <int>{8, 16};
  if (!allowedDepths.contains(bitDepth)) return null;
  if (colorType == 3 && palette == null) return null;

  final raw = zlibInflate(idat.toBytes());
  if (raw == null) return null;

  final bitsPerPixel = bitDepth * channels;
  final rowBytes = (width * bitsPerPixel + 7) ~/ 8;
  final filterBpp = bitsPerPixel < 8 ? 1 : bitsPerPixel ~/ 8;
  final expected = height * (rowBytes + 1);
  if (raw.length < expected) return null;

  final unfiltered = _unfilter(raw, height, rowBytes, filterBpp);
  if (unfiltered == null) return null;

  return DecodedImage(
    width: width,
    height: height,
    rgba: _toRgba8(
      unfiltered,
      width: width,
      height: height,
      colorType: colorType,
      bitDepth: bitDepth,
      channels: channels,
      rowBytes: rowBytes,
      palette: palette,
    ),
  );
}

/// [raw] — [height] scanlines, each a filter-type byte then [rowBytes] of
/// filtered data — reconstructed in place per PNG §6: each byte remembers
/// only the byte to its own left (by [bpp]) and the byte above it, from the
/// row already reconstructed one scanline before it.
Uint8List? _unfilter(Uint8List raw, int height, int rowBytes, int bpp) {
  final out = Uint8List(height * rowBytes);
  var src = 0;
  var previousRowStart = -1;
  for (var y = 0; y < height; y++) {
    final filterType = raw[src++];
    final rowStart = y * rowBytes;
    for (var x = 0; x < rowBytes; x++) {
      final filtered = raw[src + x];
      final left = x >= bpp ? out[rowStart + x - bpp] : 0;
      final above = previousRowStart >= 0 ? out[previousRowStart + x] : 0;
      final aboveLeft = (previousRowStart >= 0 && x >= bpp)
          ? out[previousRowStart + x - bpp]
          : 0;
      final value = switch (filterType) {
        0 => filtered,
        1 => filtered + left,
        2 => filtered + above,
        3 => filtered + ((left + above) >> 1),
        4 => filtered + _paeth(left, above, aboveLeft),
        _ => -1,
      };
      if (value < 0) return null;
      out[rowStart + x] = value & 0xFF;
    }
    src += rowBytes;
    previousRowStart = rowStart;
  }
  return out;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

/// [unfiltered] — one sample per channel per pixel, packed at [bitDepth]
/// bits, [channels] of them per pixel, [rowBytes] to a scanline — read out
/// pixel by pixel and written as plain RGBA8.
Uint8List _toRgba8(
  Uint8List unfiltered, {
  required int width,
  required int height,
  required int colorType,
  required int bitDepth,
  required int channels,
  required int rowBytes,
  required Uint8List? palette,
}) {
  final rgba = Uint8List(width * height * 4);
  final maxSample = (1 << bitDepth) - 1;

  int sampleAt(int rowStart, int pixel, int channel) {
    final index = pixel * channels + channel;
    if (bitDepth == 8) return unfiltered[rowStart + index];
    if (bitDepth == 16) {
      return unfiltered[rowStart + index * 2]; // high byte only
    }
    // 1, 2 or 4 bits — packed most-significant-bit first within a byte,
    // PNG §7.2.
    final bitOffset = index * bitDepth;
    final byte = unfiltered[rowStart + bitOffset ~/ 8];
    final shift = 8 - bitDepth - (bitOffset % 8);
    return (byte >> shift) & maxSample;
  }

  /// A sample scaled to 0–255 — exact for 8-bit ([maxSample] is already
  /// 255, so this is a no-op — and for the sub-8-bit depths, where the
  /// scale factor is always a whole divisor of 255 (1, 3, 5, 15 for depths
  /// 1, 2, 4 read as 255 ÷ maxSample), matching what PNG §7.2 itself calls
  /// out for greyscale/palette values shown as intensities.
  int scale(int sample) => bitDepth >= 8 ? sample : sample * 255 ~/ maxSample;

  for (var y = 0; y < height; y++) {
    final rowStart = y * rowBytes;
    for (var x = 0; x < width; x++) {
      final out = (y * width + x) * 4;
      switch (colorType) {
        case 0: // grey
          final g = scale(sampleAt(rowStart, x, 0));
          rgba[out] = g;
          rgba[out + 1] = g;
          rgba[out + 2] = g;
          rgba[out + 3] = 255;
        case 2: // RGB
          rgba[out] = sampleAt(rowStart, x, 0);
          rgba[out + 1] = sampleAt(rowStart, x, 1);
          rgba[out + 2] = sampleAt(rowStart, x, 2);
          rgba[out + 3] = 255;
        case 3: // palette
          final index = sampleAt(rowStart, x, 0);
          final at = index * 3;
          if (palette != null && at + 2 < palette.length) {
            rgba[out] = palette[at];
            rgba[out + 1] = palette[at + 1];
            rgba[out + 2] = palette[at + 2];
          }
          rgba[out + 3] = 255;
        case 4: // grey + alpha
          final g = scale(sampleAt(rowStart, x, 0));
          rgba[out] = g;
          rgba[out + 1] = g;
          rgba[out + 2] = g;
          rgba[out + 3] = sampleAt(rowStart, x, 1);
        case 6: // RGBA
          rgba[out] = sampleAt(rowStart, x, 0);
          rgba[out + 1] = sampleAt(rowStart, x, 1);
          rgba[out + 2] = sampleAt(rowStart, x, 2);
          rgba[out + 3] = sampleAt(rowStart, x, 3);
      }
    }
  }
  return rgba;
}
