/// A Zstandard stream decompresses to what the real compressor was given —
/// `gfx-78n`.
///
///     dart test test/formats/zstd_test.dart
///
/// **The fixtures were written by the reference compressor, not by this
/// repository.** `zstd -19` produced the three `.zst` files beside this test
/// from payloads a few lines of arithmetic generate, and the arithmetic is
/// repeated here rather than the payloads being committed — so the committed
/// half is the half nothing here can reproduce, and a round trip against our
/// own encoder, which would prove nothing, is impossible by construction.
///
/// **Three payloads, because the format has three shapes of block in it.** A
/// gradient makes a compressor reach for Huffman-coded literals; runs of a
/// repeated byte make it reach for matches at short offsets, including the
/// repeat codes; and text makes it reach for both at once. The bring-up found
/// one bug per shape, which is the argument for not testing a single buffer:
/// a wrong predefined match-length table decoded the runs and nothing else, a
/// Huffman table ranked by code length instead of weight decoded the text and
/// nothing else.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/src/formats/ktx2/zstd.dart';
import 'package:test/test.dart';

/// Where the fixtures live, relative to the package root the runner starts in.
const String _fixtures = 'test/formats/fixtures/zstd';

Uint8List _gradient([int n = 4096]) => Uint8List.fromList(<int>[
  for (var i = 0; i < n; i++) (i * 37 + (i >> 5)) & 255,
]);

Uint8List _runs([int n = 6000]) {
  final out = <int>[];
  var i = 0;
  while (out.length < n) {
    out.addAll(List<int>.filled((i % 17) + 1, i & 255));
    i++;
  }
  return Uint8List.fromList(out.sublist(0, n));
}

Uint8List _text([int n = 9000]) {
  const words = <String>[
    'window ',
    'light ',
    'rectangle ',
    'form ',
    'factor ',
    'zstd ',
  ];
  final out = <int>[];
  var i = 0;
  while (out.length < n) {
    out.addAll(words[(i * 7) % words.length].codeUnits);
    i++;
  }
  return Uint8List.fromList(out.sublist(0, n));
}

Uint8List _fixture(String name) =>
    File('$_fixtures/$name.zst').readAsBytesSync();

void main() {
  test('a gradient comes back byte for byte', () {
    expect(zstdDecode(_fixture('gradient')), orderedEquals(_gradient()));
  });

  test('runs come back byte for byte', () {
    // Short offsets and long matches, which is where the three repeat-offset
    // codes are exercised — the ones whose meaning changes when a sequence has
    // no literals in front of it.
    expect(zstdDecode(_fixture('runs')), orderedEquals(_runs()));
  });

  test('text comes back byte for byte', () {
    // Huffman-coded literals, whose weights are themselves entropy-coded here.
    expect(zstdDecode(_fixture('text')), orderedEquals(_text()));
  });

  test('the size hint does not change the answer', () {
    // It is an allocation hint and nothing else, so a wrong one must not be
    // able to truncate or pad a level.
    final right = zstdDecode(_fixture('runs'), sizeHint: 6000);
    final tooSmall = zstdDecode(_fixture('runs'), sizeHint: 4);
    final tooBig = zstdDecode(_fixture('runs'), sizeHint: 1 << 20);
    expect(right, orderedEquals(_runs()));
    expect(tooSmall, orderedEquals(_runs()));
    expect(tooBig, orderedEquals(_runs()));
  });

  test('a stream that is not zstd comes back null', () {
    expect(zstdDecode(Uint8List.fromList(<int>[1, 2, 3, 4, 5])), isNull);
    expect(zstdDecode(Uint8List(0)), isNull);
  });

  test('a truncated stream comes back null rather than throwing', () {
    // The convention `zlibInflate` set: a caller sniffing a container has one
    // shape to check, and a corrupt texture must not take a frame down.
    final whole = _fixture('text');
    for (final cut in <int>[1, 4, 8, whole.length ~/ 2]) {
      expect(
        zstdDecode(Uint8List.sublistView(whole, 0, cut)),
        isNull,
        reason: 'cut to $cut bytes',
      );
    }
  });

  test('clipping the trailing checksum still gives the content', () {
    // **Not a gap found by accident — the library says so at the top.** The
    // four-byte content checksum is parsed past and not verified, so a file
    // missing it decodes anyway. This test exists to make that a statement
    // somebody chose rather than a surprise somebody hits: the frame's data is
    // already complete before those bytes, and a decoder that verified them
    // would be rejecting a file whose pixels are intact.
    //
    // The first version of the test above asserted the opposite and failed,
    // which is how the property got written down.
    final whole = _fixture('text');
    expect(
      zstdDecode(Uint8List.sublistView(whole, 0, whole.length - 1)),
      orderedEquals(_text()),
    );
  });

  test('isZstd answers on the magic alone', () {
    expect(isZstd(_fixture('text')), isTrue);
    expect(isZstd(Uint8List.fromList(<int>[0x28, 0xB5, 0x2F])), isFalse);
    expect(isZstd(Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47])), isFalse);
  });
}
