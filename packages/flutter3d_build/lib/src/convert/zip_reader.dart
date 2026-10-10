/// Reading a ZIP archive's entries — what a `.usdz` is.
///
/// Stored and deflated entries, read through the central directory. A
/// `.usdz` is written stored by every tool that follows the format, but a
/// ZIP someone renamed is deflated, and both are read.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart' show inflate;
import '../build_exceptions.dart';

/// The entries of the ZIP archive [bytes], by name, in archive order.
///
/// Throws [SourceFormatException] for anything that is not a ZIP, or an entry
/// compressed some other way.
Map<String, Uint8List> readZip(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  // The end-of-central-directory record: 22 bytes, plus a comment of up to
  // 65535, at the end of the file.
  var end = -1;
  final lowest = bytes.length - 22 - 65535 < 0 ? 0 : bytes.length - 22 - 65535;
  for (var i = bytes.length - 22; i >= lowest; i--) {
    if (view.getUint32(i, Endian.little) == 0x06054b50) {
      end = i;
      break;
    }
  }
  if (end < 0) throw const SourceFormatException('not a ZIP archive');
  final count = view.getUint16(end + 10, Endian.little);
  var at = view.getUint32(end + 16, Endian.little);

  final entries = <String, Uint8List>{};
  for (var n = 0; n < count; n++) {
    if (at + 46 > bytes.length ||
        view.getUint32(at, Endian.little) != 0x02014b50) {
      throw const SourceFormatException(
        'a ZIP central directory entry is damaged',
      );
    }
    final method = view.getUint16(at + 10, Endian.little);
    final compressed = view.getUint32(at + 20, Endian.little);
    final nameLength = view.getUint16(at + 28, Endian.little);
    final extraLength = view.getUint16(at + 30, Endian.little);
    final commentLength = view.getUint16(at + 32, Endian.little);
    final local = view.getUint32(at + 42, Endian.little);
    final name = String.fromCharCodes(bytes, at + 46, at + 46 + nameLength);
    at += 46 + nameLength + extraLength + commentLength;

    if (view.getUint32(local, Endian.little) != 0x04034b50) {
      throw SourceFormatException('the ZIP entry "$name" has no local header');
    }
    final localName = view.getUint16(local + 26, Endian.little);
    final localExtra = view.getUint16(local + 28, Endian.little);
    final start = local + 30 + localName + localExtra;
    if (start + compressed > bytes.length) {
      throw SourceFormatException('the ZIP entry "$name" runs past the end');
    }
    final data = Uint8List.sublistView(bytes, start, start + compressed);
    if (name.endsWith('/')) continue;
    entries[name] = switch (method) {
      0 => Uint8List.fromList(data),
      8 =>
        inflate(data) ??
            (throw SourceFormatException(
              'the ZIP entry "$name" will not inflate',
            )),
      _ => throw SourceFormatException(
        'the ZIP entry "$name" is compressed with method $method; only '
        'stored and deflated entries are read',
      ),
    };
  }
  return entries;
}
