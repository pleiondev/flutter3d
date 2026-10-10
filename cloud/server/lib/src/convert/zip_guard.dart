/// Unpacking an uploaded ZIP without trusting what it says about itself.
///
/// **The expansion is counted as it happens, not read from the header.** A
/// ZIP's central directory states each entry's size, and a zip bomb is
/// exactly an archive whose stated sizes are small and whose streams are not.
/// So every entry is inflated through a sink that counts the bytes coming
/// out and stops the moment the archive as a whole passes its budget — a
/// few kilobytes of input cannot make this allocate gigabytes, whatever the
/// headers claim.
///
/// The same reader measures a `.usdz` (itself a ZIP) before the converter
/// opens it, because the converter's own reader inflates without a cap.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Why an archive was refused. The message is shown to the person who sent
/// it, so it names the problem in their terms.
final class ZipRefused implements Exception {
  const ZipRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How many entries an archive may hold. A Unity or Godot project folder
/// with its `.meta` and `.import` files runs to a few thousand; a hundred
/// thousand tiny entries is a way to spend the server's time on bookkeeping.
const int maxZipEntries = 20000;

/// Whether [bytes] start like a ZIP archive (a local file header).
bool looksLikeZip(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4b &&
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;

/// The entries of [bytes], by their path inside the archive, inflated.
///
/// [budget] is the most the archive may expand to, all entries together.
/// Directories, `__MACOSX/` and `.DS_Store` are skipped. Throws [ZipRefused]
/// for an archive that is damaged, encrypted, ZIP64, holds an entry named
/// outside itself (`../`, an absolute path, a drive letter), or expands past
/// [budget].
Map<String, Uint8List> unzipGuarded(Uint8List bytes, {required int budget}) {
  final entries = <String, Uint8List>{};
  var spent = 0;
  for (final entry in _centralDirectory(bytes)) {
    final name = _safeName(entry.name);
    if (name == null) continue;
    final (count, data) = _inflate(bytes, entry, budget - spent, keep: true);
    spent += count;
    entries[name] = data!;
  }
  return entries;
}

/// How many bytes [bytes] inflate to, all entries together, without keeping
/// any of them. Throws [ZipRefused] past [budget], like [unzipGuarded].
int measureZip(Uint8List bytes, {required int budget}) {
  var spent = 0;
  for (final entry in _centralDirectory(bytes)) {
    spent += _inflate(bytes, entry, budget - spent, keep: false).$1;
  }
  return spent;
}

final class _Entry {
  const _Entry({
    required this.name,
    required this.method,
    required this.flags,
    required this.compressedSize,
    required this.localOffset,
  });

  final String name;
  final int method;
  final int flags;
  final int compressedSize;
  final int localOffset;
}

List<_Entry> _centralDirectory(Uint8List bytes) {
  if (bytes.length < 22) throw const ZipRefused('That is not a ZIP archive.');
  final view = ByteData.sublistView(bytes);

  // The end-of-central-directory record: 22 bytes plus a comment of up to
  // 65535, at the very end.
  var end = -1;
  final lowest = bytes.length - 22 - 65535 < 0 ? 0 : bytes.length - 22 - 65535;
  for (var i = bytes.length - 22; i >= lowest; i--) {
    if (view.getUint32(i, Endian.little) == 0x06054b50) {
      end = i;
      break;
    }
  }
  if (end < 0) throw const ZipRefused('That is not a ZIP archive.');

  final count = view.getUint16(end + 10, Endian.little);
  final offset = view.getUint32(end + 16, Endian.little);
  if (count == 0xFFFF || offset == 0xFFFFFFFF) {
    throw const ZipRefused(
      'The archive is a ZIP64 archive, which is not read here. Pack it as an '
      'ordinary ZIP (under 4 GB and 65535 files).',
    );
  }
  if (count > maxZipEntries) {
    throw const ZipRefused(
      'The archive holds more than $maxZipEntries files. Pack only the folder '
      'the scene and its assets are in.',
    );
  }

  final entries = <_Entry>[];
  var at = offset;
  for (var n = 0; n < count; n++) {
    if (at + 46 > bytes.length ||
        view.getUint32(at, Endian.little) != 0x02014b50) {
      throw const ZipRefused('The archive is damaged: its file list is cut.');
    }
    final flags = view.getUint16(at + 8, Endian.little);
    final method = view.getUint16(at + 10, Endian.little);
    final compressed = view.getUint32(at + 20, Endian.little);
    final uncompressed = view.getUint32(at + 24, Endian.little);
    final nameLength = view.getUint16(at + 28, Endian.little);
    final extraLength = view.getUint16(at + 30, Endian.little);
    final commentLength = view.getUint16(at + 32, Endian.little);
    final local = view.getUint32(at + 42, Endian.little);
    if (at + 46 + nameLength > bytes.length) {
      throw const ZipRefused('The archive is damaged: a file name is cut.');
    }
    // Bit 11 says the name is UTF-8; without it the name is CP437, which
    // agrees with Latin-1 on everything a file name is likely to hold.
    final rawName = Uint8List.sublistView(bytes, at + 46, at + 46 + nameLength);
    final name = flags & 0x800 != 0
        ? utf8.decode(rawName, allowMalformed: true)
        : latin1.decode(rawName);
    if (compressed == 0xFFFFFFFF ||
        uncompressed == 0xFFFFFFFF ||
        local == 0xFFFFFFFF) {
      throw const ZipRefused(
        'The archive is a ZIP64 archive, which is not read here. Pack it as '
        'an ordinary ZIP (under 4 GB and 65535 files).',
      );
    }
    entries.add(
      _Entry(
        name: name,
        method: method,
        flags: flags,
        compressedSize: compressed,
        localOffset: local,
      ),
    );
    at += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

/// [raw] as a path inside the archive, `/`-separated, or null for an entry
/// that is skipped (a directory, macOS's resource forks).
///
/// Throws for a name that reaches outside the archive: an archive that
/// tries that once is not one whose other names deserve trust.
String? _safeName(String raw) {
  final unified = raw.replaceAll(r'\', '/');
  if (unified.endsWith('/')) return null;
  if (unified.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(unified)) {
    throw ZipRefused('The archive names "$raw", an absolute path.');
  }
  final segments = <String>[
    for (final segment in unified.split('/'))
      if (segment.isNotEmpty && segment != '.') segment,
  ];
  if (segments.contains('..')) {
    throw ZipRefused('The archive names "$raw", which reaches outside it.');
  }
  if (segments.isEmpty) return null;
  if (segments.first == '__MACOSX' || segments.last == '.DS_Store') return null;
  if (segments.any((s) => s.contains('\u0000'))) {
    throw ZipRefused('The archive names a file with a NUL in it.');
  }
  return segments.join('/');
}

/// One entry inflated, at most [allowance] bytes of it: how many bytes it
/// came to, and the bytes themselves when [keep] is set. Measuring keeps
/// nothing, so a `.usdz` is counted without being held twice.
(int, Uint8List?) _inflate(
  Uint8List bytes,
  _Entry entry,
  int allowance, {
  required bool keep,
}) {
  if (entry.flags & 0x1 != 0) {
    throw ZipRefused('"${entry.name}" in the archive is encrypted.');
  }
  final view = ByteData.sublistView(bytes);
  final local = entry.localOffset;
  if (local + 30 > bytes.length ||
      view.getUint32(local, Endian.little) != 0x04034b50) {
    throw ZipRefused('The archive is damaged around "${entry.name}".');
  }
  final start =
      local +
      30 +
      view.getUint16(local + 26, Endian.little) +
      view.getUint16(local + 28, Endian.little);
  if (start + entry.compressedSize > bytes.length) {
    throw ZipRefused('The archive is cut short inside "${entry.name}".');
  }
  final data = Uint8List.sublistView(
    bytes,
    start,
    start + entry.compressedSize,
  );

  switch (entry.method) {
    case 0:
      if (data.length > allowance) throw _tooLarge();
      return (data.length, keep ? Uint8List.fromList(data) : null);
    case 8:
      final sink = _CappedSink(allowance, keep: keep);
      final input = ZLibDecoder(raw: true).startChunkedConversion(sink);
      // Fed in small slices, so the output between two checks is bounded by
      // what one slice can expand to — DEFLATE's own ceiling is about a
      // thousand to one, so a few megabytes — rather than by the archive.
      const slice = 4096;
      try {
        for (var at = 0; at < data.length; at += slice) {
          final stop = at + slice < data.length ? at + slice : data.length;
          input.addSlice(data, at, stop, false);
        }
        input.close();
      } on _OverBudget {
        throw _tooLarge();
      } on FormatException {
        throw ZipRefused('"${entry.name}" in the archive will not inflate.');
      } on FileSystemException {
        // dart:io's zlib filter reports a corrupt stream this way.
        throw ZipRefused('"${entry.name}" in the archive will not inflate.');
      }
      return (sink.count, keep ? sink.bytes() : null);
    default:
      throw ZipRefused(
        '"${entry.name}" in the archive is compressed with method '
        '${entry.method}; only stored and deflated files are read.',
      );
  }
}

ZipRefused _tooLarge() => const ZipRefused(
  'The archive unpacks to more than this server reads for one conversion, '
  'so it was not unpacked. Send the folder the scene is in, not the whole '
  'project.',
);

final class _OverBudget implements Exception {
  const _OverBudget();
}

final class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.allowance, {required this.keep});

  final int allowance;
  final bool keep;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  int count = 0;

  @override
  void add(List<int> chunk) {
    count += chunk.length;
    if (count > allowance) throw const _OverBudget();
    if (keep) _builder.add(chunk);
  }

  @override
  void close() {}

  Uint8List bytes() => _builder.takeBytes();
}
