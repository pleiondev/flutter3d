/// Deciding whether an upload is a PNG picture, before it becomes a preview.
///
/// **Only the container is read, never the pixels.** A preview exists to show
/// a small viewport screenshot on a card in the cabinet, and the only thing
/// the server needs to know before storing one is that the bytes really are a
/// PNG and that the picture they describe is a sane size — not what is in it.
/// Reading `IHDR` needs no image-decoding package: PNG's signature and its
/// first chunk are both at fixed offsets, documented and unchanging, and this
/// file is the whole parser. It never reaches for `IDAT`, the chunk that
/// actually holds the (deflate-compressed) pixels — inflating that is where a
/// crafted file gets to be a decompression bomb, and the point of stopping at
/// the header is to never pay that cost.
library;

import 'dart:typed_data';

/// The eight bytes every PNG file starts with — a high bit (so a
/// text-mangling transfer is caught), the letters `PNG`, a CR-LF pair (so a
/// line-ending translation is caught) and a DOS end-of-file byte.
const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Signature (8) + a chunk's own length (4) + type (4) + `IHDR`'s fixed
/// 13-byte body: the fewest bytes a PNG can be and still have a complete
/// header. `IHDR` is always the first chunk and always this long, so nothing
/// here is a guess.
const _ihdrEnd = 8 + 4 + 4 + 13;

/// The smallest and largest side, in pixels, a preview picture may claim to
/// be. 16 is small enough that nothing under it is worth the round trip a
/// viewport screenshot makes; 2048 is well past any size a card in the
/// cabinet is ever drawn at, so accepting up to it costs nothing real while
/// still refusing an `IHDR` that names a picture bigger than any preview has
/// a reason to be.
const previewMinSide = 16;
const previewMaxSide = 2048;

sealed class PngInspection {
  const PngInspection();
}

final class PngAccepted extends PngInspection {
  const PngAccepted(this.width, this.height);

  final int width;
  final int height;
}

final class PngRejected extends PngInspection {
  const PngRejected(this.because);

  final String because;
}

/// Reads just enough of [bytes] to know whether they are a PNG of a sane
/// size: the eight-byte signature, then the `IHDR` chunk's own width and
/// height fields.
PngInspection inspectPreviewPng(Uint8List bytes) {
  if (bytes.length < 8 || !_startsWithPngSignature(bytes)) {
    return const PngRejected('That is not a PNG picture.');
  }
  if (bytes.length < _ihdrEnd) {
    return const PngRejected('That PNG is too short to have a header.');
  }

  final view = ByteData.sublistView(bytes);
  // Chunk layout: 4-byte length, 4-byte ASCII type, then `length` bytes of
  // data — big-endian throughout, per the PNG specification, unlike glTF's
  // little-endian binary chunks read elsewhere in this service.
  final chunkLength = view.getUint32(8, Endian.big);
  final chunkType = String.fromCharCodes(bytes.sublist(12, 16));
  if (chunkType != 'IHDR' || chunkLength != 13) {
    return const PngRejected('The first chunk is not a 13-byte IHDR.');
  }

  final width = view.getUint32(16, Endian.big);
  final height = view.getUint32(20, Endian.big);
  if (width < previewMinSide ||
      width > previewMaxSide ||
      height < previewMinSide ||
      height > previewMaxSide) {
    return PngRejected(
      'The picture is ${width}x$height; a preview must be between '
      '$previewMinSide and $previewMaxSide pixels on a side.',
    );
  }
  return PngAccepted(width, height);
}

bool _startsWithPngSignature(Uint8List bytes) {
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return false;
  }
  return true;
}
