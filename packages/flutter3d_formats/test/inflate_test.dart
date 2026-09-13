/// `zlibInflate`/`inflate`: a DEFLATE decompressor with no compressor
/// anywhere in this repository to test it against directly — so this cross-
/// checks against `dart:io`'s own `ZLibCodec` instead, an independent
/// implementation of the same RFC, for every block type it can be made to
/// produce.
///
///     dart test test/inflate_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:test/test.dart';

/// Bits packed DEFLATE's own two ways at once — plain fields
/// least-significant-bit first, Huffman codes most-significant-bit first —
/// for building one exact malformed stream by hand rather than hoping a
/// real encoder's output happens to corrupt into the shape a test wants.
final class _BitWriter {
  final List<int> _bytes = <int>[];
  int _current = 0;
  int _filled = 0;

  void _writeBit(int bit) {
    _current |= (bit & 1) << _filled;
    _filled++;
    if (_filled == 8) {
      _bytes.add(_current);
      _current = 0;
      _filled = 0;
    }
  }

  void bitsLsbFirst(int value, int count) {
    for (var i = 0; i < count; i++) {
      _writeBit((value >> i) & 1);
    }
  }

  void huffmanCode(int code, int length) {
    for (var i = length - 1; i >= 0; i--) {
      _writeBit((code >> i) & 1);
    }
  }

  Uint8List finish() {
    if (_filled > 0) _bytes.add(_current);
    return Uint8List.fromList(_bytes);
  }
}

Uint8List _zlib(List<int> raw, {int level = 6}) =>
    Uint8List.fromList(ZLibCodec(level: level).encode(raw));

void main() {
  group('against dart:io\'s own zlib — an independently written encoder', () {
    test('empty input round-trips', () {
      final data = <int>[];
      expect(zlibInflate(_zlib(data)), data);
    });

    test('a short, highly repetitive run (dynamic Huffman, short back '
        'references)', () {
      final data = List<int>.filled(2000, 42);
      expect(zlibInflate(_zlib(data)), data);
    });

    test('incompressible random-looking bytes (mostly literals)', () {
      // Not `Random` — deterministic, the same reason `mat-11`'s own row
      // rules it out for a bake. A linear congruential sequence is enough
      // to look nothing like a repeating pattern.
      var seed = 12345;
      final data = List<int>.generate(5000, (_) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed & 0xFF;
      });
      expect(zlibInflate(_zlib(data)), data);
    });

    test('a long run past the 258-byte maximum match length, needing more '
        'than one length/distance pair', () {
      final data = List<int>.filled(100000, 7);
      expect(zlibInflate(_zlib(data)), data);
    });

    test('a distance shorter than the length being copied — a run-length '
        'pattern, not a dictionary lookup', () {
      // "abab...ab", which only DEFLATE's own overlapping copy can express
      // as one length/distance pair: distance 2, length far past 2.
      final data = List<int>.generate(4000, (i) => i.isEven ? 65 : 66);
      expect(zlibInflate(_zlib(data)), data);
    });

    test('compression level 0 forces stored blocks', () {
      final data = List<int>.generate(9000, (i) => i & 0xFF);
      expect(zlibInflate(_zlib(data, level: 0)), data);
    });

    test('every byte value, so every literal code in the fixed and '
        'dynamic tables gets exercised at least once', () {
      final data =
          List<int>.generate(256, (i) => i) +
          List<int>.generate(256, (i) => 255 - i);
      expect(zlibInflate(_zlib(data)), data);
    });

    test('every compression level round-trips the same mixed data', () {
      // Mixed literals, short runs and one long run — chosen so every
      // level from 0 (stored) through 9 (most compressed, most dynamic
      // blocks) has something worth compressing and something it cannot.
      var seed = 987;
      final data = <int>[
        for (var i = 0; i < 3000; i++)
          if (i % 50 < 10)
            7 // a run
          else ...[
            () {
              seed = (seed * 1103515245 + 12345) & 0x7fffffff;
              return seed & 0xFF;
            }(),
          ],
      ];
      for (var level = 0; level <= 9; level++) {
        expect(
          zlibInflate(_zlib(data, level: level)),
          data,
          reason: 'level $level',
        );
      }
    });
  });

  group('malformed or truncated input, refused by value', () {
    test('too short to hold a zlib header at all', () {
      expect(zlibInflate(Uint8List.fromList(<int>[0x78])), isNull);
    });

    test('a compression method other than deflate', () {
      final bytes = _zlib(<int>[1, 2, 3]);
      bytes[0] = (bytes[0] & 0xF0) | 0x02; // method 2, not 8
      // Mutation: skip the method check — this is the header's own field
      // saying "not deflate," and reading it as deflate anyway would
      // produce garbage rather than a refusal.
      expect(zlibInflate(bytes), isNull);
    });

    test('a header whose own checksum does not divide by 31', () {
      final bytes = Uint8List.fromList(<int>[0x78, 0x00, 0, 0, 0, 0]);
      expect(zlibInflate(bytes), isNull);
    });

    test('a deflate stream cut off mid-block', () {
      final whole = _zlib(List<int>.filled(3000, 9));
      final cut = Uint8List.sublistView(whole, 0, whole.length - 20);
      expect(zlibInflate(cut), isNull);
    });

    test('a stored block whose length and its own complement disagree', () {
      // BFINAL=1, BTYPE=00 (the 3-bit header, byte-aligned after), then a
      // length of 5 whose complement is written wrong on purpose.
      final bytes = Uint8List.fromList(<int>[
        0x01, 0x05, 0x00, 0x00, 0x00, // length 5, "complement" 0 (wrong)
        1, 2, 3, 4, 5,
      ]);
      expect(inflate(bytes), isNull);
    });

    test('a back-reference reaching before the start of the output', () {
      // Built bit by bit, a fixed-Huffman block (RFC 1951 §3.2.6's own
      // code table) no real encoder would ever emit: one literal ('A'),
      // then a length/distance pair whose distance is far larger than the
      // one byte written so far, then end of block.
      //
      // Mutation: drop `_ByteSink.copyBack`'s own `distance > _length`
      // guard and this reads whatever was in the sink's backing buffer
      // before the write cursor — old heap contents from a previous
      // decode, on a real VM — instead of refusing.
      final writer = _BitWriter()
        ..bitsLsbFirst(1, 1) // BFINAL
        ..bitsLsbFirst(1, 2) // BTYPE = 01, fixed Huffman
        ..huffmanCode(0x30 + 65, 8) // literal 'A' (symbol 65)
        ..huffmanCode(1, 7) // length symbol 257: base 3, 0 extra bits
        ..huffmanCode(29, 5) // distance symbol 29: base 24577
        ..bitsLsbFirst(0, 13) // distance symbol 29's own 13 extra bits
        ..huffmanCode(0, 7); // end-of-block, symbol 256
      expect(inflate(writer.finish()), isNull);
    });
  });
}
