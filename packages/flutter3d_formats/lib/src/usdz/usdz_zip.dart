import 'dart:typed_data';

/// A ZIP archive holding [entries] uncompressed, each one's data padded to
/// start at a 64-byte offset — the one structural rule `.usdz` adds on top of
/// an ordinary ZIP.
///
/// **Why 64 bytes, and why this is the whole of what makes a ZIP a USDZ.**
/// Pixar's own reader — and Quick Look's, since it uses the same library —
/// memory-maps a texture or a crate layer straight out of the archive rather
/// than decompressing it into a fresh buffer first, and a memory-mapped
/// region has to start on a page-friendly boundary. `usdzip`'s own
/// convention closes the gap between a local file header's fixed 30 bytes
/// plus its filename and the next multiple of 64 with a dummy "extra field"
/// entry — content nobody reads, sized to be exactly the padding needed.
/// [store] does the same arithmetic.
///
/// **Uncompressed, and not a missing feature.** `fmt-27`'s own acceptance
/// line says so directly, and it is not a shortcut: a compressed entry can
/// only be read by inflating it first, which defeats the memory-mapping this
/// whole alignment scheme exists for. `STORE` is what every real `.usdz`
/// this reads was already written with.
final class UsdzZip {
  UsdzZip();

  final List<_Entry> _entries = <_Entry>[];

  /// Appends [data] under [name], uncompressed and 64-byte aligned. Order
  /// matters: the *first* entry a `.usdz` reader opens is the one it treats
  /// as the default layer, which is why [UsdzWriter] always calls this with
  /// the `.usda` file before any texture.
  void store(String name, Uint8List data) {
    _entries.add(_Entry(name, data));
  }

  /// Encodes every stored entry into one `.usdz`/`.zip` file.
  Uint8List build() {
    final out = BytesBuilder();
    final centralDirectory = BytesBuilder();
    var centralDirectoryEntries = 0;

    for (final entry in _entries) {
      final nameBytes = _ascii(entry.name);
      final localHeaderOffset = out.length;

      // Padding so the *data* — after this header, the filename and the
      // extra field — lands on a 64-byte boundary. The extra field's own
      // 4-byte sub-header (id + size) is part of what has to fit before
      // that boundary, not padding itself.
      final beforeExtra = localHeaderOffset + 30 + nameBytes.length;
      final padLength = (64 - (beforeExtra + 4) % 64) % 64;
      final extraFieldLength = 4 + padLength;

      final crc = _crc32(entry.data);

      out
        ..add(_uint32(0x04034b50)) // local file header signature
        ..add(_uint16(20)) // version needed to extract
        ..add(_uint16(0)) // general purpose bit flag
        ..add(_uint16(0)) // compression method: stored
        ..add(_uint16(0)) // last mod file time
        ..add(_uint16(0)) // last mod file date
        ..add(_uint32(crc))
        ..add(_uint32(entry.data.length)) // compressed size == uncompressed
        ..add(_uint32(entry.data.length))
        ..add(_uint16(nameBytes.length))
        ..add(_uint16(extraFieldLength))
        ..add(nameBytes)
        ..add(_uint16(0x1986)) // extra field id: arbitrary, unread by anyone
        ..add(_uint16(padLength))
        ..add(Uint8List(padLength))
        ..add(entry.data);

      // Mutation-worth checking on its own terms, not just trusted: every
      // byte written above is accounted for here, so a drift between this
      // arithmetic and what was actually appended shows up as a failed
      // `dataOffset % 64 == 0` assertion in the writer's own test rather
      // than as a file Quick Look silently refuses.
      assert((out.length - entry.data.length) % 64 == 0);

      centralDirectory
        ..add(_uint32(0x02014b50)) // central directory header signature
        ..add(_uint16(20)) // version made by
        ..add(_uint16(20)) // version needed to extract
        ..add(_uint16(0)) // general purpose bit flag
        ..add(_uint16(0)) // compression method: stored
        ..add(_uint16(0)) // last mod file time
        ..add(_uint16(0)) // last mod file date
        ..add(_uint32(crc))
        ..add(_uint32(entry.data.length))
        ..add(_uint32(entry.data.length))
        ..add(_uint16(nameBytes.length))
        ..add(_uint16(0)) // extra field length: alignment only matters locally
        ..add(_uint16(0)) // file comment length
        ..add(_uint16(0)) // disk number start
        ..add(_uint16(0)) // internal file attributes
        ..add(_uint32(0)) // external file attributes
        ..add(_uint32(localHeaderOffset))
        ..add(nameBytes);
      centralDirectoryEntries++;
    }

    final centralDirectoryOffset = out.length;
    final centralDirectoryBytes = centralDirectory.toBytes();
    out.add(centralDirectoryBytes);

    out
      ..add(_uint32(0x06054b50)) // end of central directory signature
      ..add(_uint16(0)) // this disk
      ..add(_uint16(0)) // disk with the start of the central directory
      ..add(_uint16(centralDirectoryEntries)) // entries on this disk
      ..add(_uint16(centralDirectoryEntries)) // entries in total
      ..add(_uint32(centralDirectoryBytes.length))
      ..add(_uint32(centralDirectoryOffset))
      ..add(_uint16(0)); // comment length

    return out.toBytes();
  }

  static Uint8List _uint16(int value) =>
      (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List();

  static Uint8List _uint32(int value) =>
      (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

  /// A ZIP filename is a byte string, not necessarily UTF-8 unless a flag
  /// says so; every name this writer produces is already ASCII, so encoding
  /// it as one avoids setting that flag for no reason.
  static Uint8List _ascii(String name) => Uint8List.fromList(name.codeUnits);

  static final Uint32List _crcTable = _buildCrcTable();

  static Uint32List _buildCrcTable() {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      table[n] = c;
    }
    return table;
  }

  /// The standard CRC-32 (IEEE 802.3 / ZIP's own), verified in
  /// `test/usdz_writer_test.dart` against the well-known check value
  /// `crc32("123456789") == 0xCBF43926` — an oracle from outside this file,
  /// not this table checked against itself.
  static int _crc32(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

final class _Entry {
  const _Entry(this.name, this.data);
  final String name;
  final Uint8List data;
}
