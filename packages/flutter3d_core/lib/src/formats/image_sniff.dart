import 'dart:typed_data';

/// Guesses an image's MIME type from its leading bytes.
///
/// **Sniffed rather than trusted to a filename, for the reason `isFmat` is**:
/// an image arriving as a buffer view has no filename at all, and a writer
/// packing images into a container needs the type to declare regardless.
/// Null when nothing here recognises it — a caller either passes the format
/// through unlabelled or refuses, and neither is a decision this function
/// should make.
///
/// The four `fmt-02` names: PNG, JPEG, KTX2 and WebP. Every one of them is
/// sniffed by the bytes every decoder and writer of the format already
/// agrees are the magic, not by a guess of this function's own.
String? sniffImageMimeType(Uint8List bytes) {
  if (_startsWith(bytes, _png)) return 'image/png';
  if (_startsWith(bytes, _jpeg)) return 'image/jpeg';
  if (_startsWith(bytes, _ktx2)) return 'image/ktx2';
  if (bytes.length >= 12 &&
      _startsWith(bytes, _riff) &&
      bytes[8] == 0x57 && // W
      bytes[9] == 0x45 && // E
      bytes[10] == 0x42 && // B
      bytes[11] == 0x50) {
    // P
    return 'image/webp';
  }
  return null;
}

/// Whether [bytes] is a KTX2 file Basis Universal produced — `fmt-21`'s own
/// row, the check that decides whether a texture can travel as
/// `KHR_texture_basisu` or has to be embedded the ordinary way instead.
///
/// **`vkFormat` is the whole test, per `KHR_texture_basisu`'s own spec**:
/// a container Basis Universal wrote — ETC1S or UASTC, transcodable at load
/// time — always leaves `vkFormat` at `VK_FORMAT_UNDEFINED` (`0`), the
/// header field at byte offset 12 (right after the 12-byte identifier this
/// file's own [sniffImageMimeType] already checks). A KTX2 container
/// already baked to one final block format — BC1, BC3, ASTC — names that
/// format there instead, which is exactly the case `fmt-21`'s own row
/// wants a warning for rather than a texture reference nothing can read.
///
/// **Not called `isBasisUniversalKtx2`, though that reads better.**
/// `flutter3d`'s own `ktx2_loader.dart` already has a function by that
/// exact name, for the identical check, for its own runtime reason — this
/// package cannot depend on `flutter3d` to reuse it, and `flutter3d`
/// re-exports this package, so the two names collide the moment anything
/// imports both. Renamed here rather than there, since this is the newer
/// of the two.
bool isKtx2BasisUniversal(Uint8List bytes) {
  if (!_startsWith(bytes, _ktx2)) return false;
  if (bytes.length < 16) return false;
  final vkFormat = ByteData.sublistView(
    bytes,
    12,
    16,
  ).getUint32(0, Endian.little);
  return vkFormat == 0;
}

bool _startsWith(Uint8List bytes, List<int> magic) {
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) return false;
  }
  return true;
}

const List<int> _png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const List<int> _jpeg = <int>[0xFF, 0xD8, 0xFF];
const List<int> _ktx2 = <int>[
  0xAB, 0x4B, 0x54, 0x58, // «KTX
  0x20, 0x32, 0x30, 0xBB, //  20»
  0x0D, 0x0A, 0x1A, 0x0A,
];
const List<int> _riff = <int>[0x52, 0x49, 0x46, 0x46]; // RIFF
