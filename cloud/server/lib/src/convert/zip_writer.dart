/// Writing a stored (uncompressed) ZIP: the "download all" of a conversion.
///
/// Stored rather than deflated, because what goes in is already compact —
/// `.f3d` models, encoded textures — and a level with its models is a few
/// files a person unpacks once. CRC-32 is computed here; nothing else in the
/// service needs it.
library;

import 'dart:convert';
import 'dart:typed_data';

/// A ZIP holding [files], by their `/`-separated paths, in the order given.
Uint8List storedZip(List<(String, Uint8List)> files) {
  final body = BytesBuilder(copy: false);
  final directory = BytesBuilder(copy: false);
  for (final (path, bytes) in files) {
    final name = utf8.encode(path);
    final crc = crc32(bytes);
    final offset = body.length;
    body
      ..add(_u32(0x04034b50))
      ..add(_u16(20)) // version needed
      ..add(_u16(0x800)) // names are UTF-8
      ..add(_u16(0)) // stored
      ..add(_u16(0)) // time
      ..add(_u16(0x21)) // date: 1980-01-01
      ..add(_u32(crc))
      ..add(_u32(bytes.length))
      ..add(_u32(bytes.length))
      ..add(_u16(name.length))
      ..add(_u16(0))
      ..add(name)
      ..add(bytes);
    directory
      ..add(_u32(0x02014b50))
      ..add(_u16(20)) // version made by
      ..add(_u16(20))
      ..add(_u16(0x800))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0x21))
      ..add(_u32(crc))
      ..add(_u32(bytes.length))
      ..add(_u32(bytes.length))
      ..add(_u16(name.length))
      ..add(_u16(0)) // extra
      ..add(_u16(0)) // comment
      ..add(_u16(0)) // disk
      ..add(_u16(0)) // internal attributes
      ..add(_u32(0)) // external attributes
      ..add(_u32(offset))
      ..add(name);
  }
  final directoryOffset = body.length;
  final directoryBytes = directory.takeBytes();
  body
    ..add(directoryBytes)
    ..add(_u32(0x06054b50))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(files.length))
    ..add(_u16(files.length))
    ..add(_u32(directoryBytes.length))
    ..add(_u32(directoryOffset))
    ..add(_u16(0));
  return body.takeBytes();
}

/// CRC-32 (IEEE 802.3), as ZIP stores it.
int crc32(Uint8List bytes) {
  final crc = bytes.fold<int>(
    0xFFFFFFFF,
    (crc, byte) => _table[(crc ^ byte) & 0xFF] ^ (crc >>> 8),
  );
  return crc ^ 0xFFFFFFFF;
}

final List<int> _table = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c & 1 != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
}, growable: false);

Uint8List _u16(int value) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);

Uint8List _u32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
