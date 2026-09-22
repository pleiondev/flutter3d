/// `fmt-27`: `UsdzWriter` — the zip container's own 64-byte alignment rule,
/// checked byte-for-byte against the field offsets ZIP's own spec defines
/// (not against this writer's own idea of where they are), and the `.usda`
/// text against Box.glb's known geometry.
///
///     dart test test/usdz_writer_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

Uint8List _sample(String relativePath) =>
    File('../flutter3d_samples/assets/$relativePath').readAsBytesSync();

/// One entry read back out of a ZIP byte-for-byte, by hand — independent of
/// [UsdzZip]'s own code, since the point is to check what it actually wrote
/// against the format's own field layout rather than against itself.
class _ZipEntry {
  const _ZipEntry({
    required this.name,
    required this.crc32,
    required this.dataOffset,
    required this.dataLength,
  });
  final String name;
  final int crc32;
  final int dataOffset;
  final int dataLength;
}

List<_ZipEntry> _readLocalEntries(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  final entries = <_ZipEntry>[];
  var at = 0;
  while (at + 4 <= zip.length &&
      data.getUint32(at, Endian.little) == 0x04034b50) {
    final crc = data.getUint32(at + 14, Endian.little);
    final compressedSize = data.getUint32(at + 18, Endian.little);
    final nameLength = data.getUint16(at + 26, Endian.little);
    final extraLength = data.getUint16(at + 28, Endian.little);
    final name = ascii.decode(zip.sublist(at + 30, at + 30 + nameLength));
    final dataOffset = at + 30 + nameLength + extraLength;
    entries.add(
      _ZipEntry(
        name: name,
        crc32: crc,
        dataOffset: dataOffset,
        dataLength: compressedSize,
      ),
    );
    at = dataOffset + compressedSize;
  }
  return entries;
}

void main() {
  group('UsdzZip: the container, independent of what it holds', () {
    test('CRC-32 matches the standard check value for "123456789"', () {
      final zip = UsdzZip();
      zip.store('check', Uint8List.fromList(ascii.encode('123456789')));
      final bytes = zip.build();
      final entries = _readLocalEntries(bytes);

      // Mutation: an off-by-one in the CRC table's polynomial, or reading
      // the final XOR backwards, both produce a plausible-looking but wrong
      // 32-bit number — this is the one external oracle that catches either.
      expect(entries.single.crc32, 0xCBF43926);
    });

    test('every entry\'s data starts on a 64-byte boundary, whatever its '
        'filename length', () {
      final zip = UsdzZip();
      // Three different name lengths, chosen to land the pre-padding
      // offset at different residues mod 64 — a fixed single-entry test
      // could pass by only ever exercising one residue.
      zip
        ..store('a.usda', Uint8List(3))
        ..store('a-somewhat-longer-name.png', Uint8List(17))
        ..store('an-even-longer-file-name-than-that-one.bin', Uint8List(129));
      final bytes = zip.build();
      final entries = _readLocalEntries(bytes);

      expect(entries, hasLength(3));
      // Mutation: compute the padding against the local header's fixed 30
      // bytes alone, forgetting the filename or the extra field's own
      // 4-byte sub-header — either drifts the offset off 64 for exactly
      // the filename lengths chosen not to be multiples of 64 themselves.
      for (final entry in entries) {
        expect(
          entry.dataOffset % 64,
          0,
          reason: '${entry.name} at ${entry.dataOffset}',
        );
      }
    });

    test('the .usda entry is written first', () {
      final zip = UsdzZip();
      zip
        ..store('model.usda', Uint8List(1))
        ..store('texture.png', Uint8List(1));
      final entries = _readLocalEntries(zip.build());
      // Mutation: sort entries alphabetically before writing them —
      // "model.usda" already sorts before "texture.png" by luck, so a
      // reversed pair below is what actually pins the order to "insertion",
      // not "alphabetical".
      expect(entries.first.name, 'model.usda');

      final reversedOrder = UsdzZip()
        ..store('z-layer.usda', Uint8List(1))
        ..store('a-texture.png', Uint8List(1));
      final reversedEntries = _readLocalEntries(reversedOrder.build());
      expect(reversedEntries.first.name, 'z-layer.usda');
    });
  });

  group('UsdzWriter: Box.glb', () {
    test('writes one Mesh prim with the box\'s own vertex and triangle '
        'counts', () async {
      final document = await GltfLoader().load(_sample('Box.glb'));
      final bytes = UsdzWriter(document).write();
      final entries = _readLocalEntries(bytes);
      expect(entries, hasLength(1));
      expect(entries.single.name, 'model.usda');

      final usda = utf8.decode(
        bytes.sublist(
          entries.single.dataOffset,
          entries.single.dataOffset + entries.single.dataLength,
        ),
      );

      expect(usda, startsWith('#usda 1.0'));
      expect(usda, contains('def Mesh'));

      final surface = document.surfaces.single;
      final mesh = surface.mesh;
      // Mutation: write `mesh.vertexCount` points but the wrong number of
      // `faceVertexIndices` (or the reverse) — Box.glb's 24 points and 36
      // indices are different enough numbers that only writing the right
      // one of each passes both.
      final pointMatch = RegExp(
        r'point3f\[\] points = \[([^\]]*)\]',
      ).firstMatch(usda);
      expect(pointMatch, isNotNull);
      final points = pointMatch!.group(1)!.split('), (').length;
      expect(points, mesh.vertexCount);

      final indexMatch = RegExp(
        r'int\[\] faceVertexIndices = \[([^\]]*)\]',
      ).firstMatch(usda);
      expect(indexMatch, isNotNull);
      final indices = indexMatch!.group(1)!.split(', ').length;
      expect(indices, mesh.indices.length);
    });

    test('writing the same document twice is byte-identical', () async {
      final document = await GltfLoader().load(_sample('Box.glb'));
      final first = UsdzWriter(document).write();
      final second = UsdzWriter(document).write();
      expect(first, orderedEquals(second));
    });

    test('a surface name that is not a legal USD identifier is sanitized, '
        'not passed through', () async {
      final document = await GltfLoader().load(_sample('Box.glb'));
      final surface = document.surfaces.single;
      final renamed = ModelSurface(
        mesh: surface.mesh,
        transform: surface.transform,
        materialIndex: surface.materialIndex,
        name: '1 not/a.valid name',
      );
      final withBadName = PlainModelDocument(surfaces: <ModelSurface>[renamed]);
      final usda = utf8.decode(_usdaOf(UsdzWriter(withBadName).write()));
      // Mutation: pass the surface name through unsanitized — this would
      // write `def Mesh "1 not/a.valid name"`, which is not `.usda` a
      // parser can read past the first token of.
      expect(usda, isNot(contains('"1 not/a.valid name"')));
      expect(usda, contains('def Mesh "_1_not_a_valid_name"'));
    });
  });
}

Uint8List _usdaOf(Uint8List zip) {
  final entry = _readLocalEntries(zip).single;
  return zip.sublist(entry.dataOffset, entry.dataOffset + entry.dataLength);
}
