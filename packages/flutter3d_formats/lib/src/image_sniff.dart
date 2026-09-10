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
