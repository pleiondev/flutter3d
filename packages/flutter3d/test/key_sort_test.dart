import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/src/engine/render/key_sort.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a packed buffer from (key, payload) pairs.
Int64List pack(List<(int, int)> entries) {
  final buffer = Int64List(entries.length);
  for (var i = 0; i < entries.length; i++) {
    buffer[i] = (entries[i].$1 << kPayloadBits) | entries[i].$2;
  }
  return buffer;
}

List<int> payloads(Int64List buffer, int count) =>
    <int>[for (var i = 0; i < count; i++) buffer[i] & kPayloadMask];

List<int> keys(Int64List buffer, int count) =>
    <int>[for (var i = 0; i < count; i++) buffer[i] >> kPayloadBits];

void main() {
  group('packing', () {
    test('key and payload survive a round trip', () {
      final buffer = pack(<(int, int)>[(0x7FFFFFFFFF, kMaxPayload)]);
      expect(buffer[0] >> kPayloadBits, 0x7FFFFFFFFF);
      expect(buffer[0] & kPayloadMask, kMaxPayload);
      // The sign bit must stay clear, otherwise byte-wise ordering would not
      // match numeric ordering.
      expect(buffer[0], greaterThan(0));
    });

    test('the largest key still fits alongside the largest payload', () {
      final maxKey = (1 << kSortKeyBits) - 1;
      final packed = (maxKey << kPayloadBits) | kMaxPayload;
      expect(packed, greaterThan(0), reason: 'no overflow into the sign bit');
      expect(packed >> kPayloadBits, maxKey);
    });
  });

  group('correctness', () {
    // Both paths must agree; the threshold only chooses which is faster.
    for (final (label, sorter) in <(String, void Function(Int64List, Int64List, int))>[
      ('sortPackedKeys', (b, s, c) => sortPackedKeys(b, s, c)),
      ('radixSortPackedKeys', (b, s, c) => radixSortPackedKeys(b, s, c)),
    ]) {
      test('$label orders random entries ascending', () {
        final random = math.Random(11);
        const count = 5000;
        final entries = <(int, int)>[
          for (var i = 0; i < count; i++)
            (random.nextInt(1 << 30), i),
        ];
        final buffer = pack(entries);
        final scratch = Int64List(count);

        sorter(buffer, scratch, count);

        final sortedKeys = keys(buffer, count);
        for (var i = 1; i < count; i++) {
          expect(sortedKeys[i], greaterThanOrEqualTo(sortedKeys[i - 1]));
        }
        // Nothing lost or duplicated.
        expect(payloads(buffer, count).toSet(), hasLength(count));
      });

      test('$label is stable on equal keys', () {
        // Stability is what makes equal keys fall back to submission order, which
        // is how the render list implements its manual sort mode.
        const count = 500;
        final buffer = pack(<(int, int)>[
          for (var i = 0; i < count; i++) (7, i),
        ]);
        final scratch = Int64List(count);

        sorter(buffer, scratch, count);
        expect(payloads(buffer, count), List<int>.generate(count, (i) => i));
      });

      test('$label handles an already sorted run', () {
        const count = 1000;
        final buffer = pack(<(int, int)>[
          for (var i = 0; i < count; i++) (i, i),
        ]);
        final scratch = Int64List(count);
        sorter(buffer, scratch, count);
        expect(payloads(buffer, count), List<int>.generate(count, (i) => i));
      });

      test('$label handles a reversed run', () {
        const count = 1000;
        final buffer = pack(<(int, int)>[
          for (var i = 0; i < count; i++) (count - i, i),
        ]);
        final scratch = Int64List(count);
        sorter(buffer, scratch, count);
        expect(
          payloads(buffer, count),
          List<int>.generate(count, (i) => count - 1 - i),
        );
      });

      test('$label handles keys spanning the full range', () {
        // Exercises every byte lane, including the top one where the skip
        // optimization would otherwise hide a bug.
        final buffer = pack(<(int, int)>[
          (0, 0),
          ((1 << kSortKeyBits) - 1, 1),
          (1 << 34, 2),
          (255, 3),
          (1 << 20, 4),
        ]);
        final scratch = Int64List(5);
        sorter(buffer, scratch, 5);
        expect(payloads(buffer, 5), <int>[0, 3, 4, 2, 1]);
      });
    }

    test('a reused histogram gives the same result', () {
      // The render list passes one buffer every frame; a stale histogram would
      // corrupt the next sort.
      final histogram = Uint32List(256);
      final scratch = Int64List(200);
      final random = math.Random(3);

      for (var round = 0; round < 5; round++) {
        final buffer = pack(<(int, int)>[
          for (var i = 0; i < 200; i++) (random.nextInt(1 << 24), i),
        ]);
        radixSortPackedKeys(buffer, scratch, 200, counts: histogram);
        final sortedKeys = keys(buffer, 200);
        for (var i = 1; i < 200; i++) {
          expect(sortedKeys[i], greaterThanOrEqualTo(sortedKeys[i - 1]));
        }
      }
    });

    test('sorts only the first count entries', () {
      final buffer = pack(<(int, int)>[(3, 0), (1, 1), (2, 2), (99, 3)]);
      final untouched = buffer[3];
      final scratch = Int64List(4);
      radixSortPackedKeys(buffer, scratch, 3);

      expect(payloads(buffer, 3), <int>[1, 2, 0]);
      expect(buffer[3], untouched, reason: 'the tail is left alone');
    });

    test('degenerate counts are no-ops', () {
      final buffer = pack(<(int, int)>[(5, 0)]);
      final scratch = Int64List(1);
      sortPackedKeys(buffer, scratch, 0);
      sortPackedKeys(buffer, scratch, 1);
      expect(buffer[0] & kPayloadMask, 0);
    });
  });

  group('threshold', () {
    test('both sides of the threshold produce identical orderings', () {
      final random = math.Random(5);
      for (final count in <int>[
        kRadixThreshold - 1,
        kRadixThreshold,
        kRadixThreshold + 1,
      ]) {
        final entries = <(int, int)>[
          for (var i = 0; i < count; i++) (random.nextInt(1 << 28), i),
        ];

        final viaDispatch = pack(entries);
        final viaRadix = pack(entries);
        final scratch = Int64List(count);

        sortPackedKeys(viaDispatch, Int64List(count), count);
        radixSortPackedKeys(viaRadix, scratch, count);

        expect(
          payloads(viaDispatch, count),
          payloads(viaRadix, count),
          reason: 'count $count',
        );
      }
    });
  });
}
