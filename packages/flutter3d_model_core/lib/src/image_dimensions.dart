/// [imageDimensions] — the width and height of an encoded image, read from
/// its own container header, with no decoder anywhere in the call.
///
/// **Why a header reader and not `dart:ui`.** This package draws nothing and
/// has no window (`flutter3d_model_core.dart`'s own doc comment), so a
/// texture slot cannot ask a `Codec` — and a texture panel showing "256×128"
/// beside a thumbnail should not have to wait on a decode of pixels it is not
/// going to draw yet. PNG's `IHDR`, JPEG's `SOFn` and KTX2's fixed header each
/// carry width and height before the first pixel does, so reading them is a
/// few field reads rather than a format's worth of decoding.
///
/// **Truncated input answers null, never throws.** A texture slot is filled
/// from whatever bytes a file picker or a dropped asset handed over, and a
/// half-downloaded or corrupt file is an ordinary case for that path, not an
/// exceptional one — the caller decides what "no dimensions yet" means.
library;

import 'dart:typed_data';

/// The width and height an encoded image's own header names.
final class ImageDimensions {
  const ImageDimensions(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is ImageDimensions &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'ImageDimensions($width x $height)';
}

/// The dimensions [bytes] declares in its own PNG, JPEG or KTX2 header, or
/// null if none of the three headers matches or the file is too short to
/// hold the one it starts with.
ImageDimensions? imageDimensions(Uint8List bytes) =>
    _pngDimensions(bytes) ?? _jpegDimensions(bytes) ?? _ktx2Dimensions(bytes);

const List<int> _pngSignature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// `IHDR`'s own four bytes, the chunk type that must follow the signature.
const List<int> _ihdrType = <int>[0x49, 0x48, 0x44, 0x52];

/// PNG: an 8-byte signature, then the first chunk — always `IHDR` — with its
/// 4-byte length, 4-byte type, then width and height as big-endian `u32`
/// each. Nothing here depends on the length actually being 13, which is
/// `IHDR`'s fixed size everywhere but this reader: the two fields it wants
/// sit at fixed offsets 16 and 20 regardless.
ImageDimensions? _pngDimensions(Uint8List bytes) {
  if (bytes.length < 24) return null;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return null;
  }
  for (var i = 0; i < _ihdrType.length; i++) {
    if (bytes[12 + i] != _ihdrType[i]) return null;
  }
  final view = ByteData.sublistView(bytes);
  return ImageDimensions(
    view.getUint32(16, Endian.big),
    view.getUint32(20, Endian.big),
  );
}

/// JPEG marker codes that start a start-of-frame segment — baseline,
/// progressive, and every arithmetic/Huffman variant that carries dimensions
/// the same way. `0xC4` (DHT), `0xC8` (JPG, reserved) and `0xCC` (DAC) sit in
/// the same numeric run and are not frame headers, so the ranges below skip
/// them rather than spanning `0xC0`–`0xCF` whole.
bool _isStartOfFrame(int marker) =>
    (marker >= 0xC0 && marker <= 0xC3) ||
    (marker >= 0xC5 && marker <= 0xC7) ||
    (marker >= 0xC9 && marker <= 0xCB) ||
    (marker >= 0xCD && marker <= 0xCF);

/// JPEG: walks markers after the SOI (`FFD8`) until a start-of-frame segment
/// gives up its height and width — at offsets 3 and 5 into the segment, past
/// the 2-byte length and 1-byte sample precision — or a start-of-scan (`FFDA`)
/// or the end of the file arrives first, with no frame header seen.
ImageDimensions? _jpegDimensions(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  final view = ByteData.sublistView(bytes);
  var offset = 2;
  while (offset < bytes.length) {
    if (bytes[offset] != 0xFF) return null;
    offset++;
    while (offset < bytes.length && bytes[offset] == 0xFF) {
      offset++;
    }
    if (offset >= bytes.length) return null;
    final marker = bytes[offset];
    offset++;
    // Standalone markers: SOI, TEM, the eight restart markers. None carries
    // a length field of its own.
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      continue;
    }
    if (marker == 0xD9 || marker == 0xDA) return null;
    if (offset + 2 > bytes.length) return null;
    final segmentLength = view.getUint16(offset, Endian.big);
    if (_isStartOfFrame(marker)) {
      if (offset + 7 > bytes.length) return null;
      return ImageDimensions(
        view.getUint16(offset + 5, Endian.big),
        view.getUint16(offset + 3, Endian.big),
      );
    }
    if (segmentLength < 2 || offset + segmentLength > bytes.length) {
      return null;
    }
    offset += segmentLength;
  }
  return null;
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

/// KTX2: a fixed 12-byte identifier, then a 36-byte header of little-endian
/// `u32` fields (`ktx2_format.dart` in the engine package states the same
/// layout for the loader that reads the rest of the file) — `pixelWidth` and
/// `pixelHeight` are the third and fourth fields, at offsets 20 and 24.
ImageDimensions? _ktx2Dimensions(Uint8List bytes) {
  if (bytes.length < 12 + 36) return null;
  for (var i = 0; i < _ktx2Identifier.length; i++) {
    if (bytes[i] != _ktx2Identifier[i]) return null;
  }
  final view = ByteData.sublistView(bytes);
  return ImageDimensions(
    view.getUint32(20, Endian.little),
    view.getUint32(24, Endian.little),
  );
}
