/// A broken `.f3d` is refused as a `.f3d`, whatever is broken in it.
///
///     dart test test/formats/f3d_fuzz_test.dart
///
/// Seeded bit flips and truncations over the committed fixtures, each file
/// read through every table it has. The one answer a caller handles is
/// [F3dFormatException]; a `RangeError`, an `ArgumentError` from a mesh
/// whose counts disagree, or a `FormatException` from a string that is not
/// UTF-8 is a reader that let a hostile header through.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

/// Every table [document] reads lazily, read.
void _readAll(F3dDocument document) {
  for (final surface in document.surfaces) {
    surface.mesh.vertices.length;
  }
  document
    ..materials
    ..images
    ..nodes
    ..animations
    ..skins
    ..lights
    ..cameras
    ..warnings
    ..asset
    ..variants
    ..programs
    ..prefabs
    ..files
    ..physicalMaterials
    ..extraSections;
}

void main() {
  for (final name in <String>[
    'v1/box.f3d',
    'v2/bundle.f3d',
    'v2/everything.f3d',
  ]) {
    test('$name, flipped and cut, fails only as a .f3d', () {
      final original = File('test/fixtures/$name').readAsBytesSync();
      final random = Random(name.length);
      final escaped = <String>[];
      for (var round = 0; round < 1500; round++) {
        final bytes = Uint8List.fromList(original);
        final Uint8List input;
        if (round % 5 == 0) {
          input = Uint8List.sublistView(bytes, 0, random.nextInt(bytes.length));
        } else {
          // One round in three flips only the header and the directory,
          // where a count or an entry size is multiplied out.
          final span = round % 3 == 0
              ? min(bytes.length, f3dHeaderBytes + 40 * f3dSectionEntryBytesV2)
              : bytes.length;
          for (var flip = 0; flip < 1 + random.nextInt(8); flip++) {
            bytes[random.nextInt(span)] ^= 1 << random.nextInt(8);
          }
          input = bytes;
        }
        try {
          _readAll(F3dDocument.parse(input));
        } on F3dFormatException {
          // The one refusal a caller handles.
        } on Object catch (error) {
          // Mutation: read a string with a bare `utf8.decode`, or build a
          // mesh without `_built`, and a round lands here.
          escaped.add('round $round: ${error.runtimeType}: $error');
        }
      }
      expect(escaped, isEmpty);
    });
  }

  test('a directory entry size that multiplies past an int is refused', () {
    final bytes = Uint8List.fromList(
      File('test/fixtures/v2/box.f3d').readAsBytesSync(),
    );
    ByteData.sublistView(bytes)
      ..setUint32(8, 0xFFFFFFFF, Endian.little)
      ..setUint32(12, 0xFFFFFFFF, Endian.little);
    // Mutation: multiply `sectionCount * entryBytes` and compare, and on
    // the VM the product of two u32 words passes the bound.
    expect(() => F3dDocument.parse(bytes), throwsA(isA<F3dFormatException>()));
    ByteData.sublistView(bytes)
      ..setUint32(8, 1, Endian.little)
      ..setUint32(12, f3dMaxSectionEntryBytes + 4, Endian.little);
    expect(
      () => F3dDocument.parse(bytes),
      throwsA(
        isA<F3dFormatException>().having(
          (F3dFormatException e) => e.message,
          'message',
          contains('$f3dMaxSectionEntryBytes'),
        ),
      ),
    );
  });
}
